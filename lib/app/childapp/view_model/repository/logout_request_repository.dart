import 'package:child_track/core/services/api_endpoints.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/utils/app_logger.dart';

/// Child-requests-logout flow — mirrors TimeLimitRepository's
/// ask-for-more-time methods exactly (same request/resolve shape), just
/// for "let me log out" instead of "give me more time".
class LogoutRequestRepository extends BaseService {
  LogoutRequestRepository({required DioClient dioClient}) : super(dioClient);

  /// POST /logout-requests — child asks their parent for permission to log
  /// out (always scoped to the calling child's own token server-side).
  Future<BaseResponse> requestLogout() async {
    final response = await post(ApiEndpoints.logoutRequests);
    AppLogger.info('requestLogout response: ${response.isSuccess}, ${response.message}');
    return response;
  }

  /// POST /logout-requests/:id/resolve — parent approves/denies.
  Future<BaseResponse> resolveLogoutRequest({
    required String requestId,
    required bool approve,
  }) async {
    final response = await post(
      ApiEndpoints.resolveLogoutRequest(requestId),
      data: {'approve': approve},
    );
    AppLogger.info('resolveLogoutRequest response: ${response.isSuccess}, ${response.message}');
    return response;
  }
}
