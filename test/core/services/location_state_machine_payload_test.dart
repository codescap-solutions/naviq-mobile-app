import 'package:child_track/app/childapp/view_model/repository/child_location_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/location_state_machine.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/tracking/tracking_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockChildRepo extends Mock implements ChildRepo {}

class MockLocationRepo extends Mock implements ChildGoogleMapsRepo {}

class MockPrefs extends Mock implements SharedPrefsService {}

class MockConfig extends Mock implements TrackingConfigService {}

Position pos(double speed, double speedAccuracy, {double lat = 10.0}) => Position(
  longitude: 20,
  latitude: lat,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: speedAccuracy,
);

/// Exercises the REAL LocationStateMachine._postChildLocation (only the network
/// layer is mocked) and inspects the exact body it hands to ChildRepo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockChildRepo repo;
  late LocationStateMachine sm;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = MockChildRepo();
    final prefs = MockPrefs();
    final cfg = MockConfig();
    when(() => prefs.getString('child_id')).thenReturn('c1');
    when(() => cfg.stopRadius).thenReturn(30.0);
    when(() => cfg.stopDuration).thenReturn(120);
    when(() => cfg.speedThreshold).thenReturn(0.28);
    when(() => cfg.geofenceRadius).thenReturn(150.0);
    when(() => cfg.fetchConfigFromServer()).thenAnswer((_) async {});
    when(() => repo.postChildLocation(any())).thenAnswer((_) async => BaseResponse.success(data: {}) as BaseResponse<dynamic>);
    when(() => repo.postTripLocation(childId: any(named: 'childId'), data: any(named: 'data')))
        .thenAnswer((_) async => BaseResponse.success(data: {}) as BaseResponse<dynamic>);
    sm = LocationStateMachine(childRepo: repo, locationRepo: MockLocationRepo(), prefs: prefs, configService: cfg);
  });
  tearDown(() => sm.dispose());

  test('unknown speed is omitted, a measured speed and a measured 0 are kept, diagnostics are attached', () async {
    await sm.processLocation(pos(0, 0)); // platform gave no speed → unknown
    await sm.processLocation(pos(4.2, 0.5, lat: 10.01)); // measured
    await sm.processLocation(pos(0, 0.4, lat: 10.02)); // measured standstill

    final calls = verify(() => repo.postChildLocation(captureAny())).captured.cast<Map<String, dynamic>>();
    expect(calls.length, 3);

    expect(calls[0].containsKey('speed_mps'), isFalse, reason: 'unknown speed is never sent as 0 m/s');
    expect(calls[0].containsKey('speed'), isFalse);
    expect(calls[0]['speed_known'], isFalse);

    expect(calls[1]['speed_mps'], 4.2);
    expect(calls[1]['speed_known'], isTrue);

    expect(calls[2]['speed_mps'], 0.0, reason: 'a genuinely measured standstill stays zero');
    expect(calls[2]['speed_known'], isTrue);

    for (final c in calls) {
      expect(c['fix_source'], 'stream');
      expect(c['platform'], anyOf('android', 'ios'));
      expect(c['app_version'], isNotEmpty);
      expect(c['timestamp'], isA<String>(), reason: "the fix's own capture time, never 'now'");
    }
  });
}
