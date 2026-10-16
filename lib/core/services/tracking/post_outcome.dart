import 'package:child_track/core/services/base_service.dart';

/// What a location/trip upload's answer means for the sender.
enum PostOutcome {
  /// The server stored it (live or as history).
  delivered,

  /// Nothing was decided about the data — offline, timeout, 5xx, 408/429, an
  /// expired token. The same payload may succeed later: keep it queued.
  retryable,

  /// The server refused this payload for a reason that will not change on a
  /// replay (400-class validation, too old, future-dated). Drop it — queueing
  /// it would only fail again until the retry cap.
  permanent,

  /// The phone's own clock is wrong (`error_code: CLOCK_SKEW`). The point is
  /// refused and not worth replaying; the child must fix the date & time.
  clockSkew,
}

/// Server `error_code`s whose refusal can never be cured by re-sending the same point.
const _permanentErrorCodes = {'FUTURE_TIMESTAMP', 'TOO_OLD', 'INVALID_TIMESTAMP'};

PostOutcome classifyPostResponse(BaseResponse response) {
  if (response.isSuccess) return PostOutcome.delivered;
  final code = response.errorCode;
  if (code == 'CLOCK_SKEW') return PostOutcome.clockSkew;
  if (_permanentErrorCodes.contains(code)) return PostOutcome.permanent;

  final status = response.statusCode;
  // No HTTP status: the request never got an answer (offline, timeout, DNS, TLS)
  // or a 2xx body said is_success=false. Never lose the point over that.
  if (status == null) return PostOutcome.retryable;
  if (status == 408 || status == 429 || status >= 500) return PostOutcome.retryable;
  // 401: the token is being refreshed / the child must log in again. The queue's
  // own retry cap bounds how long such an entry survives.
  if (status == 401) return PostOutcome.retryable;
  return PostOutcome.permanent;
}

/// True when a successful answer means "accepted as the child's current, live
/// position": not a delayed upload kept only as history and not a duplicate
/// retry. Only that proves the clock problem (if any) is over.
bool acceptedAsLive(BaseResponse response) {
  if (!response.isSuccess) return false;
  final data = response.data;
  if (data is Map) {
    if (data['history_only'] == true) return false;
    if (data['duplicate'] == true) return false;
  }
  return true;
}
