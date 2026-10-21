import 'dart:io' show Platform;

import 'package:child_track/core/constants/app_build_info.dart';
import 'package:geolocator/geolocator.dart';

/// The fix's speed in m/s, or `null` when the platform supplied none.
///
/// geolocator reports `speed == 0.0` both for a genuine measured standstill AND
/// when the OS gave no speed at all (Android omits it for network fixes and
/// pre-O devices; iOS omits invalid readings), so a bare 0 proves nothing. A
/// zero only counts as measured when the fix also carries a positive
/// `speedAccuracy`. Negative / non-finite values are always unknown.
///
/// Unknown must never be sent as "0 m/s": the backend's drive-by arrival guard
/// treats only a KNOWN slow speed as proof the child has stopped.
double? knownSpeedMps(Position p) {
  final s = p.speed;
  if (!s.isFinite || s < 0) return null;
  if (s > 0) return s;
  return p.speedAccuracy > 0 ? 0.0 : null;
}

/// Payload fields for a fix's speed. Older backends ignore `speed_known`; an
/// omitted `speed` is read as "no speed" by both old and new servers.
Map<String, dynamic> speedFields(Position p, {bool legacyAlias = true}) {
  final v = knownSpeedMps(p);
  if (v == null) return {'speed_known': false};
  return {'speed_mps': v, if (legacyAlias) 'speed': v, 'speed_known': true};
}

/// Engineering diagnostics attached to a location post (never shown to a
/// parent, never used for a decision): where the fix came from and which build.
Map<String, dynamic> locationDiagnostics({
  required String fixSource,
  String? trackingProfile,
}) => {
  'platform': Platform.isIOS ? 'ios' : 'android',
  'fix_source': fixSource,
  if (trackingProfile != null) 'tracking_profile': trackingProfile,
  'app_version': AppBuildInfo.version,
  'app_build': AppBuildInfo.build,
};

/// The location posted in answer to a server FORCE_REFRESH_DATA / geofence-probe
/// push. Speed follows [speedFields] (unknown stays unknown); `refresh_request_id`
/// echoes the server's request id so the probe → response pair can be correlated.
Map<String, dynamic> forceRefreshLocationPayload({
  required String childId,
  required Position fix,
  required bool geofenceProbe,
  String? requestId,
}) => {
  'child_id': childId,
  'lat': fix.latitude,
  'lng': fix.longitude,
  'accuracy_m': fix.accuracy,
  ...speedFields(fix, legacyAlias: false),
  'bearing': fix.heading < 0 ? 0.0 : fix.heading,
  'timestamp': fix.timestamp.toUtc().toIso8601String(),
  ...locationDiagnostics(
    fixSource: geofenceProbe ? 'geofence_probe' : 'force_refresh',
    trackingProfile: geofenceProbe ? 'probe' : 'force_refresh',
  ),
  if (requestId != null && requestId.isNotEmpty)
    'refresh_request_id': requestId,
};
