import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/services/api_exception.dart';
import 'package:child_track/core/services/tracking/clock_skew_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

class MockPrefs extends Mock implements SharedPrefsService {}

void main() {
  late MockDioClient dio;
  late ChildRepo repo;

  setUp(() {
    dio = MockDioClient();
    repo = ChildRepo(dioClient: dio, sharedPrefsService: MockPrefs());
    when(() => dio.post(any(), data: any(named: 'data'), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((i) async => Response(
              requestOptions: RequestOptions(path: i.positionalArguments.first as String),
              data: {'is_success': true, 'message': 'ok', 'data': {}},
            ));
  });

  Map<String, dynamic> sentBody() => (verify(() => dio.post(any(), data: captureAny(named: 'data'), queryParameters: any(named: 'queryParameters')))
          .captured
          .last as Map)
      .cast<String, dynamic>();

  test('every location post is stamped with the device wall clock at SEND time (UTC ISO-8601)', () async {
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
    await repo.postChildLocation({'child_id': 'c1', 'lat': 1.0, 'lng': 2.0, 'timestamp': '2026-10-10T09:00:00.000Z'});
    final body = sentBody();
    final sent = DateTime.parse(body['device_time'] as String);
    expect(sent.isUtc, isTrue);
    expect(sent.isAfter(before), isTrue);
    expect(sent.isBefore(DateTime.now().toUtc().add(const Duration(seconds: 2))), isTrue);
    // the CAPTURE time is untouched — device_time is a separate field
    expect(body['timestamp'], '2026-10-10T09:00:00.000Z');
    expect(body['child_id'], 'c1');
  });

  test('a replayed (queued) payload is re-stamped at replay time, not frozen at queue time', () async {
    final queued = {'child_id': 'c1', 'lat': 1.0, 'lng': 2.0, 'device_time': '2020-01-01T00:00:00.000Z'};
    await repo.postChildLocation(queued);
    final sent = DateTime.parse(sentBody()['device_time'] as String);
    expect(sent.year, greaterThan(2020));
    expect(queued['device_time'], '2020-01-01T00:00:00.000Z', reason: "caller's map is not mutated");
  });

  group('clock-skew bookkeeping (what the child prompt is driven by)', () {
    late ClockSkewMonitor monitor;
    late ChildRepo skewRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      monitor = ClockSkewMonitor();
      skewRepo = ChildRepo(dioClient: dio, sharedPrefsService: MockPrefs(), clockSkewMonitor: monitor);
    });

    void answerWith(Object Function() answer) {
      when(() => dio.post(any(), data: any(named: 'data'), queryParameters: any(named: 'queryParameters')))
          .thenAnswer((i) async {
        final a = answer();
        if (a is Exception) throw a;
        return Response(requestOptions: RequestOptions(path: i.positionalArguments.first as String), data: a);
      });
    }

    test('a CLOCK_SKEW refusal raises the warning and still returns the failed response', () async {
      answerWith(() => const ApiException('too far', statusCode: 400, errorCode: 'CLOCK_SKEW', data: {'clock_offset_seconds': 900}));
      final r = await skewRepo.postChildLocation({'child_id': 'c1', 'lat': 1.0, 'lng': 2.0});
      expect(r.isSuccess, isFalse);
      expect(r.errorCode, 'CLOCK_SKEW');
      expect((await monitor.read())!.offsetSeconds, 900);
    });

    test('a delayed offline-queue replay (200 history_only) does not raise it', () async {
      answerWith(() => {'is_success': true, 'message': 'Location saved', 'data': {'history_only': true, 'reason': 'DELAYED'}});
      await skewRepo.postChildLocation({'child_id': 'c1', 'lat': 1.0, 'lng': 2.0, 'timestamp': '2026-10-10T08:00:00.000Z'});
      expect(await monitor.read(), isNull);
    });

    test('an accepted live point clears an active warning', () async {
      answerWith(() => const ApiException('too far', statusCode: 400, errorCode: 'CLOCK_SKEW'));
      await skewRepo.postChildLocation({'child_id': 'c1'});
      expect(await monitor.read(), isNotNull);
      answerWith(() => {'is_success': true, 'message': 'Location saved', 'data': {}});
      await skewRepo.postChildLocation({'child_id': 'c1'});
      expect(await monitor.read(), isNull);
    });

    test('trip batches are stamped with a batch-level device_time and feed the same warning', () async {
      answerWith(() => const ApiException('too far', statusCode: 400, errorCode: 'CLOCK_SKEW'));
      await skewRepo.postTripLocation(childId: 'c1', data: {'points': [{'ts': '2026-10-10T09:00:00.000Z'}]});
      final body = (verify(() => dio.post(any(), data: captureAny(named: 'data'), queryParameters: any(named: 'queryParameters')))
              .captured
              .last as Map)
          .cast<String, dynamic>();
      expect(DateTime.parse(body['device_time'] as String).isUtc, isTrue);
      expect((body['points'] as List).single['ts'], '2026-10-10T09:00:00.000Z', reason: 'point capture times untouched');
      expect(await monitor.read(), isNotNull);
    });
  });

  group('postGeofenceEvent', () {
    Map<String, dynamic> sent() => (verify(() => dio.post(any(), data: captureAny(named: 'data'), queryParameters: any(named: 'queryParameters')))
            .captured
            .last as Map)
        .cast<String, dynamic>();

    test('keeps the existing contract and adds a send-time device_time without touching the event time', () async {
      await repo.postGeofenceEvent(
        childId: 'c1',
        geofenceId: 'g1',
        eventType: 'ENTER',
        timestamp: '2026-10-10T08:00:00.000Z',
        source: 'local_engine',
      );
      final body = sent();
      expect(body['childId'], 'c1');
      expect(body['geofenceId'], 'g1');
      expect(body['eventType'], 'ENTER');
      expect(body['timestamp'], '2026-10-10T08:00:00.000Z', reason: 'event time is the capture time, never replaced');
      expect(body['source'], 'local_engine');
      final deviceTime = DateTime.parse(body['device_time'] as String);
      expect(deviceTime.isUtc, isTrue);
      expect(DateTime.now().toUtc().difference(deviceTime).inSeconds.abs(), lessThan(5));
      expect(body.keys.toSet(), {'childId', 'geofenceId', 'eventType', 'timestamp', 'device_time', 'source'});
    });

    test('a queued replay is stamped at replay time, the old event time is preserved', () async {
      await repo.postGeofenceEvent(
        childId: 'c1',
        geofenceId: 'g1',
        eventType: 'EXIT',
        timestamp: '2020-01-01T00:00:00.000Z',
      );
      final body = sent();
      expect(body['timestamp'], '2020-01-01T00:00:00.000Z');
      expect(DateTime.parse(body['device_time'] as String).year, greaterThan(2020));
    });
  });
}
