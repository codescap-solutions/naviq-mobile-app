/// Tunables for geofence-aware (adaptive) tracking.
///
/// The server decides every ENTRY/EXIT from RELIABLE, FRESH, consistent
/// location evidence (see naviQ-server src/services/geofenceEvidence.js). The
/// device's job is to produce that evidence quickly when — and only when — it
/// matters, without keeping the GPS chip hot all day:
///
///  * Normal / far from every saved place → the existing low-power profiles.
///  * Near a saved place ("near-fence zone") → precise fixes at a modest
///    distance filter, with OS auto-pause still on, so a stationary child
///    costs almost nothing but the first movement across the boundary yields
///    a good fix (not a 100m-accuracy cell/wifi guess).
///  * Right after a native region callback or a server verification probe →
///    a short "boost": high accuracy, small filter, no auto-pause, plus a few
///    explicit fresh fixes posted immediately. It ends by itself.
class GeofenceTrackingConfig {
  const GeofenceTrackingConfig._();

  /// A device within (fence radius + this) of a saved place's centre is in the
  /// near-fence zone. Covers approaching a place and lingering just outside it.
  static const double nearFenceBufferMeters = 300;

  /// Leave the zone only once this much farther out (hysteresis — avoids
  /// restarting the location stream every time GPS jitters at the zone edge).
  static const double nearFenceExitExtraMeters = 75;

  /// iOS/Android distance filter while in the near-fence zone and not moving
  /// fast enough for the walking/vehicle profiles. Small enough to catch a
  /// real crossing of a typical 50–150 m fence, big enough to stay quiet when
  /// the child is simply sitting still.
  static const int nearFenceDistanceFilterMeters = 20;

  /// Boost (after a native region callback or a server probe).
  static const Duration boostDuration = Duration(minutes: 3);
  static const int boostDistanceFilterMeters = 5;
  static const Duration boostInterval = Duration(seconds: 5);

  /// Explicit fresh fixes taken right after a native region callback / probe,
  /// each posted immediately. Gives the server >=2 consistent fresh points
  /// within roughly its confirmation dwell.
  static const List<Duration> freshFixSchedule = [
    Duration.zero,
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  /// How long to wait for any single fresh fix before giving up on it.
  static const Duration freshFixTimeout = Duration(seconds: 15);

  /// Mirror of the server's reliable-accuracy rule (scaled by radius, bounded)
  /// — used only to avoid emitting client-side ENTER/EXIT triggers from
  /// obviously coarse fixes. The server remains the authority.
  static double reliableAccuracyLimitMeters(double radiusMeters) {
    final scaled = (radiusMeters > 0 ? radiusMeters : 150) * 0.5;
    return scaled.clamp(40.0, 75.0).toDouble();
  }

  /// Periodic retry of queued (offline/failed) uploads, independent of new
  /// GPS points — a stationary device would otherwise never flush them.
  static const Duration queueFlushInterval = Duration(seconds: 20);
}
