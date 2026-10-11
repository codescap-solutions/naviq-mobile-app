import 'dart:developer';
import 'dart:io';
import 'package:child_track/core/services/api_endpoints.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/services/socket_service.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:flutter/services.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/services/device_info_service.dart';
import 'package:child_track/core/di/injector.dart';

class ChildRepo extends BaseService {
  final SharedPrefsService _sharedPrefsService;
  final SocketService _socketService = SocketService();

  ChildRepo({
    required DioClient dioClient,
    SharedPrefsService? sharedPrefsService,
  }) : _sharedPrefsService = sharedPrefsService ?? SharedPrefsService(),
       super(dioClient);

  void initializeSocket(String childId) {
    _socketService.initSocket();
    _socketService.joinRoom(childId);
  }

  Future<BaseResponse> childLogin({required String childCode}) async {
    try {
      final response = await post(
        ApiEndpoints.childLogin,
        data: {'child_code': childCode},
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        final token = data['token'] as String?;
        final childId =
            data['child']?['child_id'] as String? ?? data['_id'] as String?;

        if (token != null) {
          await _sharedPrefsService.setAuthToken(token);
          AppLogger.info('Child login: Auth token saved');
        }
        if (childId != null) {
          await _sharedPrefsService.setString('child_id', childId);
          log('child_id saved: $childId');
          await _sharedPrefsService.setString('child_code', childCode);
          AppLogger.info('Child login: Child ID saved: $childId');

          // iOS: sync credentials to App Group so native background handler can POST data
          // without depending on the Flutter engine being alive.
          await syncAppGroupCredentials();

          final name = data['child']?['name'] as String? ?? 'Child';
          await _sharedPrefsService.setString('child_name', name);

          // Multi-Child: Save to profile list
          if (token != null) {
            final profile = ChildProfile(
              childCode: childCode,
              childId: childId,
              childName: name,
              authToken: token,
              lastActiveAt: DateTime.now(),
            );
            await _sharedPrefsService.addChild(profile);
          }

          final parentPhone = data['child']?['parent_phone']?.toString();
          if (parentPhone != null) {
            await _sharedPrefsService.setString('parent_phone', parentPhone);
          }

          // Parse and store allow deletion permission
          final isAllowDelete = data['child']?['isallowdelete'] as bool? ?? true;
          await _sharedPrefsService.setAllowDelete(isAllowDelete);
          AppLogger.info('Child login: isallowdelete saved: $isAllowDelete');

          // Apply Web Filtering settings
          await _applyWebFiltering(data['child']);

          // Verify it was saved correctly
          final savedChildId = _sharedPrefsService.getString('child_id');
          AppLogger.info('Child login: Verified saved child_id: $savedChildId');

          // Initialize Socket
          _socketService.initSocket();
          _socketService.joinRoom(childId);
        } else {
          AppLogger.warning('Child login: Child ID not found in response');
        }
      }

      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  Future<BaseResponse<String>> uploadAvatar(File file) async {
    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          file.path,
          filename: 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      });

      final response = await post(
        ApiEndpoints.uploadAvatar,
        data: formData,
      );

      if (response.isSuccess && response.data != null) {
        final avatarUrl = response.data['avatar_url'] as String?;
        if (avatarUrl != null) {
          return BaseResponse.success(data: avatarUrl, message: response.message);
        }
      }
      return BaseResponse.error(message: response.message.isEmpty ? 'Failed to upload avatar' : response.message);
    } catch (e) {
      return BaseResponse.error(message: 'Error uploading avatar: ${e.toString()}');
    }
  }

  Future<BaseResponse> createChild({
    required String name,
    required int age,
    required String travelOption,
    String? avatar,
    String? deviceImei,
  }) async {
    final Map<String, dynamic> dataMap = {
      'name': name,
      'age': age,
      'traveloption': travelOption,
    };

    if (avatar != null) {
      dataMap['avatar'] = avatar;
    }

    final response = await post(
      ApiEndpoints.createChild,
      data: dataMap,
    );

    if (response.isSuccess && response.data != null) {
      final data = response.data!;
      // Apply Web Filtering settings
      await _applyWebFiltering(data['child']);
    }

    return response;
  }

  /// Helper to extract and apply web filtering status from child data object
  Future<void> _applyWebFiltering(dynamic childData) async {
    if (childData is! Map) return;

    final isWebFilteringEnabled =
        childData['web_filtering_enabled'] as bool? ?? false;
    AppLogger.info('Applying web filtering status: $isWebFilteringEnabled');

    await _sharedPrefsService.setBool('block_18plus', isWebFilteringEnabled);

    try {
      await injector<DeviceInfoService>().setWebFiltering(
        isWebFilteringEnabled,
      );
    } catch (e) {
      AppLogger.error('Failed to apply native web filtering: $e');
    }
  }

  Future<BaseResponse> postChildData(Map<String, dynamic> data) async {
    if (_socketService.isConnected) {
      _socketService.sendStatus(data);
    }
    final response = await post(ApiEndpoints.postDeviceInfo, data: data);
    return response;
  }

  Future<BaseResponse> postAppUsage(Map<String, dynamic> data) async {
    final response = await post(ApiEndpoints.postAppUsage, data: data);
    return response;
  }

  Future<BaseResponse> getAvailableIcons() async {
    final response = await get(ApiEndpoints.childAvailableIcons);
    return response;
  }

  Future<BaseResponse> uploadAppIcon(
    String packageName,
    List<int> iconBytes,
  ) async {
    final formData = FormData.fromMap({
      packageName: MultipartFile.fromBytes(
        iconBytes,
        filename: '$packageName.png',
        contentType: MediaType('image', 'png'),
      ),
    });
    final response = await post(
      ApiEndpoints.childUploadAppIcons,
      data: formData,
    );
    return response;
  }

  Future<BaseResponse> postChildLocation(Map<String, dynamic> data) async {
    if (_socketService.isConnected) {
      _socketService.sendLocation(data);
    }
    final response = await post(ApiEndpoints.postLocation, data: data);
    return response;
  }

  /// Report a client-detected geofence transition (ENTER/EXIT/DWELL) immediately.
  /// Backed by the existing authenticated `/child/geofence-event` endpoint
  /// (see naviQ-server child.routes.js), which requires `childId` in the body.
  Future<BaseResponse> postGeofenceEvent({
    required String childId,
    required String geofenceId,
    required String eventType,
    required String timestamp,
    String source = 'local_engine',
  }) async {
    final response = await post(
      ApiEndpoints.postGeofenceEvent,
      data: {
        'childId': childId,
        'geofenceId': geofenceId,
        'eventType': eventType,
        'timestamp': timestamp,
        'source': source,
      },
    );
    return response;
  }

  /// Fetch the geofences (saved places) assigned to this child, so the
  /// client-side LocalGeofenceEngine has something to check GPS fixes against.
  Future<BaseResponse<List<dynamic>>> getChildGeofences(String childId) async {
    final response = await get<List<dynamic>>(
      '${ApiEndpoints.getChildGeofences}?childId=$childId',
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

  Future<BaseResponse> postTripLocation({
    required String childId,
    required Map<String, dynamic> data,
  }) async {
    final response = await post(
      ApiEndpoints.postTripLocation(childId),
      data: data,
    );
    return response;
  }

  Future<BaseResponse> postTripEnd({
    required String childId,
    required Map<String, dynamic> data,
  }) async {
    final response = await post(
      ApiEndpoints.postTripEnd(childId),
      data: data,
    );
    return response;
  }

  // Register child FCM token with server
  Future<BaseResponse> registerChildFcmToken({
    required String childId,
    required String fcmToken,
  }) async {
    try {
      final response = await put(
        ApiEndpoints.childFcmToken,
        data: {'child_id': childId, 'fcm_token': fcmToken},
      );
      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // Remove child FCM token from server (on logout)
  Future<BaseResponse> removeChildFcmToken({
    required String childId,
    required String fcmToken,
  }) async {
    try {
      final response = await delete(
        ApiEndpoints.childFcmToken,
        data: {'child_id': childId, 'fcm_token': fcmToken},
      );
      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // Send SOS emergency
  Future<BaseResponse> sendSOS({
    required String childId,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await post(
        ApiEndpoints.childSOS,
        data: {'child_id': childId, 'lat': lat, 'lng': lng},
      );
      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // ── Native Background Sync — Credential Bridge (both platforms) ──────────
  /// iOS: saves auth token, API base URL, and child ID into the App Group
  /// (group.com.truenyx.naviq) via MethodChannel so the native Swift handler
  /// (handleNativeDataSync) can POST to the server even when Flutter is suspended.
  ///
  /// Android: mirrors just the auth token into plain (non-secure)
  /// SharedPreferences — child_id is already stored there via setString(),
  /// and GeofenceBroadcastReceiver (native Kotlin) reads both directly, the
  /// same way AppLockService.kt already reads locked-packages CSV. No
  /// MethodChannel round-trip needed since the plain shared_preferences
  /// plugin already writes to the file native code reads.
  Future<void> syncAppGroupCredentials() async {
    final token = _sharedPrefsService.getAuthToken();
    final childId = _sharedPrefsService.getString('child_id');

    if (Platform.isAndroid) {
      try {
        if (token != null && token.isNotEmpty) {
          await _sharedPrefsService.setString('native_auth_token', token);
        }
        AppLogger.info('ChildRepo: Android native geofence credentials synced ✅');
      } catch (e) {
        AppLogger.error('ChildRepo: Failed to sync Android native credentials: $e');
      }
      return;
    }

    if (!Platform.isIOS) return;
    try {
      const channel = MethodChannel('com.truenyx.naviq/parental_control');

      if (token != null && token.isNotEmpty) {
        await channel.invokeMethod<bool>('saveAuthToken', token);
      }
      await channel.invokeMethod<bool>('saveApiBaseUrl', ApiEndpoints.baseUrl);
      if (childId != null && childId.isNotEmpty) {
        await channel.invokeMethod<bool>('saveChildId', childId);
      }
      AppLogger.info('ChildRepo: iOS App Group credentials synced ✅');
    } catch (e) {
      AppLogger.error('ChildRepo: Failed to sync App Group credentials: $e');
    }
  }

  Future<void> clearAppGroupCredentials() async {
    if (!Platform.isIOS) return;
    try {
      const channel = MethodChannel('com.truenyx.naviq/parental_control');
      await channel.invokeMethod<bool>('saveAuthToken', '');
      await channel.invokeMethod<bool>('saveApiBaseUrl', '');
      await channel.invokeMethod<bool>('saveChildId', '');
      AppLogger.info('ChildRepo: iOS App Group credentials cleared ✅');
    } catch (e) {
      AppLogger.error('ChildRepo: Failed to clear App Group credentials: $e');
    }
  }

  Future<BaseResponse<List<dynamic>>> getChildContacts() async {
    final response = await get<List<dynamic>>(
      ApiEndpoints.childContacts,
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

  /// Fetch categorized catalog apps from backend
  Future<BaseResponse<Map<String, dynamic>>> getScreenTimeApps() async {
    final response = await get<Map<String, dynamic>>(
      ApiEndpoints.screenTimeApps,
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

  /// Bulk upload device app mappings to backend
  Future<BaseResponse<dynamic>> postAppMappings(Map<String, dynamic> body) async {
    final childId = _sharedPrefsService.getString('child_id');
    if (childId != null) {
      body['childId'] = childId;
    }
    final response = await post<dynamic>(
      ApiEndpoints.appMappings,
      data: body,
    );
    if (response.isSuccess) {
      return BaseResponse.success(
        data: response.data,
        message: response.message,
      );
    }
    return BaseResponse.error(
      message: response.message,
      statusCode: response.statusCode,
    );
  }

  /// Fetch existing mappings for this device to support resuming session
  Future<BaseResponse<List<dynamic>>> getAppMappings(String deviceId) async {
    final childId = _sharedPrefsService.getString('child_id');
    final query = childId != null ? '?deviceId=$deviceId&childId=$childId' : '?deviceId=$deviceId';
    final response = await get<List<dynamic>>(
      '${ApiEndpoints.appMappings}$query',
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
}

