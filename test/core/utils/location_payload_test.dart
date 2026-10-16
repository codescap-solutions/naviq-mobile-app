import 'package:child_track/core/services/tracking/enhanced_trip_point.dart';
import 'package:child_track/core/utils/location_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position pos({double speed = 0, double speedAccuracy = 0}) => Position(
  latitude: 11.25,
  longitude: 75.78,
  timestamp: DateTime.utc(2026, 10, 10, 10),
  accuracy: 12,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: speedAccuracy,
);

void main() {
  group('knownSpeedMps', () {
    test('a positive speed is a measurement', () {
      expect(knownSpeedMps(pos(speed: 1.4)), 1.4);
    });
    test('bare 0 (what geolocator reports when the OS gave no speed) is UNKNOWN', () {
      expect(knownSpeedMps(pos()), isNull);
    });
    test('0 with a positive speedAccuracy is a genuine measured standstill', () {
      expect(knownSpeedMps(pos(speedAccuracy: 0.5)), 0.0);
    });
    test('negative / NaN / infinite are unknown', () {
      expect(knownSpeedMps(pos(speed: -1)), isNull);
      expect(knownSpeedMps(pos(speed: double.nan)), isNull);
      expect(knownSpeedMps(pos(speed: double.infinity)), isNull);
    });
  });

  group('speedFields', () {
    test('unknown speed is OMITTED and flagged — never 0', () {
      final f = speedFields(pos());
      expect(f, {'speed_known': false});
      expect(f.containsKey('speed_mps'), isFalse);
      expect(f.containsKey('speed'), isFalse);
    });
    test('known speed keeps the legacy alias unless disabled', () {
      expect(speedFields(pos(speed: 3)), {'speed_mps': 3.0, 'speed': 3.0, 'speed_known': true});
      expect(speedFields(pos(speed: 3), legacyAlias: false), {'speed_mps': 3.0, 'speed_known': true});
    });
    test('a measured standstill is sent as 0 with speed_known=true', () {
      expect(speedFields(pos(speedAccuracy: 0.4)), {'speed_mps': 0.0, 'speed': 0.0, 'speed_known': true});
    });
  });

  test('locationDiagnostics carries source, build and (optionally) profile', () {
    final d = locationDiagnostics(fixSource: 'stream', trackingProfile: 'walking');
    expect(d['fix_source'], 'stream');
    expect(d['tracking_profile'], 'walking');
    expect(d['platform'], anyOf('android', 'ios'));
    expect(d['app_version'], isNotEmpty);
    expect(locationDiagnostics(fixSource: 'x').containsKey('tracking_profile'), isFalse);
  });

  group('EnhancedTripPoint', () {
    test('unknown speed is left out of the trip payload', () {
      final json = EnhancedTripPoint.fromPosition(pos()).toJson();
      expect(json.containsKey('speed'), isFalse);
      expect(json['speed_known'], false);
    });
    test('known speed is sent', () {
      final json = EnhancedTripPoint.fromPosition(pos(speed: 5)).toJson();
      expect(json['speed'], 5.0);
      expect(json['speed_known'], true);
    });
  });

  group('forceRefreshLocationPayload (FCM refresh / probe answer)', () {
    test('probe: fix_source/profile, request id echo, measured speed', () {
      final m = forceRefreshLocationPayload(
        childId: 'c1',
        fix: pos(speed: 2.5),
        geofenceProbe: true,
        requestId: 'rr42',
      );
      expect(m['fix_source'], 'geofence_probe');
      expect(m['tracking_profile'], 'probe');
      expect(m['refresh_request_id'], 'rr42');
      expect(m['speed_mps'], 2.5);
      expect(m['speed_known'], true);
      expect(m['child_id'], 'c1');
      expect(m['timestamp'], '2026-10-10T10:00:00.000Z', reason: 'the fix capture time');
      expect(m['app_version'], isNotEmpty);
    });

    test('plain refresh: force_refresh source, no request id when the server sent none, unknown speed omitted', () {
      final m = forceRefreshLocationPayload(childId: 'c1', fix: pos(), geofenceProbe: false);
      expect(m['fix_source'], 'force_refresh');
      expect(m['tracking_profile'], 'force_refresh');
      expect(m.containsKey('refresh_request_id'), isFalse);
      expect(m.containsKey('speed_mps'), isFalse);
      expect(m['speed_known'], false);
      expect(forceRefreshLocationPayload(childId: 'c', fix: pos(), geofenceProbe: false, requestId: '').containsKey('refresh_request_id'), isFalse);
    });
  });
}
