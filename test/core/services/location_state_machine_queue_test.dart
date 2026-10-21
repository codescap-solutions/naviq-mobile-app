import 'dart:convert';

import 'package:child_track/app/childapp/view_model/repository/child_location_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/location_state_machine.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/tracking/offline_trip_queue.dart';
import 'package:child_track/core/services/tracking/tracking_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockChildRepo extends Mock implements ChildRepo {}

class MockLocationRepo extends Mock implements ChildGoogleMapsRepo {}

class MockPrefs extends Mock implements SharedPrefsService {}

class MockConfig extends Mock implements TrackingConfigService {}

final captured = DateTime.utc(2026, 10, 10, 9, 30, 15);

Position fix() => Position(
  longitude: 20,
  latitude: 10,
  timestamp: captured,
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 3,
  speedAccuracy: 0.5,
);

BaseResponse<dynamic> ok() => BaseResponse.success(data: {});
BaseResponse<dynamic> offline() => BaseResponse.error(message: 'Internet not available.');
BaseResponse<dynamic> serverError() => BaseResponse.error(message: 'Internal server error', statusCode: 500);
BaseResponse<dynamic> refused(String code) => BaseResponse.error(message: 'refused', statusCode: 400, errorCode: code);

/// Drives the REAL LocationStateMachine upload + queue + drain with only the network faked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockChildRepo repo;
  late LocationStateMachine sm;
  late List<Map<String, dynamic>> posted;
  late List<BaseResponse<dynamic> Function()> script;

  Future<List<Map<String, dynamic>>> queuedPayloads() async {
    final raw = (await SharedPreferences.getInstance()).getString('naviq_offline_trip_queue');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from((e as Map)['payload'] as Map)).toList();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineTripQueue().clear();
    posted = [];
    script = [];
    repo = MockChildRepo();
    final prefs = MockPrefs();
    final cfg = MockConfig();
    when(() => prefs.getString('child_id')).thenReturn('c1');
    when(() => cfg.stopRadius).thenReturn(30.0);
    when(() => cfg.stopDuration).thenReturn(120);
    when(() => cfg.speedThreshold).thenReturn(0.28);
    when(() => cfg.geofenceRadius).thenReturn(150.0);
    when(() => cfg.fetchConfigFromServer()).thenAnswer((_) async {});
    when(() => repo.postChildLocation(any())).thenAnswer((i) async {
      posted.add(Map<String, dynamic>.from(i.positionalArguments.first as Map));
      return script.isEmpty ? ok() : script.removeAt(0)();
    });
    when(() => repo.postTripLocation(childId: any(named: 'childId'), data: any(named: 'data'))).thenAnswer((_) async => ok());
    sm = LocationStateMachine(childRepo: repo, locationRepo: MockLocationRepo(), prefs: prefs, configService: cfg);
  });
  tearDown(() => sm.dispose());

  Future<void> run() async {
    await sm.processLocation(fix());
    await pumpEventQueue(times: 40);
  }

  test('delivered: nothing is queued', () async {
    await run();
    expect(posted.length, 1);
    expect(await queuedPayloads(), isEmpty);
  });

  test('offline (BaseService returns an error response, it does NOT throw): the fix is queued with its ORIGINAL capture time', () async {
    script = [offline, offline];
    await run();
    final q = await queuedPayloads();
    expect(q.length, 1, reason: 'a failed upload used to be logged as "posted" and lost');
    expect(q.single['timestamp'], captured.toIso8601String());
    expect(q.single['child_id'], 'c1');
    expect(q.single['lat'], 10.0);
    expect(q.single.containsKey('device_time'), isFalse, reason: 'device_time is stamped at SEND time, never frozen into the queue');
  });

  test('a 5xx is retryable and queued', () async {
    script = [serverError, serverError];
    await run();
    expect((await queuedPayloads()).length, 1);
  });

  test('a permanent refusal (TOO_OLD / validation 400) is NOT queued and not retried', () async {
    script = [() => refused('TOO_OLD')];
    await run();
    expect(posted.length, 1, reason: 'no queue entry → nothing to replay');
    expect(await queuedPayloads(), isEmpty);
    expect(OfflineTripQueue().hasPending, isFalse);
  });

  test('CLOCK_SKEW is NOT queued (replaying a skewed capture can never succeed)', () async {
    script = [() => refused('CLOCK_SKEW')];
    await run();
    expect(await queuedPayloads(), isEmpty);
  });

  test('recovery: the queued fix is replayed once the network is back, with its original timestamp, and the queue empties', () async {
    script = [offline]; // first send fails; the drain's immediate retry (default ok()) succeeds
    await run();
    expect(posted.length, 2);
    expect(posted[1]['timestamp'], captured.toIso8601String());
    expect(posted[1]['child_id'], 'c1');
    expect(await queuedPayloads(), isEmpty);
    expect(OfflineTripQueue().hasPending, isFalse);
  });

  test('a replay that the server now refuses permanently is dropped immediately, not retried to the cap', () async {
    await OfflineTripQueue().enqueueLocation(
      childId: 'c1',
      payload: {'child_id': 'c1', 'lat': 1.0, 'lng': 2.0, 'timestamp': '2026-10-09T01:00:00.000Z'},
    );
    // 1st post (live fix) ok; drain replays the old entry → TOO_OLD
    script = [ok, () => refused('TOO_OLD')];
    await run();
    expect(OfflineTripQueue().hasPending, isFalse);
  });

  test('a replay failing for a retryable reason stays queued (and is not duplicated)', () async {
    await OfflineTripQueue().enqueueLocation(
      childId: 'c1',
      payload: {'child_id': 'c1', 'lat': 1.0, 'lng': 2.0, 'timestamp': '2026-10-10T09:00:00.000Z'},
    );
    script = [ok, serverError];
    await run();
    expect(OfflineTripQueue().pendingCount, 1);
  });

  test('the same capture can never be queued twice', () async {
    final payload = {'child_id': 'c1', 'timestamp': captured.toIso8601String(), 'lat': 10.0, 'lng': 20.0};
    await OfflineTripQueue().enqueueLocation(childId: 'c1', payload: payload);
    await OfflineTripQueue().enqueueLocation(childId: 'c1', payload: Map.of(payload));
    expect(OfflineTripQueue().pendingCount, 1);
  });

  test('a long outage cannot grow the queue without bound: the newest fixes are kept', () async {
    final q = OfflineTripQueue();
    for (var i = 0; i < OfflineTripQueue.maxLocationEntries + 5; i++) {
      await q.enqueueLocation(
        childId: 'c1',
        payload: {'child_id': 'c1', 'timestamp': '2026-10-10T09:00:${i.toString().padLeft(2, '0')}.$i', 'lat': 1.0, 'lng': 2.0},
      );
    }
    expect(q.pendingCount, OfflineTripQueue.maxLocationEntries);
    final payloads = await queuedPayloads();
    expect(payloads.last['timestamp'], endsWith('.${OfflineTripQueue.maxLocationEntries + 4}'), reason: 'newest kept');
    expect(payloads.any((p) => (p['timestamp'] as String).endsWith('.0')), isFalse, reason: 'oldest dropped');
  });
}
