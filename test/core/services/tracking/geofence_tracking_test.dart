import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:child_track/core/services/tracking/geofence_tracking_config.dart';
import 'package:child_track/core/services/tracking/local_geofence_engine.dart';
import 'package:child_track/core/services/tracking/tracking_profile_manager.dart';

/// ~metres → degrees latitude.
double _m(double metres) => metres / 111320.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reliable accuracy limit (mirror of the server rule)', () {
    test('scales with radius but is bounded', () {
      expect(GeofenceTrackingConfig.reliableAccuracyLimitMeters(50), 40);
      expect(GeofenceTrackingConfig.reliableAccuracyLimitMeters(100), 50);
      expect(GeofenceTrackingConfig.reliableAccuracyLimitMeters(150), 75);
      expect(GeofenceTrackingConfig.reliableAccuracyLimitMeters(2000), 75);
    });
  });

  group('TrackingProfileManager — adaptive near-fence tracking', () {
    test('default still profile stays low-power on iOS (medium, 75m, auto-pause)', () {
      final m = TrackingProfileManager();
      final s = m.buildAppleSettings();
      expect(s.accuracy, LocationAccuracy.medium);
      expect(s.distanceFilter, 75);
      expect(s.pauseLocationUpdatesAutomatically, isTrue);
    });

    test('near-fence still profile uses HIGH accuracy + small filter, auto-pause stays ON', () {
      final m = TrackingProfileManager();
      expect(m.setNearFence(true), isTrue, reason: 'stream must be restarted');
      final s = m.buildAppleSettings();
      expect(s.accuracy, LocationAccuracy.high);
      expect(s.distanceFilter, GeofenceTrackingConfig.nearFenceDistanceFilterMeters);
      expect(s.pauseLocationUpdatesAutomatically, isTrue, reason: 'battery: OS can still pause when stationary');
      expect(m.effectiveProfileLabel, 'still_near_fence');
    });

    test('leaving the zone returns to the low-power settings', () {
      final m = TrackingProfileManager()..setNearFence(true);
      expect(m.setNearFence(false), isTrue);
      final s = m.buildAppleSettings();
      expect(s.accuracy, LocationAccuracy.medium);
      expect(s.distanceFilter, 75);
    });

    test('setNearFence with no change does not restart the stream', () {
      final m = TrackingProfileManager();
      expect(m.setNearFence(false), isFalse);
    });

    test('walking/vehicle profiles are unaffected by near-fence (already precise)', () {
      final m = TrackingProfileManager()..setProfile(TrackingProfile.walking);
      expect(m.setNearFence(true), isFalse);
      expect(m.buildAppleSettings().distanceFilter, 5);
    });

    test('boost: high accuracy, tiny filter, auto-pause OFF, then expires by itself', () {
      final m = TrackingProfileManager();
      expect(m.startBoost(const Duration(milliseconds: 80)), isTrue);
      final s = m.buildAppleSettings();
      expect(s.accuracy, LocationAccuracy.high);
      expect(s.distanceFilter, GeofenceTrackingConfig.boostDistanceFilterMeters);
      expect(s.pauseLocationUpdatesAutomatically, isFalse);
      expect(m.effectiveProfileLabel, 'boost');
      expect(m.startBoost(const Duration(milliseconds: 80)), isFalse, reason: 'already active → just extended');
    });

    test('boost ends and settings return to normal (no permanent high-frequency GPS)', () async {
      final m = TrackingProfileManager()..startBoost(const Duration(milliseconds: 40));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(m.boostActive, isFalse);
      expect(m.expireBoostIfDue(), isTrue);
      expect(m.expireBoostIfDue(), isFalse);
      expect(m.buildAppleSettings().pauseLocationUpdatesAutomatically, isTrue);
    });

    test('Android near-fence/boost settings are more frequent only while active', () {
      final m = TrackingProfileManager();
      final base = m.buildAndroidSettings();
      m.setNearFence(true);
      final near = m.buildAndroidSettings();
      expect(near.distanceFilter, GeofenceTrackingConfig.nearFenceDistanceFilterMeters);
      m.setNearFence(false);
      expect(m.buildAndroidSettings().distanceFilter, base.distanceFilter);
    });
  });

  group('LocalGeofenceEngine — accuracy/timestamp aware', () {
    late LocalGeofenceEngine engine;
    late List<GeofenceTrigger> triggers;
    late StreamSubscription<GeofenceTrigger> sub;

    setUp(() {
      engine = LocalGeofenceEngine();
      engine.clearAll();
      engine.register(id: 'home', name: 'Home', lat: 11.25, lng: 75.78, radiusMeters: 100);
      triggers = [];
      sub = engine.triggers.listen(triggers.add);
    });
    tearDown(() async {
      await sub.cancel();
      engine.clearAll();
    });

    test('nearestEdgeDistanceMeters: negative inside, positive outside, null with no fences', () {
      expect(engine.nearestEdgeDistanceMeters(11.25, 75.78)!, closeTo(-100, 1));
      expect(engine.nearestEdgeDistanceMeters(11.25 + _m(400), 75.78)!, closeTo(300, 2));
      engine.clearAll();
      expect(engine.nearestEdgeDistanceMeters(11.25, 75.78), isNull);
    });

    test('a coarse (200m) fix inside the fence does NOT emit ENTER', () async {
      engine.processPosition(11.25, 75.78, accuracyMeters: 200);
      await Future<void>.delayed(Duration.zero);
      expect(triggers, isEmpty);
    });

    test('a precise fix emits ENTER stamped with the fix time, not "now"', () async {
      final captured = DateTime.now().subtract(const Duration(minutes: 5));
      engine.processPosition(11.25, 75.78, accuracyMeters: 10, capturedAt: captured);
      await Future<void>.delayed(Duration.zero);
      expect(triggers.length, 1);
      expect(triggers.single.event, GeofenceEvent.enter);
      expect(triggers.single.timestamp, captured);
    });

    test('a coarse fix far outside does NOT emit EXIT for a child recorded inside', () async {
      engine.register(id: 'home', name: 'Home', lat: 11.25, lng: 75.78, radiusMeters: 100, currentlyInside: true);
      engine.processPosition(11.25 + _m(500), 75.78, accuracyMeters: 400);
      await Future<void>.delayed(Duration.zero);
      expect(triggers, isEmpty);
      engine.processPosition(11.25 + _m(500), 75.78, accuracyMeters: 10);
      await Future<void>.delayed(Duration.zero);
      expect(triggers.single.event, GeofenceEvent.exit);
    });
  });
}
