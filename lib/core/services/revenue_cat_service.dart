import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../utils/app_logger.dart';
import 'subscription_manager.dart';

/// Wraps all RevenueCat SDK interactions.
/// Call [initialize] once in main(), then [logIn] after login and
/// [logOut] before clearing session.
class RevenueCatService {
  RevenueCatService._();
  static final RevenueCatService instance = RevenueCatService._();

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      final apiKey = Platform.isIOS
          ? dotenv.env['APPLE_API_KEY']
          : dotenv.env['PLAYSTORE_API_KEY'];

      if (apiKey == null ||
          apiKey.isEmpty ||
          apiKey.startsWith('appl_REPLACE') ||
          apiKey.startsWith('goog_REPLACE')) {
        AppLogger.warning(
          'RevenueCat: API key not configured in .env — purchases disabled.',
        );
        return;
      }

      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.error);

      final config = PurchasesConfiguration(apiKey);
      await Purchases.configure(config);

      AppLogger.info('RevenueCat: Initialized successfully.');
    } catch (e, st) {
      AppLogger.error('RevenueCat init error: $e', e, st);
    }
  }

  // ── User Identity ─────────────────────────────────────────────────────────

  /// Call after successful login with your backend's user ID.
  /// [displayName] and [phoneNumber], when given, are tagged as subscriber
  /// attributes so the RevenueCat dashboard shows who a customer is instead
  /// of just their raw App User ID.
  Future<void> logIn(
    String userId, {
    String? displayName,
    String? phoneNumber,
  }) async {
    try {
      await Purchases.logIn(userId);
      AppLogger.info('RevenueCat: Logged in as $userId');

      if (displayName != null && displayName.isNotEmpty) {
        await Purchases.setDisplayName(displayName);
      }
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        await Purchases.setPhoneNumber(phoneNumber);
      }

      // SubscriptionManager.initialize() only ever checks status once, at
      // cold start in main() — before this identity swap even runs (it's
      // called later, once auth/session data is available). Purchases.logIn
      // alone doesn't push a CustomerInfo update through the SDK's listener
      // when there's no new *delta* to report (e.g. a promo entitlement
      // granted via the RevenueCat dashboard between sessions), so without
      // this, SubscriptionManager's cached tier can stay wrong — "starter"
      // — for the rest of the app's lifetime even though the account is
      // actually entitled. Confirmed live: a manually-granted premium
      // account still hit the free-tier geofence cap after a full
      // force-quit/reopen, because this identity swap never re-triggered
      // the tier check on its own.
      await SubscriptionManager.instance.checkAndUpdateStatus();
    } catch (e) {
      AppLogger.error('RevenueCat logIn error: $e');
    }
  }

  /// Call on logout before clearing local session.
  Future<void> logOut() async {
    try {
      await Purchases.logOut();
      AppLogger.info('RevenueCat: Logged out.');
    } catch (e) {
      AppLogger.error('RevenueCat logOut error: $e');
    }
  }

  // ── Offerings ─────────────────────────────────────────────────────────────

  /// Fetches the current offerings from RevenueCat.
  /// Returns null on error.
  Future<Offerings?> getOfferings() async {
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      AppLogger.error('RevenueCat getOfferings error: $e');
      return null;
    }
  }

  // ── Purchasing ────────────────────────────────────────────────────────────

  /// Triggers the native OS payment sheet for [pkg].
  /// Uses the modern SDK API — not deprecated purchasePackage.
  /// Throws [PurchasesErrorCode] on failure.
  Future<CustomerInfo> purchasePackage(Package pkg) async {
    final result = await Purchases.purchasePackage(pkg);
    return result;
  }

  /// Triggers the native OS payment sheet for a specific product ID.
  /// Fetches the product from the store first.
  Future<CustomerInfo> purchaseProductById(String productId) async {
    final offerings = await getOfferings();
    log("offerings ${offerings?.all}");

    if (offerings == null || offerings.all.isEmpty) {
      throw Exception('No offerings configured in RevenueCat.');
    }

    final currentOffering = offerings.current ?? offerings.all.values.first;

    try {
      // Find the package inside the offering whose store product identifier
      // exactly matches the productId (works for both iOS and Android).
      final packageToBuy = currentOffering.availablePackages.firstWhere(
        (pkg) => pkg.storeProduct.identifier == productId,
      );

      log("Found package to buy: ${packageToBuy.identifier}");
      return await Purchases.purchasePackage(packageToBuy);
    } catch (_) {
      throw Exception('Product $productId not found in RevenueCat Offering.');
    }
  }

  // ── Customer Info ─────────────────────────────────────────────────────────

  Future<CustomerInfo?> getCustomerInfo() async {
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      AppLogger.error('RevenueCat getCustomerInfo error: $e');
      return null;
    }
  }
}
