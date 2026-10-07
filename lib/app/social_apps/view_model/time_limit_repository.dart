import 'package:child_track/app/social_apps/model/time_limit_model.dart';
import 'package:child_track/core/services/api_endpoints.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/utils/app_logger.dart';

class TimeLimitRepository extends BaseService {
  TimeLimitRepository({required DioClient dioClient}) : super(dioClient);

  // ─── Daily limit CRUD (parent sets; child can read its own) ───

  /// GET /app-time-limits?childId=X
  Future<BaseResponse<List<AppTimeLimitItem>>> getTimeLimits({
    String? childId,
  }) async {
    final response = await get<Map<String, dynamic>>(
      ApiEndpoints.appTimeLimits,
      queryParameters: childId != null ? {'childId': childId} : null,
    );

    if (response.isSuccess) {
      try {
        final list = (response.data?['data'] as List? ?? [])
            .map((e) => AppTimeLimitItem.fromJson(e as Map<String, dynamic>))
            .toList();
        return BaseResponse.success(data: list, message: response.message);
      } catch (e) {
        AppLogger.error('Failed to parse time limits: $e');
        return BaseResponse.error(message: 'Failed to parse time limits: $e');
      }
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  /// POST /app-time-limits — parent sets/updates a daily limit for one app.
  /// Pass dailyLimitMinutes: null to mean "no limit" (caller should use
  /// [removeTimeLimit] instead — kept here only for symmetry).
  Future<BaseResponse> setTimeLimit({
    required String childId,
    required String packageName,
    required String appName,
    required int dailyLimitMinutes,
  }) async {
    final response = await post(
      ApiEndpoints.appTimeLimits,
      data: {
        'childId': childId,
        'package_name': packageName,
        'app_name': appName,
        'daily_limit_minutes': dailyLimitMinutes,
      },
    );
    AppLogger.info(
      'setTimeLimit response: ${response.isSuccess}, ${response.message}',
    );
    return response;
  }

  /// DELETE /app-time-limits — parent removes a daily limit for one app.
  Future<BaseResponse> removeTimeLimit({
    required String childId,
    required String packageName,
  }) async {
    final response = await delete(
      ApiEndpoints.appTimeLimits,
      data: {'childId': childId, 'package_name': packageName},
    );
    AppLogger.info(
      'removeTimeLimit response: ${response.isSuccess}, ${response.message}',
    );
    return response;
  }

  // ─── Ask-for-more-time flow ───

  /// POST /time-extension-requests — child asks for more time (always scoped
  /// to the calling child's own token server-side).
  Future<BaseResponse> requestExtension({
    required String packageName,
    int requestedMinutes = 15,
  }) async {
    final response = await post(
      ApiEndpoints.timeExtensionRequests,
      data: {
        'package_name': packageName,
        'requested_minutes': requestedMinutes,
      },
    );
    AppLogger.info(
      'requestExtension response: ${response.isSuccess}, ${response.message}',
    );
    return response;
  }

  /// GET /time-extension-requests?status=pending — parent views pending asks.
  Future<BaseResponse<List<TimeExtensionRequestItem>>>
  listPendingRequests() async {
    final response = await get<Map<String, dynamic>>(
      ApiEndpoints.timeExtensionRequests,
      queryParameters: {'status': 'pending'},
    );

    if (response.isSuccess) {
      try {
        final list = (response.data?['data'] as List? ?? [])
            .map(
              (e) =>
                  TimeExtensionRequestItem.fromJson(e as Map<String, dynamic>),
            )
            .toList();
        return BaseResponse.success(data: list, message: response.message);
      } catch (e) {
        AppLogger.error('Failed to parse extension requests: $e');
        return BaseResponse.error(
          message: 'Failed to parse extension requests: $e',
        );
      }
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  /// POST /time-extension-requests/:id/resolve — parent approves/denies.
  Future<BaseResponse> resolveExtensionRequest({
    required String requestId,
    required bool approve,
    required String platform,
  }) async {
    final response = await post(
      ApiEndpoints.resolveTimeExtensionRequest(requestId),
      data: {'approve': approve, 'platform': platform},
    );
    AppLogger.info(
      'resolveExtensionRequest response: ${response.isSuccess}, ${response.message}',
    );
    return response;
  }
}
