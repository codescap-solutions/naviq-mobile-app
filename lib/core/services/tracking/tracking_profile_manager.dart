import 'package:child_track/core/services/tracking/geofence_tracking_config.dart';
import 'package:geolocator/geolocator.dart';

/// Adaptive tracking profiles — interval + distance filter change based on
/// detected activity mode to balance accuracy against battery.
enum TrackingProfile { walking, vehicle, still }

class TrackingProfileConfig {
  final Duration interval;
  final int distanceFilter; // metres
  final String label;

  const TrackingProfileConfig({
    required this.interval,
    required this.distanceFilter,
    required this.label,
  });
}

class TrackingProfileManager {
  static const _profiles = {
    TrackingProfile.walking: TrackingProfileConfig(
      interval: Duration(seconds: 5),
      distanceFilter: 5,
      label: 'Walking',
    ),
    TrackingProfile.vehicle: TrackingProfileConfig(
      interval: Duration(seconds: 3),
      distanceFilter: 5,
      label: 'Vehicle',
    ),
    TrackingProfile.still: TrackingProfileConfig(
      interval: Duration(seconds: 15),
      distanceFilter: 5,
      label: 'Still',
    ),
  };

  TrackingProfile _current = TrackingProfile.still;

  // ── Geofence-aware tracking (adaptive; see GeofenceTrackingConfig) ───────
  bool _nearFence = false;
  DateTime? _boostUntil;

  bool get nearFence => _nearFence;
  bool get boostActive => _boostUntil != null && DateTime.now().isBefore(_boostUntil!);

  /// Enter/leave the near-fence zone. Returns true if the effective stream
  /// settings changed (caller restarts the location stream).
  bool setNearFence(bool value) {
    if (value == _nearFence) return false;
    _nearFence = value;
    return _current == TrackingProfile.still; // walking/vehicle are already precise
  }

  /// Start (or extend) a boost. Returns true if it was not already active.
  bool startBoost([Duration? duration]) {
    final wasActive = boostActive;
    _boostUntil = DateTime.now().add(duration ?? GeofenceTrackingConfig.boostDuration);
    return !wasActive;
  }

  /// Clears an expired boost. Returns true if one just ended.
  bool expireBoostIfDue() {
    if (_boostUntil != null && !boostActive) {
      _boostUntil = null;
      return true;
    }
    return false;
  }

  /// Engineering label sent with location posts (diagnostics only).
  String get effectiveProfileLabel => boostActive
      ? 'boost'
      : (_nearFence && _current == TrackingProfile.still)
          ? 'still_near_fence'
          : _current.name;

  TrackingProfile get currentProfile => _current;
  TrackingProfileConfig get currentConfig => _profiles[_current]!;

  /// Update profile based on detected speed (m/s). Returns true if changed.
  bool updateFromSpeed(double speedMs) {
    final next = _profileFromSpeed(speedMs);
    if (next == _current) return false;
    _current = next;
    return true;
  }

  /// Force a specific profile (e.g. from Activity Recognition).
  bool setProfile(TrackingProfile profile) {
    if (profile == _current) return false;
    _current = profile;
    return true;
  }

  static TrackingProfile _profileFromSpeed(double speedMs) {
    if (speedMs > 5.0) return TrackingProfile.vehicle;
    if (speedMs > 0.6) return TrackingProfile.walking;
    return TrackingProfile.still;
  }

  /// Build [AndroidSettings] for the current profile.
  AndroidSettings buildAndroidSettings() {
    final cfg = currentConfig;
    final boost = boostActive;
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: boost
          ? GeofenceTrackingConfig.boostDistanceFilterMeters
          : (_nearFence && _current == TrackingProfile.still)
              ? GeofenceTrackingConfig.nearFenceDistanceFilterMeters
              : cfg.distanceFilter,
      forceLocationManager: false, // ← Fused Location Provider
      intervalDuration: boost
          ? GeofenceTrackingConfig.boostInterval
          : (_nearFence && _current == TrackingProfile.still)
              ? const Duration(seconds: 10)
              : cfg.interval,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'NaviQ Active',
        notificationText: 'Tracking location...',
        notificationIcon: AndroidResource(name: 'ic_launcher'),
      ),
    );
  }

  /// Build [AppleSettings] for the current profile.
  ///
  /// The `still` profile gets a genuinely low-power config — confirmed
  /// (2026-08-16) as the main iOS battery-drain source: with
  /// pauseLocationUpdatesAutomatically:false and LocationAccuracy.high
  /// applied even while stationary, CoreLocation's GPS chip never sleeps —
  /// a child sitting still for hours (asleep, in class) kept it running at
  /// max precision the whole time. `walking`/`vehicle` are untouched (same
  /// high accuracy, no auto-pause) since those only run while the child is
  /// actually moving, where full precision matters and there's nothing to
  /// pause. Safe to relax `still` specifically because:
  ///  - pauseLocationUpdatesAutomatically:true only pauses once iOS's own
  ///    motion coprocessor confirms no movement, and resumes automatically
  ///    (fast, motion-triggered) the moment real movement starts — trip
  ///    start detection isn't meaningfully delayed.
  ///  - Geofence entry/exit uses a separate OS-level region-monitoring API,
  ///    independent of this position stream — unaffected either way.
  ///
  /// Near a saved place (or briefly after a region callback / server probe)
  /// the `still` profile is upgraded: HIGH accuracy (a 100 m "medium" fix can't
  /// say which side of a 50 m fence the child is on, so the server rightly
  /// refuses to act on it) with a small distance filter. Near-fence keeps
  /// OS auto-pause ON (a stationary child still costs ~nothing); a boost
  /// turns auto-pause off for its short, time-boxed window only.
  AppleSettings buildAppleSettings() {
    final cfg = currentConfig;
    final isStill = _current == TrackingProfile.still;
    final boost = boostActive;
    final precise = boost || (isStill && _nearFence);
    return AppleSettings(
      accuracy: (isStill && !precise) ? LocationAccuracy.medium : LocationAccuracy.high,
      activityType: _current == TrackingProfile.vehicle
          ? ActivityType.automotiveNavigation
          : ActivityType.fitness,
      distanceFilter: boost
          ? GeofenceTrackingConfig.boostDistanceFilterMeters
          : precise
              ? GeofenceTrackingConfig.nearFenceDistanceFilterMeters
              : (isStill ? 75 : cfg.distanceFilter),
      pauseLocationUpdatesAutomatically: isStill && !boost,
      showBackgroundLocationIndicator: true,
    );
  }

  static TrackingProfileConfig configFor(TrackingProfile p) => _profiles[p]!;
}
