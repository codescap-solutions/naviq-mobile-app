import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:child_track/core/utils/structured_logger.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/child_location_repo.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/app/childapp/view_model/repository/device_info_service.dart';
import 'package:child_track/core/services/tracking/enhanced_trip_point.dart';
import 'package:child_track/core/services/tracking/activity_recognition_service.dart';
import 'package:child_track/core/services/tracking/trip_classification_engine.dart';
import 'package:child_track/core/services/tracking/stop_detection_service.dart';
import 'package:child_track/core/services/tracking/offline_trip_queue.dart';
import 'package:child_track/core/services/tracking/local_geofence_engine.dart';
import 'package:child_track/core/services/tracking/tracking_config_service.dart';

export 'package:child_track/core/services/tracking/trip_classification_engine.dart'
    show BgTripMode;

enum BgTripState { idle, candidate, tracking }

class LocationStateMachine {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final ChildRepo _childRepo;
  final SharedPrefsService _prefs;
  final Battery _battery;
  final TrackingConfigService _configService;

  // ── New services ──────────────────────────────────────────────────────────
  final ActivityRecognitionService _ar = ActivityRecognitionService();
  final TripClassificationEngine _classifier = TripClassificationEngine();
  late final StopDetectionService _stopDetector;
  final OfflineTripQueue _offlineQueue = OfflineTripQueue();
  final LocalGeofenceEngine _geoEngine = LocalGeofenceEngine();

  StreamSubscription<StopEvent>? _stopSub;
  StreamSubscription<GeofenceTrigger>? _geoTriggerSub;

  // ── State ─────────────────────────────────────────────────────────────────
  Position? _lastPostedLocation;
  BgTripState _state = BgTripState.idle;
  List<Position> _candidatePoints = [];
  bool _isTripTracking = false;
  BgTripMode _tripMode = BgTripMode.unknown;

  DateTime? _lastDrainAttempt;
  DateTime? _lastConfigFetch;
  DateTime? _lastGeofenceFetch;

  LocationStateMachine({
    required ChildRepo childRepo,
    required ChildGoogleMapsRepo locationRepo,
    required SharedPrefsService prefs,
    required TrackingConfigService configService,
    Battery? battery,
  }) : _childRepo = childRepo,
       _prefs = prefs,
       _configService = configService,
       _battery = battery ?? Battery() {
    _stopDetector = StopDetectionService(config: _configService);

    // Start activity recognition
    _ar.start();

    // Listen for local stop events
    _stopSub = _stopDetector.onStop.listen(_onLocalStopDetected);

    // Load offline queue
    _offlineQueue.load();

    // Report client-detected geofence transitions (incl. native iOS region
    // monitoring bridged through this same stream) to the backend immediately,
    // instead of relying solely on the server inferring transitions from the
    // next routine location ping.
    _geoTriggerSub = _geoEngine.triggers.listen(_onGeofenceTrigger);
  }

  void dispose() {
    _ar.stop();
    _stopSub?.cancel();
    _geoTriggerSub?.cancel();
    _stopDetector.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC ENTRY POINT
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> processLocation(Position position) async {
    StructuredLogger.log(
      LogTag.BG,
      'Processing: ${position.latitude},${position.longitude} '
      '| Spd: ${(position.speed * 3.6).toStringAsFixed(1)} km/h '
      '| Acc: ${position.accuracy.toStringAsFixed(1)}m '
      '| Bearing: ${position.heading.toStringAsFixed(0)}°',
    );

    final childId = _prefs.getString('child_id');
    if (childId == null || childId.isEmpty) {
      StructuredLogger.log(LogTag.BG, 'No child_id – skipping');
      return;
    }

    // ── Distance gate (adaptive — respects current profile filter) ──────────
    double distance = 0.0;
    if (_lastPostedLocation != null) {
      distance = Geolocator.distanceBetween(
        _lastPostedLocation!.latitude,
        _lastPostedLocation!.longitude,
        position.latitude,
        position.longitude,
      );
    }

    if (_lastPostedLocation != null && distance < 5) {
      StructuredLogger.log(
        LogTag.BG,
        'Skipped (${distance.toStringAsFixed(1)}m < 5m filter)',
      );
      return;
    }

    _lastPostedLocation = position;

    // ── Local geofence check (immediate, no HTTP) ──────────────────────────
    _geoEngine.processPosition(position.latitude, position.longitude);

    // ── Stop detection ─────────────────────────────────────────────────────
    _ar.updateSpeedFallback(position.speed);
    _stopDetector.processPosition(position, _ar.current);

    // ── Fetch config periodically ──────────────────────────────────────────
    if (_lastConfigFetch == null || DateTime.now().difference(_lastConfigFetch!).inHours >= 1) {
      _lastConfigFetch = DateTime.now();
      _configService.fetchConfigFromServer();
    }

    // ── Refresh geofence list periodically ──────────────────────────────────
    // LocalGeofenceEngine.processPosition() (called above) has nothing to check
    // against until this runs at least once — it starts with zero registered
    // fences. Kept on a short-ish cadence since a parent can add/edit a saved
    // place at any time and the child device should pick it up promptly.
    if (_lastGeofenceFetch == null ||
        DateTime.now().difference(_lastGeofenceFetch!).inMinutes >= 10) {
      _lastGeofenceFetch = DateTime.now();
      _refreshGeofences(childId);
    }

    // ── Post plain location ────────────────────────────────────────────────
    await _postChildLocation(position, childId);

    // ── Trip logic ─────────────────────────────────────────────────────────
    if (_isTripTracking) {
      await _updateTripLocation(position, childId);
    } else {
      await _processTripStartLogic(position, childId);
    }

    // ── Drain offline queue if online ──────────────────────────────────────
    _tryDrainOfflineQueue(childId);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION POSTING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _postChildLocation(Position pos, String childId) async {
    try {
      int batteryLevel = 100;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

      final activityName = _ar.current.type.name;

      final requestBody = {
        'child_id': childId,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'accuracy_m': pos.accuracy,
        'speed': pos.speed < 0 ? 0.0 : pos.speed,
        'speed_mps': pos.speed < 0 ? 0.0 : pos.speed,
        'bearing': pos.heading < 0 ? 0.0 : pos.heading,
        'altitude': pos.altitude,
        'speed_accuracy': pos.speedAccuracy,
        'activity': activityName,
        // pos.timestamp (not DateTime.now()) — the actual moment this fix
        // was captured. On a weak-signal highway stretch, iOS/Android can
        // hand back the same cached CLLocation/FusedLocation fix across
        // several consecutive requests instead of a fresh one; stamping
        // each post with "now" relabeled 4 identical stale coordinates as 4
        // distinct fresh pings ~2-8 min apart, which fed TripStateMachine's
        // displacement check (>30m required) four separate "new" points
        // that were secretly all the same point — the candidate window kept
        // reopening and failing validation every cycle, so a real ~1.2km
        // trip never got confirmed (confirmed real case, Kusuma/585LQP,
        // 2026-09-29). Using the fix's own timestamp means a repeated stale
        // fix carries the SAME timestamp each time instead of a fake new
        // one, so it reads as what it actually is — one old point, not
        // several new ones.
        'timestamp': pos.timestamp.toUtc().toIso8601String(),
        'battery': batteryLevel,
      };

      StructuredLogger.log(LogTag.BG, 'Posting location → $requestBody');
      final response = await _childRepo.postChildLocation(requestBody);
      StructuredLogger.log(
        LogTag.BG,
        'Location post: [${response.statusCode}] ${response.message}',
      );
      StructuredLogger.log(
        LogTag.LOCATION,
        'source=stream lat=${pos.latitude} lng=${pos.longitude} '
        'acc=${pos.accuracy.toStringAsFixed(1)}m status=posted',
        buffered: true,
      );
    } catch (e) {
      StructuredLogger.log(LogTag.BG, 'Failed to post location', error: e);
      String status = 'failed';
      try {
        final int battery = await _battery.batteryLevel;
        await _offlineQueue.enqueueLocation(
          childId: childId,
          payload: {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'accuracy_m': pos.accuracy,
            'speed_mps': pos.speed < 0 ? 0.0 : pos.speed,
            'bearing': pos.heading < 0 ? 0.0 : pos.heading,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'battery': battery,
          },
        );
        status = 'queued';
      } catch (_) {}
      StructuredLogger.log(
        LogTag.LOCATION,
        'source=stream lat=${pos.latitude} lng=${pos.longitude} '
        'acc=${pos.accuracy.toStringAsFixed(1)}m status=$status',
        buffered: true,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRIP START DETECTION  (hybrid — GPS + AR + heading)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _processTripStartLogic(Position location, String childId) async {
    if (location.accuracy > 30.0) {
      StructuredLogger.log(
        LogTag.TRIP,
        'Ignored poor accuracy (${location.accuracy}m)',
      );
      return;
    }

    final classification = _classifier.classify(
      position: location,
      arState: _ar.current,
    );

    List<Position> newWindow = List.from(_candidatePoints)..add(location);
    if (newWindow.length > 15) newWindow.removeAt(0);

    if (newWindow.length > 1) {
      final gap = newWindow.last.timestamp
          .difference(newWindow[newWindow.length - 2].timestamp)
          .inSeconds;
      if (gap > 300) {
        StructuredLogger.log(LogTag.TRIP, 'Gap $gap s – resetting window');
        newWindow = [location];
      }
    }

    if (newWindow.length < 3) {
      _candidatePoints = newWindow;
      _state = BgTripState.candidate;
      return;
    }

    double totalDistance = 0;
    for (int i = 0; i < newWindow.length - 1; i++) {
      totalDistance += Geolocator.distanceBetween(
        newWindow[i].latitude, newWindow[i].longitude,
        newWindow[i + 1].latitude, newWindow[i + 1].longitude,
      );
    }

    final startPt = newWindow.first;
    final endPt = newWindow.last;
    final straightDist = Geolocator.distanceBetween(
      startPt.latitude, startPt.longitude,
      endPt.latitude, endPt.longitude,
    );
    final durationSeconds =
        endPt.timestamp.difference(startPt.timestamp).inSeconds;
    if (durationSeconds < 1) return;

    final avgSpeed = totalDistance / durationSeconds;
    final consistencyRatio =
        totalDistance > 0 ? straightDist / totalDistance : 0.0;

    StructuredLogger.log(
      LogTag.TRIP,
      'Window=${newWindow.length} pts, Dur=${durationSeconds}s, '
      'Dist=${totalDistance.toStringAsFixed(1)}m, '
      'Speed=${(avgSpeed * 3.6).toStringAsFixed(1)}km/h, '
      'AR=${classification.type.name}(${classification.confidence.toStringAsFixed(2)})',
    );

    bool rulesMet = false;
    BgTripMode estimatedMode = BgTripMode.unknown;

    if (avgSpeed >= 0.6 && avgSpeed <= 1.8) {
      if (totalDistance >= 30 && durationSeconds >= 30) {
        estimatedMode = BgTripMode.walking;
        rulesMet = true;
      }
    } else if (avgSpeed > 1.8 && avgSpeed <= 5.0) {
      if (totalDistance >= 60 && durationSeconds >= 20) {
        estimatedMode = BgTripMode.walking;
        rulesMet = true;
      }
    } else if (avgSpeed > 5.0) {
      if (totalDistance >= 100 && durationSeconds >= 20) {
        estimatedMode = BgTripMode.vehicle;
        rulesMet = true;
      }
    }

    if (classification.confidence >= 0.7 &&
        classification.type != NaviQActivityType.stationary &&
        classification.type != NaviQActivityType.unknown) {
      estimatedMode = classification.legacyMode;
      rulesMet = totalDistance >= 20 && durationSeconds >= 20;
    }

    if (rulesMet && consistencyRatio < 0.6) {
      StructuredLogger.log(
        LogTag.TRIP,
        'Rejected – low consistency ($consistencyRatio)',
      );
      rulesMet = false;
    }

    if (rulesMet) {
      StructuredLogger.log(
        LogTag.TRIP,
        'TRIP CONFIRMED! Mode: $estimatedMode',
      );
      await _startTripTracking(estimatedMode, childId);
    } else {
      _candidatePoints = newWindow;
      _state = BgTripState.candidate;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRIP TRACKING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _startTripTracking(BgTripMode mode, String childId) async {
    _isTripTracking = true;
    _tripMode = mode;
    _state = BgTripState.tracking;
    _stopDetector.reset();
    _classifier.reset();

    final pointsToPost = List<Position>.from(_candidatePoints);
    _candidatePoints = [];

    StructuredLogger.log(LogTag.STATE, 'Trip STARTED (mode: $mode)');

    if (pointsToPost.isNotEmpty) {
      await _postTripBatch(pointsToPost, childId);
    }
  }

  void _stopTripTracking() {
    _isTripTracking = false;
    _tripMode = BgTripMode.unknown;
    _state = BgTripState.idle;
    _candidatePoints = [];
    _stopDetector.reset();
    _classifier.reset();
    StructuredLogger.log(LogTag.STATE, 'Trip STOPPED – state reset');
  }

  Future<void> _updateTripLocation(Position pos, String childId) async {
    await _postTripBatch([pos], childId);
  }

  Future<void> _postTripBatch(List<Position> positions, String childId) async {
    if (positions.isEmpty) return;

    int batteryLevel = 0;
    try {
      final infoService = ChildInfoService();
      batteryLevel = await infoService.getBatteryPercentage();
    } catch (_) {
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}
    }

    final enhancedPoints = positions
        .map((p) => EnhancedTripPoint.fromPosition(p, battery: batteryLevel))
        .toList();

    final requestBody = {
      'points': enhancedPoints.map((p) => p.toJson()).toList(),
    };

    StructuredLogger.log(
      LogTag.TRIP,
      'Posting ${positions.length} trip points (enhanced)',
    );

    try {
      final response = await _childRepo.postTripLocation(
        childId: childId,
        data: requestBody,
      );

      StructuredLogger.log(
        LogTag.TRIP,
        'Trip post response: ${response.data}',
      );

      if (response.isSuccess && response.data != null) {
        if (_shouldStopTrip(response.data)) {
          StructuredLogger.log(LogTag.TRIP, 'Backend → STOP signal');
          _stopTripTracking();
        }
      } else {
        await _offlineQueue.enqueuePoints(
          childId: childId,
          points: enhancedPoints,
        );
      }
    } catch (e) {
      StructuredLogger.log(LogTag.TRIP, 'Trip post failed – queuing', error: e);
      await _offlineQueue.enqueuePoints(
        childId: childId,
        points: enhancedPoints,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOCAL STOP DETECTION HANDLER
  // ══════════════════════════════════════════════════════════════════════════

  void _onLocalStopDetected(StopEvent event) {
    if (!_isTripTracking) return;
    StructuredLogger.log(
      LogTag.TRIP,
      '[LocalStop] Stop detected: ${event.duration.inSeconds}s, '
      'r=${event.radiusMeters.toStringAsFixed(1)}m → ending trip locally',
    );
    final childId = _prefs.getString('child_id');
    if (childId != null && childId.isNotEmpty) {
      _postTripEnd(childId, event.detectedAt);
    }
    _stopTripTracking();
  }

  Future<void> _postTripEnd(String childId, DateTime endedAt) async {
    final payload = {'ended_at': endedAt.toIso8601String()};
    try {
      final response = await _childRepo.postTripEnd(childId: childId, data: payload);
      if (!response.isSuccess) {
        await _offlineQueue.enqueueTripEnd(childId: childId, endedAt: endedAt);
      }
    } catch (_) {
      await _offlineQueue.enqueueTripEnd(childId: childId, endedAt: endedAt);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOCAL GEOFENCE REPORTING (client-side ENTER/EXIT/DWELL → backend, immediately)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _refreshGeofences(String childId) async {
    try {
      final response = await _childRepo.getChildGeofences(childId);
      if (response.isSuccess && response.data != null) {
        final fenceList = response.data!
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _geoEngine.updateFences(
          fenceList,
          currentlyInsideIds: _geoEngine.insideFenceIds,
        );
        StructuredLogger.log(
          LogTag.BG,
          '[Geofence] Refreshed ${fenceList.length} fences from server',
        );
      }
    } catch (e) {
      StructuredLogger.log(LogTag.BG, '[Geofence] Failed to refresh fences', error: e);
    }
  }

  void _onGeofenceTrigger(GeofenceTrigger trigger) {
    final childId = _prefs.getString('child_id');
    if (childId == null || childId.isEmpty) return;

    final eventType = switch (trigger.event) {
      GeofenceEvent.enter => 'ENTER',
      GeofenceEvent.exit => 'EXIT',
      GeofenceEvent.dwell => 'DWELL',
    };

    StructuredLogger.log(
      LogTag.BG,
      '[Geofence] Reporting $eventType on "${trigger.geofenceName}" to backend',
    );

    _postGeofenceEvent(
      childId: childId,
      geofenceId: trigger.geofenceId,
      eventType: eventType,
      timestamp: trigger.timestamp.toUtc().toIso8601String(),
    );
  }

  Future<void> _postGeofenceEvent({
    required String childId,
    required String geofenceId,
    required String eventType,
    required String timestamp,
  }) async {
    try {
      final response = await _childRepo.postGeofenceEvent(
        childId: childId,
        geofenceId: geofenceId,
        eventType: eventType,
        timestamp: timestamp,
      );
      if (!response.isSuccess) {
        await _offlineQueue.enqueueGeofenceEvent(
          childId: childId,
          payload: {
            'geofenceId': geofenceId,
            'eventType': eventType,
            'timestamp': timestamp,
          },
        );
      }
    } catch (e) {
      StructuredLogger.log(LogTag.BG, '[Geofence] Failed to post event – queuing', error: e);
      await _offlineQueue.enqueueGeofenceEvent(
        childId: childId,
        payload: {
          'geofenceId': geofenceId,
          'eventType': eventType,
          'timestamp': timestamp,
        },
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OFFLINE QUEUE DRAIN
  // ══════════════════════════════════════════════════════════════════════════

  void _tryDrainOfflineQueue(String childId) {
    if (!_offlineQueue.hasPending) return;

    final now = DateTime.now();
    if (_lastDrainAttempt != null &&
        now.difference(_lastDrainAttempt!).inSeconds < 30) {
      return;
    }

    _lastDrainAttempt = now;

    _offlineQueue.drain((entry) async {
      try {
        switch (entry.type) {
          case OfflineEntryType.location:
            final response = await _childRepo.postChildLocation(entry.payload);
            return response.isSuccess;
          case OfflineEntryType.tripPoints:
            final response = await _childRepo.postTripLocation(
              childId: entry.childId,
              data: entry.payload,
            );
            return response.isSuccess;
          case OfflineEntryType.tripEnd:
            final response = await _childRepo.postTripEnd(
              childId: entry.childId,
              data: entry.payload,
            );
            return response.isSuccess;
          case OfflineEntryType.geofenceEvent:
            final response = await _childRepo.postGeofenceEvent(
              childId: entry.childId,
              geofenceId: entry.payload['geofenceId'] as String,
              eventType: entry.payload['eventType'] as String,
              timestamp: entry.payload['timestamp'] as String,
            );
            return response.isSuccess;
        }
      } catch (_) {
        return false;
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BACKEND STOP SIGNAL PARSER
  // ══════════════════════════════════════════════════════════════════════════

  bool _shouldStopTrip(dynamic responseData) {
    if (responseData == null) return false;
    try {
      final currentState = responseData['currentState'];
      if (currentState != 'IDLE') return false;
      final transitions = responseData['stateTransitions'];
      if (transitions is List && transitions.isNotEmpty) {
        for (final t in transitions) {
          if (t['to'] == 'ENDED' && t['reason'] == 'STATIONARY_CONFIRMED') {
            return true;
          }
        }
      }
    } catch (e) {
      StructuredLogger.log(LogTag.TRIP, 'Error parsing stop signal', error: e);
    }
    return false;
  }

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get isTripTracking => _isTripTracking;
  BgTripMode get tripMode => _tripMode;
  BgTripState get currentState => _state;
  LocalGeofenceEngine get geofenceEngine => _geoEngine;

  /// The last position that passed the 5m distance filter above — i.e. the
  /// last one actually accepted into processing/posting, not just the raw
  /// per-callback GPS reading. Use this (not a raw Position.speed) for
  /// anything user-visible, so a filtered/rejected reading can't show up
  /// in UI text that looks like it reflects real, accepted movement.
  Position? get lastAcceptedPosition => _lastPostedLocation;
}
