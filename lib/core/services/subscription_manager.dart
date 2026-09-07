import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../app/subscription/models/subscription_plan.dart';
import '../../app/subscription/view_model/subscription_repository.dart';
import '../di/injector.dart';
import '../utils/app_logger.dart';

/// Tracks the signed-in user's subscription state: whether they have any
/// paid entitlement, and which [SubscriptionTier] they are currently on.
///
/// Tier is resolved by matching the RevenueCat customer's active purchased
/// product identifier against the Apple/Google product IDs the backend
/// returns per plan (`SubscriptionRepository.getPlans()`). There is
/// intentionally no separate per-tier RevenueCat entitlement — the single
/// `premium_access` entitlement only tells us "some paid plan is active";
/// the *product id* tells us which one.
class SubscriptionManager extends ChangeNotifier {
  SubscriptionManager._();
  static final SubscriptionManager instance = SubscriptionManager._();

  bool _hasPremiumAccess = false;
  SubscriptionTier _currentTier = SubscriptionTier.starter;

  /// Synchronous check if the user has any paid access.
  /// Kept in sync via [initialize] and [checkAndUpdateStatus].
  bool get hasPremiumAccess => _hasPremiumAccess;

  /// The user's current subscription tier. Defaults to [SubscriptionTier.starter]
  /// (free) until resolved, and whenever no active purchase can be matched
  /// to a known plan.
  SubscriptionTier get currentTier => _currentTier;

  /// Test-only hook to force a tier without going through RevenueCat/backend.
  /// Also used by the debug tier-switcher (see [devices_view.dart]).
  @visibleForTesting
  void debugSetTier(SubscriptionTier tier) {
    _currentTier = tier;
    _hasPremiumAccess = tier != SubscriptionTier.starter;
    notifyListeners();
  }

  /// Should be called during app startup after RevenueCat is configured.
  Future<void> initialize() async {
    try {
      // 1. Check initial status
      await checkAndUpdateStatus();

      // 2. Listen for future updates (e.g., successful purchases)
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        _updateAccessFromInfo(customerInfo);
      });
    } catch (e) {
      AppLogger.error('Failed to initialize SubscriptionManager: $e');
    }
  }

  /// Manually checks RevenueCat for the latest entitlement status.
  Future<bool> checkAndUpdateStatus() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      await _updateAccessFromInfo(customerInfo);
      return _hasPremiumAccess;
    } catch (e) {
      AppLogger.error('Failed to get customer info in SubscriptionManager: $e');
      return false;
    }
  }

  Future<void> _updateAccessFromInfo(CustomerInfo customerInfo) async {
    // Check if the 'premium_access' entitlement is active
    final isActive = customerInfo.entitlements.active.containsKey('premium_access');
    SubscriptionTier resolvedTier = SubscriptionTier.starter;

    if (isActive) {
      final activeProductIds = customerInfo.activeSubscriptions.toSet();
      if (activeProductIds.isNotEmpty) {
        List<SubscriptionPlan>? plans;
        try {
          final response = await injector<SubscriptionRepository>().getPlans();
          plans = response.data;
        } catch (e) {
          AppLogger.error(
            'SubscriptionManager: failed to fetch plans for tier resolution: $e',
          );
        }
        resolvedTier = resolveTierFromProductIds(activeProductIds, plans);
      } else {
        // Entitlement active but no store product behind it — a
        // RevenueCat-dashboard "Grant" (promotional entitlement) rather than
        // a real purchase. Real purchases always populate
        // activeSubscriptions with the store's product id; a promo grant
        // doesn't, since nothing was actually bought. Confirmed live:
        // granting premium_access this way left currentTier stuck at the
        // 'starter' default above even though the entitlement itself was
        // active — gated features (and the floating upgrade banner) never
        // noticed the grant existed. The entitlement is literally named
        // premium_access, so an active grant with nothing to match against
        // is treated as premium outright rather than silently falling back
        // to starter.
        resolvedTier = SubscriptionTier.premium;
      }
    }

    final changed = _hasPremiumAccess != isActive || _currentTier != resolvedTier;
    _hasPremiumAccess = isActive;
    _currentTier = resolvedTier;

    if (changed) {
      AppLogger.info(
        'SubscriptionManager: access=$_hasPremiumAccess tier=${_currentTier.id}',
      );
      notifyListeners();
    }
  }

  /// Pure matching logic, split out from [_updateAccessFromInfo] so it's
  /// unit-testable without constructing a real RevenueCat [CustomerInfo].
  ///
  /// Matches RevenueCat's active purchased product identifiers against the
  /// backend's plan → product-id mapping. Falls back to
  /// [SubscriptionTier.starter] when [plans] is `null` (fetch failed
  /// entirely — nothing to match against). Falls back to
  /// [SubscriptionTier.basic] when [plans] loaded but none matched — a
  /// paying user should never silently lose all access just because the
  /// specific product id couldn't be matched.
  @visibleForTesting
  static SubscriptionTier resolveTierFromProductIds(
    Set<String> activeProductIds,
    List<SubscriptionPlan>? plans,
  ) {
    if (plans == null) return SubscriptionTier.starter;

    for (final plan in plans) {
      final productIds = <String?>{
        plan.monthlyAppleProductId,
        plan.monthlyGoogleProductId,
        plan.yearlyAppleProductId,
        plan.yearlyGoogleProductId,
      }..removeWhere((id) => id == null);

      // Android base-plan-tagged IDs look like "sku:base-plan-id" while
      // the backend may only store "sku" — match by prefix too.
      final matches = productIds.any(
        (id) => activeProductIds.any(
          (active) => active == id || active.startsWith('$id:'),
        ),
      );
      if (matches) return plan.tier;
    }

    return SubscriptionTier.basic;
  }
}
