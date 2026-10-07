import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:child_track/core/utils/structured_logger.dart';
import 'package:child_track/core/utils/parser_utils.dart';
import 'package:child_track/core/services/tracking/geofence_tracking_config.dart';

// ── Geofence model ───────────────────────────────────────────────────────────

enum GeofenceEvent { enter, exit, dwell }

class GeofenceTrigger {
  final String geofenceId;
  final String geofenceName;
  final GeofenceEvent event;
  final double lat;
  final double lng;
  final DateTime timestamp;

  const GeofenceTrigger({
    required this.geofenceId,
    required this.geofenceName,
    required this.event,
    required this.lat,
    required this.lng,
    required this.timestamp,
  });
}

class _GeofenceState {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;

  bool isInside = false;
  DateTime? dwellStartedAt;
  DateTime? lastEnterEmittedAt;
  DateTime? lastExitEmittedAt;

  _GeofenceState({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
  });
}

// ── Engine ───────────────────────────────────────────────────────────────────

/// Client-side geofence engine that checks every incoming GPS point against
/// all registered fences and fires [GeofenceTrigger] events immediately.
///
/// Integrated with native iOS CoreLocation Region Monitoring over Method Channels.
class LocalGeofenceEngine {
  static final LocalGeofenceEngine _instance = LocalGeofenceEngine._();
  factory LocalGeofenceEngine() => _instance;

  final Map<String, _GeofenceState> _fences = {};
  final _controller = StreamController<GeofenceTrigger>.broadcast();
  
  static const MethodChannel _channel = MethodChannel('com.truenyx.naviq/geofence');

  /// Minimum time inside a fence to fire DWELL (seconds).
  int dwellThresholdSeconds;

  /// Buffer added to the exit radius to prevent boundary bouncing (meters).
  double exitBufferMeters;

  /// Cooldown duration to prevent rapid duplicate enter triggers (seconds).
  int enterCooldownSeconds;

  /// Cooldown duration to prevent rapid duplicate exit triggers (seconds).
  int exitCooldownSeconds;

  LocalGeofenceEngine._()
      : dwellThresholdSeconds = 60,
        exitBufferMeters = 20.0,
        enterCooldownSeconds = 30,
        exitCooldownSeconds = 30 {
    _initializeMethodChannel();
  }

  Stream<GeofenceTrigger> get triggers => _controller.stream;

  /// IDs of fences the engine currently considers the device inside.
  /// Used to preserve inside/outside state across a [updateFences] refresh
  /// (otherwise every periodic fence-list refresh would reset `isInside` to
  /// false and spuriously re-fire an ENTER for a child who never left).
  List<String> get insideFenceIds =>
      _fences.values.where((f) => f.isInside).map((f) => f.id).toList();

  // ── Method Channel Listener ────────────────────────────────────────────────

  void _initializeMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      try {
        if (call.method == 'onGeofenceEvent') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final typeStr = args['type'] as String;
          final geofenceId = args['geofenceId'] as String;
          final lat = safeToDouble(args['lat']);
          final lng = safeToDouble(args['lng']);
          final timestamp = args['timestamp'] != null 
              ? DateTime.parse(args['timestamp'] as String) 
              : DateTime.now();

          GeofenceEvent event;
          if (typeStr == 'ENTER') {
            event = GeofenceEvent.enter;
          } else if (typeStr == 'EXIT') {
            event = GeofenceEvent.exit;
          } else {
            event = GeofenceEvent.dwell;
          }

          final fenceName = _fences[geofenceId]?.name ?? 'Unknown';

          // Keep in-memory tracking in sync with native triggers
          if (typeStr == 'ENTER') {
            _fences[geofenceId]?.isInside = true;
          } else if (typeStr == 'EXIT') {
            _fences[geofenceId]?.isInside = false;
          }

          _emit(GeofenceTrigger(
            geofenceId: geofenceId,
            geofenceName: fenceName,
            event: event,
            lat: lat,
            lng: lng,
            timestamp: timestamp,
          ));
          
          StructuredLogger.log(
            LogTag.BG,
            '[LocalGeofenceEngine] Bridged Native iOS Event: $typeStr on $fenceName',
          );
        } else if (call.method == 'onRegionRegistered') {
          final geofenceId = call.arguments as String;
          StructuredLogger.log(LogTag.BG, '[LocalGeofenceEngine] iOS Region Monitored: $geofenceId');
        } else if (call.method == 'onRegionRemoved') {
          final geofenceId = call.arguments as String;
          StructuredLogger.log(LogTag.BG, '[LocalGeofenceEngine] iOS Region Stopped: $geofenceId');
        }
      } catch (e) {
        StructuredLogger.log(
          LogTag.BG,
          '[LocalGeofenceEngine] Error handling native method call',
          error: e,
        );
      }
    });
  }

  // ── Registration ──────────────────────────────────────────────────────────

  void register({
    required String id,
    required String name,
    required double lat,
    required double lng,
    required double radiusMeters,
    bool currentlyInside = false,
  }) {
    _fences[id] = _GeofenceState(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      radiusMeters: radiusMeters,
    )..isInside = currentlyInside;
    StructuredLogger.log(
      LogTag.BG,
      '[GeoEngine] Registered fence "$name" r=${radiusMeters}m (hysteresis exit: r+${exitBufferMeters}m)',
    );
  }

  void unregister(String id) => _fences.remove(id);

  void clearAll() => _fences.clear();

  void updateFences(
    List<Map<String, dynamic>> fenceList, {
    List<String>? currentlyInsideIds,
  }) {
    clearAll();
    final List<Map<String, dynamic>> nativeList = [];

    for (final f in fenceList) {
      final id = f['_id']?.toString() ?? f['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      
      final lat = _toDouble(f['address']?['latitude'] ?? f['lat']);
      final lng = _toDouble(f['address']?['longitude'] ?? f['lng']);
      final radius = _toDouble(f['radius'] ?? 100);
      final name = f['name']?.toString() ?? 'Unknown';

      // Priortization mapping:
      // 1 = Home, 2 = School, 3 = Current Destination, 4 = Frequently Visited, 5 = Others
      int priority = 5;
      final nameLower = name.toLowerCase();
      if (nameLower.contains('home')) {
        priority = 1;
      } else if (nameLower.contains('school')) {
        priority = 2;
      } else if (nameLower.contains('tuition') || nameLower.contains('class') || nameLower.contains('destination')) {
        priority = 3;
      } else if (nameLower.contains('house') || nameLower.contains('frequent')) {
        priority = 4;
      }

      register(
        id: id,
        name: name,
        lat: lat,
        lng: lng,
        radiusMeters: radius,
        currentlyInside: currentlyInsideIds?.contains(id) ?? false,
      );

      nativeList.add({
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'priority': priority,
      });
    }

    _syncToNative(nativeList);
  }

  /// Pushes the geofence list to whichever native OS-level mechanism survives
  /// this app being force-killed: iOS CLCircularRegion monitoring, or Android
  /// GeofencingClient (NativeGeofenceManager.kt). Same channel + method name
  /// on both platforms — only the platform guard differs.
  Future<void> _syncToNative(List<Map<String, dynamic>> list) async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod('syncGeofences', list);
      StructuredLogger.log(
        LogTag.BG,
        '[LocalGeofenceEngine] Synced ${list.length} geofences to native '
        '${defaultTargetPlatform == TargetPlatform.iOS ? "iOS CLCircularRegion" : "Android GeofencingClient"} monitoring',
      );
    } catch (e) {
      StructuredLogger.log(
        LogTag.BG,
        '[LocalGeofenceEngine] Failed to sync geofences to native platform monitoring',
        error: e,
      );
    }
  }

  // ── Processing ────────────────────────────────────────────────────────────

  bool get hasFences => _fences.isNotEmpty;

  /// Smallest (distance to a fence centre − that fence's radius) over all
  /// registered fences, in metres. Negative = inside. Null when none are
  /// registered. Drives the near-fence tracking zone.
  double? nearestEdgeDistanceMeters(double lat, double lng) {
    double? best;
    for (final fence in _fences.values) {
      final edge = _haversine(lat, lng, fence.lat, fence.lng) - fence.radiusMeters;
      if (best == null || edge < best) best = edge;
    }
    return best;
  }

  /// Call on every new GPS position.
  ///
  /// [accuracyMeters] / [capturedAt] (the fix's own timestamp, not "now"):
  /// a coarse fix (e.g. iOS low-power 100–500 m) must not emit a client-side
  /// ENTER/EXIT — it can't say which side of a boundary the child is on, and
  /// the server ignores it as evidence anyway. A cached fix replayed later
  /// must not be stamped "now" either. Both are optional for callers that
  /// have neither (the previous behaviour).
  void processPosition(
    double lat,
    double lng, {
    double? accuracyMeters,
    DateTime? capturedAt,
  }) {
    final now = capturedAt ?? DateTime.now();
    for (final fence in _fences.values) {
      final dist = _haversine(lat, lng, fence.lat, fence.lng);
      if (accuracyMeters != null &&
          accuracyMeters > GeofenceTrackingConfig.reliableAccuracyLimitMeters(fence.radiusMeters)) {
        continue; // coarse fix: cannot decide a boundary crossing
      }

      if (!fence.isInside) {
        // ENTER condition: distance is <= radius
        final inside = dist <= fence.radiusMeters;
        if (inside) {
          // Check enter cooldown
          if (fence.lastEnterEmittedAt != null &&
              now.difference(fence.lastEnterEmittedAt!).inSeconds < enterCooldownSeconds) {
            continue;
          }
          fence.isInside = true;
          fence.dwellStartedAt = now;
          fence.lastEnterEmittedAt = now;
          _emit(GeofenceTrigger(
            geofenceId: fence.id,
            geofenceName: fence.name,
            event: GeofenceEvent.enter,
            lat: lat,
            lng: lng,
            timestamp: now,
          ));
          StructuredLogger.log(
            LogTag.BG,
            '[GeoEngine] ENTER → ${fence.name} (dist: ${dist.toStringAsFixed(1)}m <= r: ${fence.radiusMeters}m)',
          );
        }
      } else {
        // EXIT condition: distance is > radius + exitBufferMeters (Hysteresis)
        final outside = dist > (fence.radiusMeters + exitBufferMeters);
        if (outside) {
          // Check exit cooldown
          if (fence.lastExitEmittedAt != null &&
              now.difference(fence.lastExitEmittedAt!).inSeconds < exitCooldownSeconds) {
            continue;
          }
          fence.isInside = false;
          fence.dwellStartedAt = null;
          fence.lastExitEmittedAt = now;
          _emit(GeofenceTrigger(
            geofenceId: fence.id,
            geofenceName: fence.name,
            event: GeofenceEvent.exit,
            lat: lat,
            lng: lng,
            timestamp: now,
          ));
          StructuredLogger.log(
            LogTag.BG,
            '[GeoEngine] EXIT ← ${fence.name} (dist: ${dist.toStringAsFixed(1)}m > r+buf: ${(fence.radiusMeters + exitBufferMeters)}m)',
          );
        } else {
          // DWELL check for remaining inside
          if (fence.dwellStartedAt != null) {
            final dwellSecs = now.difference(fence.dwellStartedAt!).inSeconds;
            if (dwellSecs >= dwellThresholdSeconds) {
              fence.dwellStartedAt = null; // fire once
              _emit(GeofenceTrigger(
                geofenceId: fence.id,
                geofenceName: fence.name,
                event: GeofenceEvent.dwell,
                lat: lat,
                lng: lng,
                timestamp: now,
              ));
              StructuredLogger.log(
                LogTag.BG,
                '[GeoEngine] DWELL (${dwellSecs}s) at ${fence.name}',
              );
            }
          }
        }
      }
    }
  }

  void dispose() => _controller.close();

  void _emit(GeofenceTrigger t) => _controller.add(t);

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
