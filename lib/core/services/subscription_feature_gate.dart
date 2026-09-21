import '../../app/subscription/models/subscription_plan.dart';
import 'subscription_manager.dart';

/// Which support channels a tier is allowed to use directly (see
/// [SubscriptionFeatureGate.helpChannels]). A disallowed channel should
/// still be visible in the UI, just gated behind an upgrade prompt on tap.
class HelpChannels {
  final bool email;
  final bool chat;
  final bool call;

  const HelpChannels({
    required this.email,
    required this.chat,
    required this.call,
  });
}

/// Single source of truth for the per-tier feature matrix (Free/Basic/Smart/
/// Premium), sourced from the subscription pricing + screen-restriction
/// spec. Every gated screen should read limits/flags from here instead of
/// hardcoding tier comparisons, so the matrix only needs to change in one
/// place.
///
/// All getters optionally accept a [tier] override (defaults to the current
/// user's tier via [SubscriptionManager]) so this class is testable without
/// mocking RevenueCat.
class SubscriptionFeatureGate {
  const SubscriptionFeatureGate._();

  static SubscriptionTier get _currentTier => SubscriptionManager.instance.currentTier;

  /// Max number of geofence zones the tier may create.
  /// NOTE: the pricing sheet lists Smart = 7; a separate internal
  /// restriction-logic sheet lists Smart = 3 (same as Basic). Using 7 (the
  /// customer-facing number) per product decision — flagged for spec
  /// cleanup, see plan notes.
  static int geofenceLimit({SubscriptionTier? tier}) {
    switch (tier ?? _currentTier) {
      case SubscriptionTier.starter:
        return 1;
      case SubscriptionTier.basic:
        return 3;
      case SubscriptionTier.smart:
        return 7;
      case SubscriptionTier.premium:
        return 10;
    }
  }

  /// How far back location/trip history is browsable.
  static Duration tripHistoryWindow({SubscriptionTier? tier}) {
    switch (tier ?? _currentTier) {
      case SubscriptionTier.starter:
        return const Duration(hours: 24);
      case SubscriptionTier.basic:
        return const Duration(days: 3);
      case SubscriptionTier.smart:
        return const Duration(days: 15);
      case SubscriptionTier.premium:
        return const Duration(days: 30);
    }
  }

  /// Free & Basic can only view app-usage/screen-time data; Smart & Premium
  /// can also take action (lock apps, set/remove time limits).
  static bool canTakeScreenTimeAction({SubscriptionTier? tier}) {
    final t = tier ?? _currentTier;
    return t == SubscriptionTier.smart || t == SubscriptionTier.premium;
  }

  /// Free tier sees a static upgrade-promo card instead of real route
  /// playback on the trip detail screen (no ad SDK is integrated).
  static bool showsHomePlaybackPromo({SubscriptionTier? tier}) {
    return (tier ?? _currentTier) == SubscriptionTier.starter;
  }

  /// Which support channels are directly usable for the tier.
  static HelpChannels helpChannels({SubscriptionTier? tier}) {
    switch (tier ?? _currentTier) {
      case SubscriptionTier.starter:
      case SubscriptionTier.basic:
        return const HelpChannels(email: true, chat: false, call: false);
      case SubscriptionTier.smart:
        return const HelpChannels(email: true, chat: true, call: false);
      case SubscriptionTier.premium:
        return const HelpChannels(email: true, chat: true, call: true);
    }
  }

  /// The next tier up from [tier] (current tier by default), used to pick
  /// which plan an upgrade prompt should highlight. Returns `premium` when
  /// already on `premium` (nothing higher to suggest).
  static SubscriptionTier nextTier({SubscriptionTier? tier}) {
    switch (tier ?? _currentTier) {
      case SubscriptionTier.starter:
        return SubscriptionTier.basic;
      case SubscriptionTier.basic:
        return SubscriptionTier.smart;
      case SubscriptionTier.smart:
      case SubscriptionTier.premium:
        return SubscriptionTier.premium;
    }
  }
}
