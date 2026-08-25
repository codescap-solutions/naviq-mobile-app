import 'package:flutter_test/flutter_test.dart';
import 'package:child_track/app/subscription/models/subscription_plan.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';

/// Table tests for the per-tier feature matrix defined by the subscription
/// pricing + screen-restriction spec (Free ₹0 / Basic ₹199 / Smart ₹299 /
/// Premium ₹499). Every getter accepts an explicit [tier] override so these
/// don't need to touch RevenueCat or SubscriptionManager.
void main() {
  group('SubscriptionFeatureGate.geofenceLimit', () {
    test('starter allows 1 zone', () {
      expect(
        SubscriptionFeatureGate.geofenceLimit(tier: SubscriptionTier.starter),
        1,
      );
    });
    test('basic allows 3 zones', () {
      expect(
        SubscriptionFeatureGate.geofenceLimit(tier: SubscriptionTier.basic),
        3,
      );
    });
    test('smart allows 7 zones (pricing-sheet value)', () {
      expect(
        SubscriptionFeatureGate.geofenceLimit(tier: SubscriptionTier.smart),
        7,
      );
    });
    test('premium allows 10 zones', () {
      expect(
        SubscriptionFeatureGate.geofenceLimit(tier: SubscriptionTier.premium),
        10,
      );
    });
  });

  group('SubscriptionFeatureGate.tripHistoryWindow', () {
    test('starter is 24 hours', () {
      expect(
        SubscriptionFeatureGate.tripHistoryWindow(tier: SubscriptionTier.starter),
        const Duration(hours: 24),
      );
    });
    test('basic is 3 days', () {
      expect(
        SubscriptionFeatureGate.tripHistoryWindow(tier: SubscriptionTier.basic),
        const Duration(days: 3),
      );
    });
    test('smart is 15 days', () {
      expect(
        SubscriptionFeatureGate.tripHistoryWindow(tier: SubscriptionTier.smart),
        const Duration(days: 15),
      );
    });
    test('premium is 30 days', () {
      expect(
        SubscriptionFeatureGate.tripHistoryWindow(tier: SubscriptionTier.premium),
        const Duration(days: 30),
      );
    });
  });

  group('SubscriptionFeatureGate.canTakeScreenTimeAction', () {
    test('starter is view-only', () {
      expect(
        SubscriptionFeatureGate.canTakeScreenTimeAction(
          tier: SubscriptionTier.starter,
        ),
        isFalse,
      );
    });
    test('basic is view-only', () {
      expect(
        SubscriptionFeatureGate.canTakeScreenTimeAction(
          tier: SubscriptionTier.basic,
        ),
        isFalse,
      );
    });
    test('smart can take action', () {
      expect(
        SubscriptionFeatureGate.canTakeScreenTimeAction(
          tier: SubscriptionTier.smart,
        ),
        isTrue,
      );
    });
    test('premium can take action', () {
      expect(
        SubscriptionFeatureGate.canTakeScreenTimeAction(
          tier: SubscriptionTier.premium,
        ),
        isTrue,
      );
    });
  });

  group('SubscriptionFeatureGate.showsHomePlaybackPromo', () {
    test('only starter sees the playback promo', () {
      expect(
        SubscriptionFeatureGate.showsHomePlaybackPromo(
          tier: SubscriptionTier.starter,
        ),
        isTrue,
      );
      for (final tier in [
        SubscriptionTier.basic,
        SubscriptionTier.smart,
        SubscriptionTier.premium,
      ]) {
        expect(
          SubscriptionFeatureGate.showsHomePlaybackPromo(tier: tier),
          isFalse,
          reason: '$tier should get real playback',
        );
      }
    });
  });

  group('SubscriptionFeatureGate.showsFloatingUpgradeBanner', () {
    test('only starter sees the floating banner', () {
      expect(
        SubscriptionFeatureGate.showsFloatingUpgradeBanner(
          tier: SubscriptionTier.starter,
        ),
        isTrue,
      );
      for (final tier in [
        SubscriptionTier.basic,
        SubscriptionTier.smart,
        SubscriptionTier.premium,
      ]) {
        expect(
          SubscriptionFeatureGate.showsFloatingUpgradeBanner(tier: tier),
          isFalse,
          reason: '$tier should not see the banner',
        );
      }
    });
  });

  group('SubscriptionFeatureGate.helpChannels', () {
    test('starter: email only', () {
      final c = SubscriptionFeatureGate.helpChannels(tier: SubscriptionTier.starter);
      expect(c.email, isTrue);
      expect(c.chat, isFalse);
      expect(c.call, isFalse);
    });
    test('basic: email only', () {
      final c = SubscriptionFeatureGate.helpChannels(tier: SubscriptionTier.basic);
      expect(c.email, isTrue);
      expect(c.chat, isFalse);
      expect(c.call, isFalse);
    });
    test('smart: email + chat, no call', () {
      final c = SubscriptionFeatureGate.helpChannels(tier: SubscriptionTier.smart);
      expect(c.email, isTrue);
      expect(c.chat, isTrue);
      expect(c.call, isFalse);
    });
    test('premium: email + chat + call', () {
      final c = SubscriptionFeatureGate.helpChannels(tier: SubscriptionTier.premium);
      expect(c.email, isTrue);
      expect(c.chat, isTrue);
      expect(c.call, isTrue);
    });
  });

  group('SubscriptionFeatureGate.nextTier', () {
    test('starter -> basic', () {
      expect(
        SubscriptionFeatureGate.nextTier(tier: SubscriptionTier.starter),
        SubscriptionTier.basic,
      );
    });
    test('basic -> smart', () {
      expect(
        SubscriptionFeatureGate.nextTier(tier: SubscriptionTier.basic),
        SubscriptionTier.smart,
      );
    });
    test('smart -> premium', () {
      expect(
        SubscriptionFeatureGate.nextTier(tier: SubscriptionTier.smart),
        SubscriptionTier.premium,
      );
    });
    test('premium -> premium (nothing higher to suggest)', () {
      expect(
        SubscriptionFeatureGate.nextTier(tier: SubscriptionTier.premium),
        SubscriptionTier.premium,
      );
    });
  });
}
