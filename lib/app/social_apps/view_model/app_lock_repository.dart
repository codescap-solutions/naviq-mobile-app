import 'package:child_track/app/social_apps/model/locked_app_model.dart';
import 'package:child_track/core/services/api_endpoints.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/utils/app_logger.dart';

class AppLockRepository extends BaseService {
  AppLockRepository({required DioClient dioClient}) : super(dioClient);

  // ─── Parent APIs ───

  /// GET /parent/locked-apps?childId=X
  Future<BaseResponse<ParentLockedAppsResponse>> getLockedApps({
    required String childId,
  }) async {
    final response = await get<Map<String, dynamic>>(
      ApiEndpoints.parentLockedApps,
      queryParameters: {'childId': childId},
    );

    if (response.isSuccess && response.data != null) {
      try {
        final parsed = ParentLockedAppsResponse.fromJson(response.data!);
        return BaseResponse.success(data: parsed, message: response.message);
      } catch (e) {
        AppLogger.error('Failed to parse locked apps response: $e');
        return BaseResponse.error(message: 'Failed to parse locked apps: $e');
      }
    }

    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  /// PUT /parent/locked-apps
  Future<BaseResponse<ParentLockedAppsResponse>> updateLockedApps({
    required String childId,
    required List<LockedPackageItem> lockedPackages,
  }) async {
    final body = {
      'child_id': childId,
      'locked_packages': lockedPackages.map((p) => p.toJson()).toList(),
    };

    final response = await put<Map<String, dynamic>>(
      ApiEndpoints.parentLockedApps,
      data: body,
    );

    if (response.isSuccess && response.data != null) {
      try {
        final parsed = ParentLockedAppsResponse.fromJson(response.data!);
        return BaseResponse.success(data: parsed, message: response.message);
      } catch (e) {
        AppLogger.error('Failed to parse update locked apps response: $e');
        return BaseResponse.error(message: 'Failed to parse response: $e');
      }
    }

    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  // ─── Child API ───

  /// GET /child/locked-apps
  Future<BaseResponse<ChildLockedAppsResponse>> getChildLockedApps() async {
    final response = await get<Map<String, dynamic>>(
      ApiEndpoints.childLockedApps,
    );

    if (response.isSuccess && response.data != null) {
      try {
        final parsed = ChildLockedAppsResponse.fromJson(response.data!);
        return BaseResponse.success(data: parsed, message: response.message);
      } catch (e) {
        AppLogger.error('Failed to parse child locked apps: $e');
        return BaseResponse.error(message: 'Failed to parse: $e');
      }
    }

    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  // ─── New Lock/Unlock APIs (POST /lock-apps, POST /unlock-apps) ───

  /// POST /lock-apps — locks specific apps on the child device
  Future<BaseResponse> lockApps({
    required String childId,
    required List<String> tokens,
    required String platform,
    int durationMinutes = 0,
  }) async {
    final body = {
      'childId': childId,
      'tokens': tokens,
      'platform': platform,
      'durationMinutes': durationMinutes,
    };

    final response = await post(ApiEndpoints.lockApps, data: body);

    AppLogger.info(
      'lockApps response: ${response.isSuccess}, ${response.message}',
    );
    return response;
  }

  /// POST /unlock-apps — unlocks specific apps on the child device
  Future<BaseResponse> unlockApps({
    required String childId,
    required List<String> tokens,
    required String platform,
  }) async {
    final body = {'childId': childId, 'tokens': tokens, 'platform': platform};

    final response = await post(ApiEndpoints.unlockApps, data: body);

    AppLogger.info(
      'unlockApps response: ${response.isSuccess}, ${response.message}',
    );
    return response;
  }
}
