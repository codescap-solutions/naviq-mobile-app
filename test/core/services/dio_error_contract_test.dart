import 'dart:convert';
import 'dart:typed_data';

import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/tracking/post_outcome.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Svc extends BaseService {
  _Svc(super.client);
  Future<BaseResponse> send() => post('child/location', data: {'a': 1});
}

/// Answers every request with a canned status/body, or fails like a dead network.
class _Adapter implements HttpClientAdapter {
  int? status;
  Object? body;
  DioExceptionType? failWith;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (failWith != null) {
      throw DioException(requestOptions: options, type: failWith!, message: 'net');
    }
    return ResponseBody.fromString(jsonEncode(body), status!, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late _Svc svc;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.init();
    final client = DioClient(sharedPrefsService: SharedPrefsService());
    adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    svc = _Svc(client);
  });

  test('a CLOCK_SKEW 400 keeps its status, error_code and data (the old contract dropped all three)', () async {
    adapter
      ..status = 400
      ..body = {
        'is_success': false,
        'message': 'Location timestamp is too far from server time',
        'error_code': 'CLOCK_SKEW',
        'data': {'server_time': '2026-10-10T10:00:00.000Z', 'clock_offset_seconds': 1200},
      };
    final r = await svc.send();
    expect(r.isSuccess, isFalse);
    expect(r.statusCode, 400);
    expect(r.errorCode, 'CLOCK_SKEW');
    expect(r.errorData!['clock_offset_seconds'], 1200);
    expect(classifyPostResponse(r), PostOutcome.clockSkew);
  });

  test('the user-visible message text is unchanged by the richer exception', () async {
    adapter
      ..status = 400
      ..body = {'is_success': false, 'message': 'Bad thing'};
    expect((await svc.send()).message, 'Bad thing');
    adapter
      ..status = 500
      ..body = {'message': 'x'};
    expect((await svc.send()).message, 'Internal server error: Please try again later');
  });

  test('a 500 is retryable', () async {
    adapter
      ..status = 500
      ..body = {'message': 'x'};
    final r = await svc.send();
    expect(r.statusCode, 500);
    expect(classifyPostResponse(r), PostOutcome.retryable);
  });

  test('a validation 400 without a retry-fixable cause is permanent', () async {
    adapter
      ..status = 400
      ..body = {'is_success': false, 'message': 'child_id required'};
    final r = await svc.send();
    expect(r.errorCode, isNull);
    expect(classifyPostResponse(r), PostOutcome.permanent);
  });

  test('a dead network has no status and is retryable', () async {
    adapter.failWith = DioExceptionType.connectionError;
    final r = await svc.send();
    expect(r.statusCode, isNull);
    expect(classifyPostResponse(r), PostOutcome.retryable);
  });

  test('a timeout has no status and is retryable', () async {
    adapter.failWith = DioExceptionType.receiveTimeout;
    expect(classifyPostResponse(await svc.send()), PostOutcome.retryable);
  });
}
