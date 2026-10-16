import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/tracking/post_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

BaseResponse err({int? status, String? code, String message = 'x'}) =>
    BaseResponse.error(message: message, statusCode: status, errorCode: code);

void main() {
  group('classifyPostResponse', () {
    test('a 2xx with is_success is delivered', () {
      expect(classifyPostResponse(BaseResponse.success(data: {})), PostOutcome.delivered);
    });

    test('no HTTP status (offline, timeout, DNS, TLS) is retryable — the point must not be lost', () {
      expect(classifyPostResponse(err(message: 'Internet not available.')), PostOutcome.retryable);
    });

    test('5xx, 408 and 429 are retryable', () {
      for (final s in [500, 502, 503, 504, 408, 429]) {
        expect(classifyPostResponse(err(status: s)), PostOutcome.retryable, reason: '$s');
      }
    });

    test('401 is retryable (token refresh / re-login), bounded by the queue retry cap', () {
      expect(classifyPostResponse(err(status: 401)), PostOutcome.retryable);
    });

    test('other 4xx are permanent: the same payload would be refused again', () {
      for (final s in [400, 403, 404, 422]) {
        expect(classifyPostResponse(err(status: s)), PostOutcome.permanent, reason: '$s');
      }
    });

    test('CLOCK_SKEW is its own outcome (never retried, raises the child prompt)', () {
      expect(classifyPostResponse(err(status: 400, code: 'CLOCK_SKEW')), PostOutcome.clockSkew);
    });

    test('FUTURE_TIMESTAMP / TOO_OLD / INVALID_TIMESTAMP are permanent even if the status were missing', () {
      for (final c in ['FUTURE_TIMESTAMP', 'TOO_OLD', 'INVALID_TIMESTAMP']) {
        expect(classifyPostResponse(err(code: c)), PostOutcome.permanent, reason: c);
        expect(classifyPostResponse(err(status: 400, code: c)), PostOutcome.permanent, reason: c);
      }
    });
  });

  group('acceptedAsLive', () {
    test('a normal accepted point is live', () {
      expect(acceptedAsLive(BaseResponse.success(data: {})), isTrue);
      expect(acceptedAsLive(BaseResponse.success(data: null as dynamic)), isTrue);
    });

    test('a delayed upload kept as history is NOT live evidence', () {
      expect(acceptedAsLive(BaseResponse.success(data: {'history_only': true, 'reason': 'DELAYED'})), isFalse);
    });

    test('a duplicate retry is NOT live evidence', () {
      expect(acceptedAsLive(BaseResponse.success(data: {'duplicate': true})), isFalse);
    });

    test('a failure is never live', () {
      expect(acceptedAsLive(err(status: 500)), isFalse);
    });
  });
}
