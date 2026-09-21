import '../../../core/services/dio_client.dart';
import '../../../core/services/shared_prefs_service.dart';
import '../../../core/services/api_endpoints.dart';
import '../../../core/services/base_service.dart';
import '../../../core/services/revenue_cat_service.dart';
import '../../../core/models/child_profile.dart';
import '../../../core/services/background_location_service.dart';

class AuthRepository extends BaseService {
  final SharedPrefsService _sharedPrefsService;

  AuthRepository({
    required DioClient dioClient,
    required SharedPrefsService sharedPrefsService,
  }) : _sharedPrefsService = sharedPrefsService,
       super(dioClient);

  // Send OTP
  Future<BaseResponse> sendOtp(String phoneNumber) async {
    try {
      final response = await post(
        ApiEndpoints.sendOtp,
        data: {'phoneNumber': phoneNumber},
      );

      if (response.isSuccess) {
        // Save phone number for OTP verification
        await _sharedPrefsService.setUserPhone(phoneNumber);
      }

      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // Verify OTP
  Future<BaseResponse> verifyOtp(String otp) async {
    try {
      final phoneNumber = _sharedPrefsService.getUserPhone();
      if (phoneNumber == null) {
        return BaseResponse.error(
          message: 'Phone number not found. Please try again.',
        );
      }

      final response = await post(
        ApiEndpoints.verifyOtp,
        data: {'phoneNumber': phoneNumber, 'otp': otp},
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        final isNewUser = data['is_new_user'] as bool? ?? false;
        final phoneNumber = data['phoneNumber'] as String?;

        // Save phone number if provided
        if (phoneNumber != null) {
          await _sharedPrefsService.setUserPhone(phoneNumber);
        }

        // If new user, don't save auth data yet (will be saved after registration)
        if (!isNewUser) {
          // Save auth token and user ID (parent ID)
          // Handle different response structures
          final token = data['token'] as String?;
          final refreshToken = data['refresh_token'] as String?;
          final userData = data['user'] as Map<String, dynamic>?;
          final parentId =
              userData?['id'] as String? ??
              data['user_id'] as String? ??
              data['_id'] as String?;
          final name = userData?['name'] as String? ?? data['name'] as String?;
          final childrenData = data['children'] as List<dynamic>?;

          if (parentId != null) {
            await _sharedPrefsService.setUserId(parentId);
            // Also save as parent_id for clarity
            await _sharedPrefsService.setString('parent_id', parentId);
          }
          if (token != null) {
            await _sharedPrefsService.setAuthToken(token);
          }
          if (refreshToken != null) {
            await _sharedPrefsService.setRefreshToken(refreshToken);
          }
          if (name != null) {
            await _sharedPrefsService.setString('parent_name', name);
          }

          // Save children count and full list
          if (childrenData != null) {
            await _sharedPrefsService.setInt(
              'children_count',
              childrenData.length,
            );

            // Parse and save full list of children
            final List<ChildProfile> childProfiles = [];

            for (var child in childrenData) {
              if (child is Map<String, dynamic>) {
                final childId =
                    child['child_id'] as String? ??
                    child['_id'] as String? ??
                    child['id'] as String?;
                final childName = child['name'] as String? ?? 'Unknown';

                if (childId != null && token != null) {
                  childProfiles.add(
                    ChildProfile(
                      childCode: child['child_code'] as String? ?? '',
                      childId: childId,
                      childName: childName,
                      authToken: token, // Using parent token
                      lastActiveAt: DateTime.now(),
                      avatar: child['avatar'] as String?,
                    ),
                  );
                }
              }
            }

            if (childProfiles.isNotEmpty) {
              await _sharedPrefsService.saveChildren(childProfiles);

              // Set first child as default active if not already set
              final currentChildId = _sharedPrefsService.getString('child_id');
              if (currentChildId == null) {
                await _sharedPrefsService.setString(
                  'child_id',
                  childProfiles.first.childId,
                );
                await _sharedPrefsService.setString(
                  'child_code',
                  childProfiles.first.childCode,
                );
              }
            } else if (childrenData.isNotEmpty && childrenData[0] is String) {
              // Handle case where children are just IDs (less likely now but for safety)
              // We can't build profiles without names, so we rely on fetching later or
              // just saving the first ID as we did before.
              final firstChildId = childrenData[0] as String;
              await _sharedPrefsService.setString('child_id', firstChildId);
            }
          }
        }

        // Sync user identity with RevenueCat after successful login
        final loggedInParentId = _sharedPrefsService.getString('parent_id');
        if (loggedInParentId != null) {
          await RevenueCatService.instance.logIn(
            loggedInParentId,
            displayName: _sharedPrefsService.getString('parent_name'),
            phoneNumber: _sharedPrefsService.getUserPhone(),
          );
        }
      }

      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // Refresh Token
  Future<BaseResponse> refreshToken() async {
    try {
      final currentRefreshToken = _sharedPrefsService.getRefreshToken();
      if (currentRefreshToken == null) {
        return BaseResponse.error(message: 'No refresh token available.');
      }

      final response = await post(
        ApiEndpoints.refreshToken,
        data: {'refresh_token': currentRefreshToken},
      );

      if (response.isSuccess && response.data != null) {
        final token = response.data!['token'] as String?;
        final newRefreshToken = response.data!['refresh_token'] as String?;
        if (token != null) {
          await _sharedPrefsService.setAuthToken(token);
        }
        if (newRefreshToken != null) {
          await _sharedPrefsService.setRefreshToken(newRefreshToken);
        }
      }

      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // Logout
  Future<BaseResponse> logout() async {
    try {
      final response = await post(ApiEndpoints.logout);

      // Sign out from RevenueCat before clearing local storage
      await RevenueCatService.instance.logOut();

      // Clear local storage regardless of API response
      await _sharedPrefsService.logout();
      await BackgroundLocationService().stop(); // Ensure tracking stops

      return response;
    } catch (e) {
      // Clear local storage even if API call fails
      await RevenueCatService.instance.logOut();
      await _sharedPrefsService.logout();
      await BackgroundLocationService().stop(); // Ensure tracking stops
      return BaseResponse.error(message: e.toString());
    }
  }

  // Check if user is logged in
  bool isLoggedIn() {
    return _sharedPrefsService.isLoggedIn();
  }

  // Register User
  Future<BaseResponse> registerUser({
    required String phoneNumber,
    required String name,
    required String parentingSituation,
    required String parentRoutine,
    Map<String, dynamic>? address,
  }) async {
    try {
      final data = <String, dynamic>{
        'phoneNumber': phoneNumber,
        'name': name,
        'parentingSituation': parentingSituation,
        'parentRoutine': parentRoutine,
      };

      if (address != null) {
        data['address'] = address;
      }

      final response = await post(ApiEndpoints.registerUser, data: data);

      if (response.isSuccess && response.data != null) {
        // Save auth token and user ID (parent ID) after registration
        final responseData = response.data!;
        final token = responseData['token'] as String?;
        final refreshToken = responseData['refresh_token'] as String?;
        final parentId =
            responseData['user']?['id'] as String? ??
            responseData['_id'] as String?;
        final savedName = responseData['name'] as String?;

        if (parentId != null) {
          await _sharedPrefsService.setUserId(parentId);
          await _sharedPrefsService.setString('parent_id', parentId);
        }
        if (token != null) {
          await _sharedPrefsService.setAuthToken(token);
        }
        if (refreshToken != null) {
          await _sharedPrefsService.setRefreshToken(refreshToken);
        }
        if (savedName != null) {
          await _sharedPrefsService.setString('parent_name', savedName);
        }
        // New user has no children initially
        await _sharedPrefsService.setInt('children_count', 0);
        
        // Sync user identity with RevenueCat after successful registration
        if (parentId != null) {
          await RevenueCatService.instance.logIn(
            parentId,
            displayName: savedName,
            phoneNumber: _sharedPrefsService.getUserPhone(),
          );
        }
      }

      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // Register parent FCM token with server
  Future<BaseResponse> registerParentFcmToken(String fcmToken) async {
    try {
      final response = await put(
        ApiEndpoints.parentFcmToken,
        data: {'fcm_token': fcmToken},
      );
      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // Remove parent FCM token from server (on logout)
  Future<BaseResponse> removeParentFcmToken(String fcmToken) async {
    try {
      final response = await delete(
        ApiEndpoints.parentFcmToken,
        data: {'fcm_token': fcmToken},
      );
      return response;
    } catch (e) {
      return BaseResponse.error(message: e.toString());
    }
  }

  // Get current user info
  Map<String, String?> getCurrentUser() {
    return {
      'user_id': _sharedPrefsService.getUserId(),
      'phone': _sharedPrefsService.getUserPhone(),
      'token': _sharedPrefsService.getAuthToken(),
    };
  }
}
