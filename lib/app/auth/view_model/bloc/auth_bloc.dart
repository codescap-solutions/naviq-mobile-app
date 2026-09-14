import 'package:child_track/app/auth/view_model/auth_repository.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_event.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_state.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final SharedPrefsService _sharedPrefsService;
  AuthBloc({
    required AuthRepository authRepository,
    required SharedPrefsService sharedPrefsService,
  }) : _authRepository = authRepository,
       _sharedPrefsService = sharedPrefsService,
       super(AuthInitial()) {
    on<AuthStarted>(_onAuthStarted);
    on<SendOtp>(_onSendOtp);
    on<VerifyOtp>(_onVerifyOtp);
    on<SelectChild>(_onSelectChild);
    on<RegisterUser>(_onRegisterUser);
    on<AuthLoggedIn>(_onAuthLoggedIn);
    on<AuthLoggedOut>(_onAuthLoggedOut);
    AppLogger.info('AuthBloc initialized with SelectChild handler');
  }

  void _onAuthStarted(AuthStarted event, Emitter<AuthState> emit) {
    emit(AuthLoading());
  }

  Future<void> _onSendOtp(SendOtp event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await _authRepository.sendOtp(event.phoneNumber);
      if (response.isSuccess) {
        emit(AuthOtpSent(phoneNumber: event.phoneNumber));
      } else {
        emit(AuthError(message: response.message));
      }
    } catch (e) {
      AppLogger.error('Error sending OTP: ${e.toString()}');
      emit(AuthError(message: 'Failed to send OTP: ${e.toString()}'));
    }
  }

  Future<void> _onVerifyOtp(VerifyOtp event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await _authRepository.verifyOtp(event.otp);
      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        final isNewUser = data['is_new_user'] as bool? ?? false;
        final phoneNumber = data['phoneNumber'] as String?;
        final parentId = data['user']?['id'] as String?;
        final token = data['token'] as String?;
        // Backend already tells us this — user.is_owner is `role !== 3`
        // (secondary "guardian" accounts are role 3). Nothing here was ever
        // reading it, so isPrimaryParent's SharedPreferences key was never
        // written and defaulted to true for everyone — a secondary guardian
        // logging into Family Management saw full primary-parent controls
        // (edit/delete guardians, including a "delete self" affordance),
        // and the same default silently over-granted every other screen
        // gated on isPrimaryParent (settings, geofencing, contacts).
        final isOwner = data['user']?['is_owner'] as bool? ?? true;

        // Save parent ID, token, and role
        if (parentId != null) {
          await _sharedPrefsService.setString('parent_id', parentId);
          await _sharedPrefsService.setUserId(parentId);
        }
        await _sharedPrefsService.setBool('is_primary_parent', isOwner);
        if (token != null) {
          await _sharedPrefsService.setAuthToken(token);
        }

        // Check if this is a new user
        if (isNewUser && phoneNumber != null) {
          emit(AuthNewUser(phoneNumber: phoneNumber));
        } else if (response.data != null) {
          // Existing user - check if user has children
          final children = data['children'] as List<dynamic>?;
          final hasChildren = children != null && children.isNotEmpty;

          if (hasChildren) {
            // Check how many children
            if (children.length > 1) {
              // Multiple children: Auto-parse all child profiles and save locally
              final List<ChildProfile> profilesList = [];
              for (var child in children) {
                if (child is Map<String, dynamic>) {
                  final childId =
                      child['child_id'] as String? ??
                      child['_id'] as String? ??
                      '';
                  final childCode = child['child_code'] as String? ?? '';
                  final childName =
                      child['name'] as String? ??
                      child['child_name'] as String? ??
                      'Child';
                  final avatar = child['avatar'] as String?;
                  profilesList.add(
                    ChildProfile(
                      childId: childId,
                      childCode: childCode,
                      childName: childName,
                      authToken: token ?? '',
                      avatar: avatar,
                      lastActiveAt: DateTime.now(),
                    ),
                  );
                }
              }

              // Save all children locally in SharedPreferences
              await _sharedPrefsService.saveChildren(profilesList);

              // Set the first child as the default active child in local preferences
              if (profilesList.isNotEmpty) {
                final firstChild = profilesList.first;
                await _sharedPrefsService.setString(
                  'child_id',
                  firstChild.childId,
                );
                await _sharedPrefsService.setString(
                  'child_code',
                  firstChild.childCode,
                );
                await _sharedPrefsService.setString(
                  'child_name',
                  firstChild.childName,
                );
              }
              await _sharedPrefsService.setInt(
                'children_count',
                profilesList.length,
              );

              // Register FCM token with server
              FirebaseNotificationService().registerTokenWithServer();

              emit(const AuthSuccess(hasChildren: true, showProfilesTab: true));
            } else {
              // Single child: Auto-select
              final firstChild = children[0] as Map<String, dynamic>?;
              final childId = firstChild?['child_id'] as String?;
              final childCode = firstChild?['child_code'] as String?;

              if (childId != null) {
                await _sharedPrefsService.setString('child_id', childId);
                AppLogger.info('OTP verification: Child ID saved: $childId');
              }
              if (childCode != null) {
                await _sharedPrefsService.setString('child_code', childCode);
              }
              // Save children count
              await _sharedPrefsService.setInt(
                'children_count',
                children.length,
              );
              // Register FCM token with server after successful login
              FirebaseNotificationService().registerTokenWithServer();
              emit(const AuthSuccess(hasChildren: true));
            }
          } else {
            // No children
            emit(const AuthSuccess(hasChildren: false));
          }
        } else {
          emit(AuthNeedsRegistration());
        }
      } else {
        emit(AuthError(message: response.message));
      }
    } catch (e) {
      AppLogger.error('Error verifying OTP: ${e.toString()}');
      emit(AuthError(message: 'Failed to verify OTP: ${e.toString()}'));
    }
  }

  Future<void> _onSelectChild(
    SelectChild event,
    Emitter<AuthState> emit,
  ) async {
    try {
      if (state is AuthSelectChild) {
        final currentState = state as AuthSelectChild;
        // Verify child exists in the list we have (optional security check)
        final selectedChild = currentState.children.firstWhere(
          (child) => child['child_id'] == event.childId,
          orElse: () => {},
        );

        if (selectedChild.isNotEmpty) {
          final childId = selectedChild['child_id'] as String;
          final childCode = selectedChild['child_code'] as String?;

          await _sharedPrefsService.setString('child_id', childId);
          if (childCode != null) {
            await _sharedPrefsService.setString('child_code', childCode);
          }
          await _sharedPrefsService.setInt(
            'children_count',
            currentState.children.length,
          );

          // Register FCM token with server after child selection
          FirebaseNotificationService().registerTokenWithServer();
          emit(const AuthSuccess(hasChildren: true));
        } else {
          emit(const AuthError(message: 'Selected child not found'));
        }
      }
    } catch (e) {
      AppLogger.error('Error selecting child: ${e.toString()}');
      emit(AuthError(message: 'Failed to select child: ${e.toString()}'));
    }
  }

  Future<void> _onRegisterUser(
    RegisterUser event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final response = await _authRepository.registerUser(
        phoneNumber: event.phoneNumber,
        name: event.name,
        parentingSituation: event.parentingSituation,
        parentRoutine: event.parentRoutine,
        address: event.address,
      );
      if (response.isSuccess) {
        // After registration, user has no children yet
        // Register FCM token with server after registration
        FirebaseNotificationService().registerTokenWithServer();
        emit(const AuthSuccess(hasChildren: false));
      } else {
        emit(AuthError(message: response.message));
      }
    } catch (e) {
      AppLogger.error('Error registering user: ${e.toString()}');
      emit(AuthError(message: 'Failed to register: ${e.toString()}'));
    }
  }

  void _onAuthLoggedIn(AuthLoggedIn event, Emitter<AuthState> emit) {
    emit(const AuthSuccess(hasChildren: false));
  }

  void _onAuthLoggedOut(AuthLoggedOut event, Emitter<AuthState> emit) {
    emit(AuthInitial());
  }
}
