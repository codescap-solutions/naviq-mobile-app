import 'dart:convert';
import 'dart:io';
import 'package:child_track/app/home/model/home_model.dart';
import 'package:child_track/app/home/model/trip_detail_model.dart';
import 'package:child_track/app/home/model/trip_list_model.dart';
import 'package:child_track/core/services/api_endpoints.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:dio/dio.dart';

class HomeRepository extends BaseService {
  HomeRepository({required DioClient dioClient}) : super(dioClient);

  Future<BaseResponse<HomeResponse>> getHomeData({String? childId}) async {
    final response = await get<Map<String, dynamic>>(
      ApiEndpoints.getHome,
      queryParameters: childId != null ? {'child_id': childId} : null,
    );

    if (response.isSuccess && response.data != null) {
      try {
        final homeData = HomeResponse.fromJson(response.data!);
        return BaseResponse.success(data: homeData, message: response.message);
      } catch (e) {
        return BaseResponse.error(
          message: 'Failed to parse home data: ${e.toString()}',
        );
      }
    }

    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  /// Silently pushes a FORCE_REFRESH_DATA FCM to the child's device
  /// (server: notification.service.requestChildLocationUpdate), which makes
  /// the child app take a one-shot high-accuracy GPS fix — bypassing the
  /// distanceFilter that otherwise blocks new fixes while the child hasn't
  /// physically moved — and upload it. This only *requests* the push; the
  /// fresh location won't be in getTrackingSnapshot/getHomeData until the
  /// child device has had a few seconds to receive it, fetch, and upload.
  /// Server-side debounced to one request per child per 60s.
  Future<BaseResponse> refreshChildLiveStatus({required String childId}) async {
    final response = await post(
      ApiEndpoints.refreshChild,
      data: {'child_id': childId},
    );
    return response;
  }

  Future<BaseResponse<Map<String, dynamic>>> getTrackingSnapshot(String childId) async {
    final response = await get<Map<String, dynamic>>(
      ApiEndpoints.getTrackingSnapshot(childId),
    );

    if (response.isSuccess && response.data != null) {
      return BaseResponse.success(data: response.data!, message: response.message);
    }
    
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  Future<BaseResponse> getCurrentLocationDetails() async {
    await Future.delayed(const Duration(seconds: 1));
    return BaseResponse(
      isSuccess: true,
      message: "Static current location details",
      data: jsonEncode({
        "lat": 11.2488,
        "lng": 75.7839,
        "address": "Cubbon Road, Bengaluru",
        "place_name": "School",
        "since": "9:30am",
        "duration_minutes": 120,
      }),
    );
  }

  Future<BaseResponse<TripListResponse>> getTrips({
    String? childId,
    int? page,
    int? pageSize,
    bool includePoints = true,
  }) async {
    final queryParams = <String, dynamic>{};
    if (childId != null) queryParams['child_id'] = childId;
    if (page != null) queryParams['page'] = page;
    if (pageSize != null) queryParams['page_size'] = pageSize;
    queryParams['include_points'] = includePoints;

    final response = await get(
      ApiEndpoints.getTrips,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    if (response.isSuccess && response.data != null) {
      try {
        final tripsData = TripListResponse.fromJson(response.data!);
        return BaseResponse.success(data: tripsData, message: response.message);
      } catch (e) {
        return BaseResponse.error(
          message: 'Failed to parse trips data: ${e.toString()}',
        );
      }
    }

    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  Future<BaseResponse<TripDetailResponse>> getTripDetail(String tripId, {String? childId}) async {
    final url = childId != null
        ? 'parent/child/$childId/trips/$tripId'
        : ApiEndpoints.getTripDetail(tripId);
    final response = await get(
      url,
      queryParameters: childId != null ? {'child_id': childId} : null,
    );
    if (response.isSuccess && response.data != null) {
      try {
        final detail = TripDetailResponse.fromJson(response.data!);
        return BaseResponse.success(data: detail, message: response.message);
      } catch (e) {
        return BaseResponse.error(
          message: 'Failed to parse trip detail: ${e.toString()}',
        );
      }
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  Future<BaseResponse> linkChild({required String childCode}) async {
    final response = await post(
      ApiEndpoints.linkChild,
      data: {'child_code': childCode},
    );
    return response;
  }

  Future<BaseResponse> deleteChild(String childId) async {
    final response = await delete(ApiEndpoints.deleteChild(childId));
    return response;
  }

  Future<BaseResponse> updateChild({
    required String childId,
    required String name,
    int? age,
    String? avatar,
  }) async {
    final Map<String, dynamic> dataMap = {'name': name};
    if (age != null) {
      dataMap['age'] = age;
    }
    if (avatar != null) {
      dataMap['avatar'] = avatar;
    }

    final response = await put(
      ApiEndpoints.updateChild(childId),
      data: dataMap,
    );
    return response;
  }

  Future<BaseResponse<List<dynamic>>> getChildrenProfiles() async {
    final response = await get<List<dynamic>>(ApiEndpoints.parentChildren);

    if (response.isSuccess && response.data != null) {
      return BaseResponse.success(
        data: response.data!,
        message: response.message,
      );
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  Future<BaseResponse> updateChildSettings({
    required String childId,
    required bool webFilteringEnabled,
  }) async {
    final response = await put(
      ApiEndpoints.updateChildSettings,
      data: {'child_id': childId, 'web_filtering_enabled': webFilteringEnabled},
    );
    return response;
  }

  Future<BaseResponse> updateWebFilter({
    required String childId,
    required bool enabled,
  }) async {
    final response = await post(
      ApiEndpoints.webFilter,
      data: {'childId': childId, 'enabled': enabled},
    );
    return response;
  }

  Future<BaseResponse<bool>> getWebFilterStatus({
    required String childId,
  }) async {
    final response = await get(
      ApiEndpoints.webFilter,
      queryParameters: {'childId': childId},
    );

    if (response.isSuccess && response.data != null) {
      final isEnabled = response.data['web_filtering_enabled'] ?? false;
      return BaseResponse.success(data: isEnabled, message: response.message);
    }
    return BaseResponse.error(message: response.message);
  }

  Future<BaseResponse> updateDeletionRestriction({
    required String childId,
    required bool enabled,
  }) async {
    final response = await post(
      ApiEndpoints.restrictDeletion,
      data: {
        'child_id': childId,
        'isallowdelete':
            !enabled, // If deletion restriction is enabled, isallowdelete is false
      },
    );
    return response;
  }

  Future<BaseResponse<bool>> getDeletionRestrictionStatus({
    required String childId,
  }) async {
    final response = await get(
      ApiEndpoints.restrictDeletion,
      queryParameters: {'childId': childId},
    );

    if (response.isSuccess && response.data != null) {
      final isAllowDelete = response.data['isallowdelete'] ?? true;
      return BaseResponse.success(
        data: !isAllowDelete,
        message: response.message,
      );
    }
    return BaseResponse.error(message: response.message);
  }

  Future<BaseResponse<Map<String, dynamic>>> getNotificationPreferences() async {
    final response = await get<Map<String, dynamic>>(
      ApiEndpoints.notificationPreferences,
    );
    if (response.isSuccess && response.data != null) {
      return BaseResponse.success(
        data: response.data!,
        message: response.message,
      );
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  /// Updates a single notification-preference field, addressed by its dot
  /// path (e.g. "notifications.safePlaceArrival.enabled"), via PATCH so
  /// other fields are left untouched.
  Future<BaseResponse> updateNotificationPreference({
    required String fieldPath,
    required bool enabled,
  }) async {
    final response = await patch(
      ApiEndpoints.notificationPreferences,
      data: {fieldPath: enabled},
    );
    return response;
  }

  Future<BaseResponse> requestLocationSharing({
    required String phoneNumber,
    String? notes,
  }) async {
    final response = await post(
      ApiEndpoints.requestLocation,
      data: {
        'phone_number': phoneNumber,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return response;
  }

  Future<BaseResponse> respondToLocationRequest({
    required String requestId,
    required String action,
    List<String>? childIds,
    int? durationMinutes,
    String? rejectionReason,
  }) async {
    final response = await post(
      ApiEndpoints.respondToLocationRequest(requestId),
      data: {
        'action': action,
        if (childIds != null) 'child_ids': childIds,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        if (rejectionReason != null) 'rejection_reason': rejectionReason,
      },
    );
    return response;
  }

  Future<BaseResponse> revokeLocationSharing({required String shareId}) async {
    final response = await post(ApiEndpoints.revokeLocationShare(shareId));
    return response;
  }

  Future<BaseResponse<List<dynamic>>> getActiveOutgoingShares() async {
    final response = await get<List<dynamic>>(
      ApiEndpoints.activeOutgoingShares,
    );
    if (response.isSuccess && response.data != null) {
      return BaseResponse.success(
        data: response.data!,
        message: response.message,
      );
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  Future<BaseResponse<List<dynamic>>> getParentsContacts() async {
    final response = await get<List<dynamic>>(ApiEndpoints.parentContacts);
    if (response.isSuccess && response.data != null) {
      return BaseResponse.success(
        data: response.data!,
        message: response.message,
      );
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  Future<BaseResponse> addParentContact({
    required String name,
    required String relation,
    required String phone,
  }) async {
    final response = await post(
      ApiEndpoints.parentContacts,
      data: {'name': name, 'relation': relation, 'phone': phone},
    );
    return response;
  }

  Future<BaseResponse> editParentContact({
    required String id,
    required String name,
    required String relation,
    required String phone,
  }) async {
    final response = await put(
      ApiEndpoints.parentContactDetail(id),
      data: {'name': name, 'relation': relation, 'phone': phone},
    );
    return response;
  }

  Future<BaseResponse> deleteParentContact(String id) async {
    final response = await delete(ApiEndpoints.parentContactDetail(id));
    return response;
  }

  // ── Family Management (secondary guardians) ──────────────────────────────
  // Backend: guardian.controller.js. The primary parent (self, role 2) is
  // always included first with is_default:true, followed by any role-3
  // secondary guardians linked under the same parentId.

  Future<BaseResponse<List<dynamic>>> getGuardians() async {
    final response = await get<List<dynamic>>(ApiEndpoints.guardians);
    if (response.isSuccess && response.data != null) {
      return BaseResponse.success(data: response.data!, message: response.message);
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  /// Creates a real, independently-loginable guardian account (role 3) tied
  /// to this parent's family — not just a local display entry. Server
  /// enforces the plan's guardian-count limit and rejects an
  /// already-registered phone number.
  Future<BaseResponse> addGuardian({
    required String name,
    required String phoneNumber,
  }) async {
    final response = await post(
      ApiEndpoints.guardians,
      data: {'name': name, 'phone_number': phoneNumber},
    );
    return response;
  }

  /// Renames a guardian (or self). Server allows a guardian to rename only
  /// themselves; the primary parent can rename anyone in their family.
  Future<BaseResponse> updateGuardianName({
    required String id,
    required String name,
  }) async {
    final response = await put(
      ApiEndpoints.guardianDetail(id),
      data: {'name': name},
    );
    return response;
  }

  Future<BaseResponse> deleteGuardian(String id) async {
    final response = await delete(ApiEndpoints.guardianDetail(id));
    return response;
  }

  /// Multipart upload — field name must be "file" (server: multer
  /// `upload.single("file")` in guardian.routes).
  Future<BaseResponse<String>> uploadGuardianAvatar({
    required String id,
    required File file,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: 'avatar_guardian_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      });
      final response = await post(
        ApiEndpoints.guardianAvatar(id),
        data: formData,
      );
      if (response.isSuccess && response.data != null) {
        final avatarUrl = response.data['avatar_url'] as String?;
        if (avatarUrl != null) {
          return BaseResponse.success(data: avatarUrl, message: response.message);
        }
      }
      return BaseResponse.error(
        message: response.message.isEmpty ? 'Failed to upload avatar' : response.message,
      );
    } catch (e) {
      return BaseResponse.error(message: 'Error uploading avatar: ${e.toString()}');
    }
  }
}
