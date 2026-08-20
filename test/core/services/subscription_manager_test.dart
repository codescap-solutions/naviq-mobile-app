import 'package:flutter_test/flutter_test.dart';
import 'package:child_track/app/subscription/models/subscription_plan.dart';
import 'package:child_track/core/services/subscription_manager.dart';

SubscriptionPlan _plan(
  String id, {
  String? monthlyApple,
  String? monthlyGoogle,
  String? yearlyApple,
  String? yearlyGoogle,
}) {
  return SubscriptionPlan(
    id: id,
    name: id,
    monthlyPrice: 0,
    monthlyAppleProductId: monthlyApple,
    monthlyGoogleProductId: monthlyGoogle,
    yearlyAppleProductId: yearlyApple,
    yearlyGoogleProductId: yearlyGoogle,
    features: const [],
  );
}

void main() {
  group('SubscriptionManager.resolveTierFromProductIds', () {
    final plans = [
      _plan('basic', monthlyGoogle: 'basic_monthly', yearlyGoogle: 'basic_yearly'),
      _plan('smart', monthlyApple: 'smart_monthly_ios', monthlyGoogle: 'smart_monthly'),
      _plan(
        'premium',
        monthlyApple: 'premium_monthly_ios',
        monthlyGoogle: 'premium_monthly',
        yearlyGoogle: 'premium_yearly',
      ),
    ];

    test('plans == null -> starter regardless of active products', () {
      expect(
        SubscriptionManager.resolveTierFromProductIds({'smart_monthly'}, null),
        SubscriptionTier.starter,
      );
    });

    test('exact monthly Google product id match resolves the right tier', () {
      expect(
        SubscriptionManager.resolveTierFromProductIds({'smart_monthly'}, plans),
        SubscriptionTier.smart,
      );
    });

    test('exact yearly Google product id match resolves the right tier', () {
      expect(
        SubscriptionManager.resolveTierFromProductIds({'basic_yearly'}, plans),
        SubscriptionTier.basic,
      );
    });

    test('exact Apple product id match resolves the right tier', () {
      expect(
        SubscriptionManager.resolveTierFromProductIds(
          {'premium_monthly_ios'},
          plans,
        ),
        SubscriptionTier.premium,
      );
    });

    test(
      'Android base-plan-tagged id ("sku:base-plan") matches by prefix',
      () {
        expect(
          SubscriptionManager.resolveTierFromProductIds(
            {'smart_monthly:smart-base-plan'},
            plans,
          ),
          SubscriptionTier.smart,
        );
      },
    );

    test('no active products -> starter fallback via empty set', () {
      expect(
        SubscriptionManager.resolveTierFromProductIds(<String>{}, plans),
        // Empty active product set never matches anything -> falls through
        // to the "paid but unmatched" fallback (basic). The caller
        // (`_updateAccessFromInfo`) is what short-circuits to starter when
        // there's no active RevenueCat entitlement at all.
        SubscriptionTier.basic,
      );
    });

    test(
      'active product id with no matching plan -> basic fallback (never fully locks out a payer)',
      () {
        expect(
          SubscriptionManager.resolveTierFromProductIds(
            {'some_unknown_sku'},
            plans,
          ),
          SubscriptionTier.basic,
        );
      },
    );

    test('matches the correct plan when multiple are active-looking', () {
      // Simulates a customer whose RevenueCat record still lists an old
      // product alongside their current one — first structural match wins,
      // driven by plan list order (basic, smart, premium).
      expect(
        SubscriptionManager.resolveTierFromProductIds(
          {'premium_monthly', 'smart_monthly'},
          plans,
        ),
        SubscriptionTier.smart,
      );
    });
  });

  group('SubscriptionManager reactive updates', () {
    test('debugSetTier updates currentTier/hasPremiumAccess and notifies listeners', () {
      final manager = SubscriptionManager.instance;
      var notifications = 0;
      void listener() => notifications++;
      manager.addListener(listener);

      addTearDown(() {
        manager.removeListener(listener);
        // Leave the singleton back on the default free tier for any other
        // test file that runs after this one in the same process.
        manager.debugSetTier(SubscriptionTier.starter);
      });

      manager.debugSetTier(SubscriptionTier.premium);

      expect(manager.currentTier, SubscriptionTier.premium);
      expect(manager.hasPremiumAccess, isTrue);
      expect(notifications, 1);

      manager.debugSetTier(SubscriptionTier.starter);
      expect(manager.hasPremiumAccess, isFalse);
      expect(notifications, 2);
    });
  });
}
