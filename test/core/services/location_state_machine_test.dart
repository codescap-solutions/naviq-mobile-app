import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:child_track/core/services/location_state_machine.dart';
import 'package:mocktail/mocktail.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/child_location_repo.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:child_track/core/services/tracking/tracking_config_service.dart';

class MockChildRepo extends Mock implements ChildRepo {}

class MockChildGoogleMapsRepo extends Mock implements ChildGoogleMapsRepo {}

class MockSharedPrefsService extends Mock implements SharedPrefsService {}

class MockTrackingConfigService extends Mock implements TrackingConfigService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocationStateMachine stateMachine;
  late MockChildRepo mockChildRepo;
  late MockChildGoogleMapsRepo mockLocationRepo;
  late MockSharedPrefsService mockPrefs;
  late MockTrackingConfigService mockConfigService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockChildRepo = MockChildRepo();
    mockLocationRepo = MockChildGoogleMapsRepo();
    mockPrefs = MockSharedPrefsService();
    mockConfigService = MockTrackingConfigService();

    when(() => mockPrefs.getString('child_id')).thenReturn('test_child_123');
    when(() => mockConfigService.stopRadius).thenReturn(30.0);
    when(() => mockConfigService.stopDuration).thenReturn(120);
    when(() => mockConfigService.speedThreshold).thenReturn(0.28);
    when(() => mockConfigService.geofenceRadius).thenReturn(150.0);
    when(() => mockConfigService.fetchConfigFromServer()).thenAnswer((_) async {});

    // Mock Location Repo answers
    when(
      () => mockLocationRepo.getAddressAndPlaceName(any(), any()),
    ).thenAnswer(
      (_) async => {'address': '123 Test St', 'place_name': 'Test Place'},
    );

    // Mock API answers
    when(() => mockChildRepo.postChildLocation(any())).thenAnswer(
      (_) async => BaseResponse.success(data: {}) as BaseResponse<dynamic>,
    );

    // Default mock for postTripLocation
    when(
      () => mockChildRepo.postTripLocation(
        childId: any(named: 'childId'),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => BaseResponse.success(data: {}) as BaseResponse<dynamic>,
    );

    stateMachine = LocationStateMachine(
      childRepo: mockChildRepo,
      locationRepo: mockLocationRepo,
      prefs: mockPrefs,
      configService: mockConfigService,
    );
  });

  Position createPosition(
    double lat,
    double lng,
    DateTime time,
    double speed,
    double accuracy,
  ) {
    return Position(
      longitude: lng,
      latitude: lat,
      timestamp: time,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
      isMocked: false,
    );
  }

  test('Scenario 1: Stationary - ignores locations under 10m', () async {
    final t1 = DateTime.now();

    // First location (Should post API) - using real coordinates near equator (1 degree ~ 111km)
    final p1 = createPosition(10.0000000, 20.0000000, t1, 0, 5);
    await stateMachine.processLocation(p1);

    // Second location 2m away (Should ignore) - ~0.000018 degrees
    final p2 = createPosition(
      10.0000001,
      20.0000001,
      t1.add(const Duration(seconds: 30)),
      0,
      5,
    );
    await stateMachine.processLocation(p2);

    verify(() => mockChildRepo.postChildLocation(any())).called(1);
    expect(stateMachine.currentState, BgTripState.candidate);
  });

  test(
    'Scenario 2: Walking Trip Detection (Speed ~1.0 m/s for >30s and >30m)',
    () async {
      final baseTime = DateTime.parse('2026-03-01T10:00:00Z');

      // Point 1 - Origin
      await stateMachine.processLocation(
        createPosition(10.0, 20.0, baseTime, 1.2, 5),
      );

      // Point 2 - 15m away, 15s later
      await stateMachine.processLocation(
        createPosition(
          10.000135,
          20.0,
          baseTime.add(const Duration(seconds: 15)),
          1.2,
          5,
        ),
      );
      expect(stateMachine.currentState, BgTripState.candidate);

      // Point 3 - 35m total distance, 35s total elapsed
      await stateMachine.processLocation(
        createPosition(
          10.000315,
          20.0,
          baseTime.add(const Duration(seconds: 35)),
          1.2,
          5,
        ),
      );

      // Should now be a confirmed walking trip
      expect(stateMachine.currentState, BgTripState.tracking);
      expect(stateMachine.tripMode, BgTripMode.walking);
    },
  );

  test(
    'Scenario 3: Vehicle Trip Detection (Speed 15 m/s for >20s and >100m)',
    () async {
      final baseTime = DateTime.parse('2026-03-01T10:00:00Z');

      await stateMachine.processLocation(
        createPosition(10.0, 20.0, baseTime, 15.0, 5),
      );

      // 15 seconds later, 225m away -> Candidate
      await stateMachine.processLocation(
        createPosition(
          10.00202,
          20.0,
          baseTime.add(const Duration(seconds: 15)),
          15.0,
          5,
        ),
      );
      expect(stateMachine.currentState, BgTripState.candidate);

      // 25 seconds later, 375m total away -> Confirmed Vehicle Trip
      await stateMachine.processLocation(
        createPosition(
          10.00337,
          20.0,
          baseTime.add(const Duration(seconds: 25)),
          15.0,
          5,
        ),
      );

      expect(stateMachine.currentState, BgTripState.tracking);
      expect(stateMachine.tripMode, BgTripMode.vehicle);
    },
  );

  test('Scenario 4: Poor Accuracy Filter', () async {
    final baseTime = DateTime.now();
    await stateMachine.processLocation(
      createPosition(10.0, 20.0, baseTime, 5.0, 50.0),
    ); // 50m accuracy is bad

    // Shouldn't even become a candidate
    expect(stateMachine.currentState, BgTripState.idle);
  });

  test('Scenario 5: Backend Stops Trip (STATIONARY_CONFIRMED)', () async {
    final baseTime = DateTime.parse('2026-03-01T10:00:00Z');

    // Fast-track a vehicle trip
    await stateMachine.processLocation(
      createPosition(10.0, 20.0, baseTime, 15.0, 5),
    );
    await stateMachine.processLocation(
      createPosition(
        10.00202,
        20.0,
        baseTime.add(const Duration(seconds: 15)),
        15.0,
        5,
      ),
    );
    await stateMachine.processLocation(
      createPosition(
        10.00337,
        20.0,
        baseTime.add(const Duration(seconds: 25)),
        15.0,
        5,
      ),
    );

    expect(stateMachine.isTripTracking, true);

    // Now mock the backend telling us to STOP the trip on the next post
    when(
      () => mockChildRepo.postTripLocation(
        childId: any(named: 'childId'),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async =>
          BaseResponse.success(
                data: {
                  'currentState': 'IDLE',
                  'stateTransitions': [
                    {'to': 'ENDED', 'reason': 'STATIONARY_CONFIRMED'},
                  ],
                },
              )
              as BaseResponse<dynamic>,
    );

    // Send one more point (which will trigger the stop logic after it posts)
    await stateMachine.processLocation(
      createPosition(
        10.00400,
        20.0,
        baseTime.add(const Duration(seconds: 40)),
        0.0,
        5,
      ),
    );

    // The state machine should parse the response and stop the trip
    expect(stateMachine.isTripTracking, false);
    expect(stateMachine.currentState, BgTripState.idle);
  });

  test(
    'Scenario 6: Posted body uses the fix\'s own timestamp, not DateTime.now()',
    () async {
      // Deliberately a stale timestamp far from "now" — mirrors the real
      // Kusuma/585LQP case (2026-09-29): iOS handed back the same cached
      // fix across several consecutive requests. If _postChildLocation ever
      // regresses to DateTime.now(), this old fixTime would get silently
      // relabeled as "just captured", which is exactly the bug that made 4
      // identical stale coordinates look like 4 separate fresh pings to the
      // backend's trip detection (see location_state_machine.dart's
      // _postChildLocation comment).
      final fixTime = DateTime.utc(2020, 1, 1, 0, 0, 0);
      final p1 = createPosition(10.0, 20.0, fixTime, 0, 5);

      await stateMachine.processLocation(p1);

      final captured = verify(
        () => mockChildRepo.postChildLocation(captureAny()),
      ).captured;
      expect(captured, isNotEmpty);
      final body = captured.first as Map<String, dynamic>;

      expect(body['timestamp'], fixTime.toIso8601String());
      // Regression guard: a wall-clock timestamp would be within seconds of
      // "now" (2026+), not this fixed 2020 date.
      expect(
        DateTime.parse(
          body['timestamp'] as String,
        ).isBefore(DateTime.now().subtract(const Duration(days: 365))),
        isTrue,
        reason:
            'timestamp should be the stale fix time, not DateTime.now() — '
            'regression to DateTime.now() would make this assertion fail',
      );
    },
  );
}
