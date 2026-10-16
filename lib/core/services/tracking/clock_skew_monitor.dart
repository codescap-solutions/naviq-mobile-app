import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/tracking/post_outcome.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The backend's verdict that THIS phone's clock is wrong, as seen by the child app.
class ClockSkewStatus {
  final DateTime detectedAt;

  /// Seconds the phone is BEHIND the server (negative = ahead); null if unknown.
  final int? offsetSeconds;

  const ClockSkewStatus({required this.detectedAt, this.offsetSeconds});
}

/// Remembers a confirmed `CLOCK_SKEW` refusal so the child screen can ask the
/// child to enable automatic date & time, and forgets it as soon as the server
/// accepts a live point again (the same condition the backend clears its own
/// flag on). It lives in SharedPreferences because the uploads run in the
/// background-service isolate while the prompt is shown by the UI isolate.
///
/// A delayed offline-queue replay is answered with a normal 200 (history), so it
/// can neither raise nor clear this state.
class ClockSkewMonitor {
  static const _atKey = 'clock_skew_detected_at_ms';
  static const _offsetKey = 'clock_skew_offset_s';

  /// Mirrors the backend's flag lifetime: without further posts the prompt
  /// stops showing after this long.
  static const ttl = Duration(minutes: 30);

  static final ClockSkewMonitor instance = ClockSkewMonitor();

  final DateTime Function() _now;

  ClockSkewMonitor({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Feed every location/trip upload answer through here.
  Future<void> observe(BaseResponse response) async {
    try {
      if (classifyPostResponse(response) == PostOutcome.clockSkew) {
        final offset = response.errorData?['clock_offset_seconds'];
        await _record(offset is num ? offset.round() : null);
      } else if (acceptedAsLive(response)) {
        await clear();
      }
    } catch (_) {
      // Bookkeeping must never break an upload.
    }
  }

  Future<void> _record(int? offsetSeconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_atKey, _now().millisecondsSinceEpoch);
    if (offsetSeconds != null) {
      await prefs.setInt(_offsetKey, offsetSeconds);
    } else {
      await prefs.remove(_offsetKey);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_atKey) && !prefs.containsKey(_offsetKey)) return;
    await prefs.remove(_atKey);
    await prefs.remove(_offsetKey);
  }

  /// The active warning, or null when there is none / it has expired.
  /// `reload()` first: the value is written from another isolate.
  Future<ClockSkewStatus?> read() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.reload();
    } catch (_) {}
    final at = prefs.getInt(_atKey);
    if (at == null) return null;
    final detectedAt = DateTime.fromMillisecondsSinceEpoch(at);
    final age = _now().difference(detectedAt);
    // A negative age means the clock moved backwards since detection — it was
    // changed (e.g. fixed), so the old verdict no longer applies.
    if (age.isNegative || age > ttl) return null;
    return ClockSkewStatus(detectedAt: detectedAt, offsetSeconds: prefs.getInt(_offsetKey));
  }
}
