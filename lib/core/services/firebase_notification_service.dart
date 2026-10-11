import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import '../utils/structured_logger.dart';
import 'package:child_track/core/services/background_task_service.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/auth/view_model/auth_repository.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/app/social_apps/view_model/bloc/app_lock_bloc.dart';
import 'package:child_track/app/social_apps/view_model/bloc/app_lock_event.dart';
import 'package:child_track/app/social_apps/view_model/app_lock_repository.dart';
import 'package:workmanager/workmanager.dart';
import 'package:child_track/core/services/csv_file_logger.dart';
import 'package:child_track/core/services/oem_battery_helper.dart';
import 'package:child_track/core/services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:child_track/core/services/tracking/geofence_tracking_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart' show GlobalKey, NavigatorState, MaterialPageRoute;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/app/chat/view/chat_screen.dart';
import 'package:child_track/app/chat/view_model/bloc/chat_bloc.dart';
import 'package:child_track/core/services/screen_time_sync_service.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/services/notifications/child_notification_router.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/app/childapp/view_model/repository/device_info_service.dart';
import 'package:child_track/core/services/device_info_service.dart' show DeviceInfoService;

/// Top-level function for handling background messages
/// This must be a top-level function, not a class method
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await dotenv.load(fileName: ".env");
  
  // Initialize CSV Logger for background isolates
  await CsvFileLogger.instance.init();
  
  AppLogger.info('Background message received: ${message.messageId}');
  AppLogger.info('Background message data: ${message.data}');

  // Save background notification locally for parent app
  try {
    await SharedPrefsService.init();
    final prefs = SharedPrefsService();
    if (prefs.isParent) {
      final parsed = FirebaseNotificationService.parseNotificationContent(message);
      if (parsed['type'] != 'SYNC_SCREEN_TIME' && parsed['type'] != 'SYNC_LOCKED_APPS') {
        await prefs.addNotification({
          'id': message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'title': parsed['title'],
          'body': parsed['body'],
          'timestamp': FirebaseNotificationService._eventTimestampOrNow(message),
          'type': parsed['type'],
          'isRead': false,
        });
        AppLogger.info('Saved background notification locally');

        // Save pending request to local SharedPrefs
        if (message.data['type'] == 'location_share_request') {
          await prefs.setString('pending_location_share_request', json.encode(message.data));
          AppLogger.info('Saved pending location share request to SharedPrefs');
        }
      }
    }
  } catch (e) {
    AppLogger.error('Failed to save background notification: $e');
  }

  // Log to CSV for offline analysis — type/id only, not the full data
  // payload (may carry place names / other identifying details).
  StructuredLogger.log(
    LogTag.FCM,
    'BG message received: type=${message.data['type']} id=${message.messageId}',
  );

  if (message.data['type'] == 'SYNC_SCREEN_TIME') {
    AppLogger.info('Received SYNC_SCREEN_TIME command via FCM');
    try {
      // CRITICAL: Initialize WorkManager in background isolate.
      // When the app is killed, main() hasn't run, so WorkManager
      // is not initialized. Safe to call multiple times.
      await Workmanager().initialize(callbackDispatcher);
      await BackgroundTaskService.triggerImmediateSync();
      AppLogger.info('SYNC_SCREEN_TIME: WorkManager task scheduled');
    } catch (e) {
      AppLogger.error('SYNC_SCREEN_TIME: Failed to schedule sync: $e');
    }
  }

  if (message.data['type'] == 'SYNC_LOCKED_APPS' ||
      message.data['action'] == 'lock_apps' ||
      message.data['action'] == 'unlock_apps') {
    final action = message.data['action'] ?? message.data['type'] ?? 'unknown';
    AppLogger.info('Received $action command via FCM (background)');
    try {
      // Background isolate can't use MethodChannel to reach native plugins on some setups.
      // On Android, we fetch the lock list and write it to SharedPreferences,
      // which IS shared across isolates AND readable by native Kotlin code.
      // AppLockService reads 'flutter.locked_packages_csv' from FlutterSharedPreferences.
      await SharedPrefsService.init();

      // We need DioClient to call the API — initialize minimal deps
      if (!injector.isRegistered<SharedPrefsService>()) {
        await initializeDependencies();
      }

      final repo = injector<AppLockRepository>();
      final response = await repo.getChildLockedApps();

      if (response.isSuccess && response.data != null) {
        final packages = response.data!.lockedPackages
            .map((e) => e.packageName)
            .toList();

        // CRITICAL: Write using the EXACT key that AppLockService.kt reads.
        // AppLockService reads from FlutterSharedPreferences with key "flutter.locked_packages_csv".
        // Flutter's SharedPreferences plugin automatically prepends "flutter." to all keys,
        // so calling prefs.setString('locked_packages_csv', ...) writes "flutter.locked_packages_csv".
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('locked_packages_csv', packages.join(','));
        AppLogger.info(
          '$action (bg): Saved ${packages.length} packages to SharedPrefs CSV: $packages',
        );

        // Attempt to sync natively for iOS from background isolate
        if (Platform.isIOS) {
          try {
            const iosChannel = MethodChannel('com.truenyx.naviq/parental_control');
            await iosChannel.invokeMethod<bool>('updateLockList', packages);
            AppLogger.info('$action (bg): Synced to iOS native');
          } catch (iosErr) {
            AppLogger.error('$action (bg): iOS sync error: $iosErr');
          }
        }
      } else {
        AppLogger.error(
          '$action (bg): API failed: ${response.message}',
        );
      }
    } catch (e) {
      AppLogger.error('$action background sync error: $e');
    }
  }

  if (message.data['type'] == 'FORCE_REFRESH_DATA') {
    AppLogger.info('Received FORCE_REFRESH_DATA command via FCM (background)');
    try {
      await SharedPrefsService.init();
      final prefs = SharedPrefsService();
      final childId = prefs.getString('child_id');

      if (childId == null || childId.isEmpty) {
        AppLogger.warning('FORCE_REFRESH_DATA (bg): No child_id found');
        return;
      }

      // Initialize minimal dependencies for API calls
      if (!injector.isRegistered<SharedPrefsService>()) {
        await initializeDependencies();
      }

      await _performForceRefresh(
        childId,
        geofenceProbe: message.data['purpose'] == 'GEOFENCE_VERIFY',
      );
      AppLogger.info('FORCE_REFRESH_DATA (bg): Sync completed successfully');
    } catch (e) {
      AppLogger.error('FORCE_REFRESH_DATA background error: $e');
    }
  }

  // Handle WEB_FILTER_UPDATE in background
  if (message.data['type'] == 'WEB_FILTER_UPDATE') {
    AppLogger.info('Received WEB_FILTER_UPDATE command via FCM (background)');
    try {
      final enabledStr = message.data['enabled']?.toString();
      final enabled = enabledStr == 'true';

      await SharedPrefsService.init();
      final prefs = SharedPrefsService();
      await prefs.setBool('block_18plus', enabled);

      AppLogger.info('WEB_FILTER_UPDATE (bg): Updated block_18plus to $enabled');

      // Android's enforcement (AppLockService) polls the SharedPreferences value
      // above directly, so it's already live. iOS's enforcement (ManagedSettings)
      // requires an explicit native call — without this, toggling the setting
      // for an already-logged-in child never actually changed the filter on iOS.
      if (Platform.isIOS) {
        try {
          const iosChannel = MethodChannel('com.truenyx.naviq/parental_control');
          await iosChannel.invokeMethod('setWebFiltering', enabled);
          AppLogger.info('WEB_FILTER_UPDATE (bg): Synced to iOS native');
        } catch (iosErr) {
          AppLogger.error('WEB_FILTER_UPDATE (bg): iOS sync error: $iosErr');
        }
      }
    } catch (e) {
      AppLogger.error('WEB_FILTER_UPDATE background error: $e');
    }
  }

  // Handle DELETION_RESTRICTION_UPDATE in background
  if (message.data['type'] == 'DELETION_RESTRICTION_UPDATE') {
    AppLogger.info('Received DELETION_RESTRICTION_UPDATE command via FCM (background)');
    try {
      final isAllowDeleteStr = message.data['isallowdelete']?.toString();
      final isAllowDelete = isAllowDeleteStr == 'true';

      await SharedPrefsService.init();
      final prefs = SharedPrefsService();
      // AppLockService.kt polls 'flutter.is_allow_delete' directly, so this
      // alone makes the change live for an already-running child device.
      await prefs.setAllowDelete(isAllowDelete);

      AppLogger.info(
        'DELETION_RESTRICTION_UPDATE (bg): Updated is_allow_delete to $isAllowDelete',
      );
    } catch (e) {
      AppLogger.error('DELETION_RESTRICTION_UPDATE background error: $e');
    }
  }
}

/// Helper function to perform the actual data refresh and upload.
/// This is used by both foreground and background handlers.
Future<void> _performForceRefresh(
  String childId, {
  bool geofenceProbe = false,
}) async {
  try {
    AppLogger.info(
      '🚀 Executing FORCE_REFRESH_DATA for $childId'
      '${geofenceProbe ? " (geofence verification probe)" : ""}',
    );

    // 1. Get a fresh location and POST IT FIRST. Everything else in this
    // refresh (device status, OEM telemetry, screen time) can take many
    // seconds; the server may be holding a possible geofence ENTRY/EXIT that
    // only this fix can confirm or cancel, so it must not wait behind them.
    // Uses the fix's own timestamp (never "now" — a cached OS fix relabelled
    // fresh would count as fresh evidence) and no client-side reverse
    // geocoding (the server resolves addresses itself).
    final childRepo = injector<ChildRepo>();
    final fixCount = geofenceProbe ? 2 : 1;
    for (var i = 0; i < fixCount; i++) {
      if (i > 0) await Future.delayed(const Duration(seconds: 12));
      try {
        final fix = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        final locationResponse = await childRepo.postChildLocation({
          'child_id': childId,
          'lat': fix.latitude,
          'lng': fix.longitude,
          'accuracy_m': fix.accuracy,
          'speed_mps': fix.speed < 0 ? 0.0 : fix.speed,
          'bearing': fix.heading < 0 ? 0.0 : fix.heading,
          'timestamp': fix.timestamp.toUtc().toIso8601String(),
          // Engineering diagnostics only.
          'platform': Platform.isIOS ? 'ios' : 'android',
          'tracking_profile': geofenceProbe ? 'probe' : 'force_refresh',
          'fix_source': geofenceProbe ? 'geofence_probe' : 'force_refresh',
        });
        AppLogger.info(
          locationResponse.isSuccess
              ? '✅ Force Refresh: Location synced (acc ${fix.accuracy.toStringAsFixed(0)}m)'
              : '❌ Force Refresh: Location failed: ${locationResponse.message}',
        );
      } catch (e) {
        AppLogger.error('Force Refresh: Failed to get/post location: $e');
      }
    }

    // A probe means "evidence needed now": also boost the always-on tracking
    // service (separate isolate) so points keep flowing at high accuracy for
    // the next few minutes, then it returns to normal low-power by itself.
    if (geofenceProbe) {
      try {
        FlutterBackgroundService().invoke('boost', {
          'seconds': GeofenceTrackingConfig.boostDuration.inSeconds,
        });
      } catch (e) {
        AppLogger.error('Force Refresh: could not boost tracking service: $e');
      }
    }

    // 2. Get Device Status
    final childInfoService = injector<ChildInfoService>();
    final deviceInfo = await childInfoService.getDeviceInfo();

    // 3. Post Device Status
    final statusData = {
      'child_id': childId,
      'battery_percentage': deviceInfo.batteryPercentage,
      'network_status': deviceInfo.networkStatus,
      'network_type': deviceInfo.networkType,
      'sound_profile': deviceInfo.soundProfile,
      'is_online': deviceInfo.isOnline,
      'is_charging': deviceInfo.isCharging,
      'last_update': deviceInfo.onlineSince,
      'gps_enabled': deviceInfo.gpsEnabled,
      'location_permission': deviceInfo.locationPermissionStatus,
    };

    // manufacturer/oem_onboarding_status used to only sync from the OEM
    // onboarding screen itself (OemBatteryHelper.syncOnboardingStatusToBackend)
    // — a device that never opens that screen again (fresh reinstall, or the
    // onboarding step was already acknowledged before) never reports it again,
    // leaving this triage telemetry permanently empty server-side for exactly
    // the incidents it exists to help diagnose. FORCE_REFRESH_DATA already
    // fires far more often (every parent-triggered refresh, foreground and
    // background) than the onboarding screen is ever revisited, so piggyback
    // it here instead of adding a new periodic timer.
    if (Platform.isAndroid) {
      try {
        final oemHelper = OemBatteryHelper();
        final manufacturer = await oemHelper.getRawManufacturer();
        final oemStatus = await oemHelper.getOnboardingStatus();
        if (manufacturer != null) statusData['manufacturer'] = manufacturer;
        statusData['oem_onboarding_status'] = oemStatus;
      } catch (e) {
        AppLogger.error('Force Refresh: OEM telemetry lookup failed: $e');
      }
    }

    // Same "piggyback on the already-frequent force-refresh" reasoning as
    // the OEM telemetry above — see LocationService.getBackgroundLocationStatus
    // for why this is checked separately from location_permission above.
    try {
      statusData['background_location_permission'] =
          await LocationService().getBackgroundLocationStatus();
    } catch (e) {
      AppLogger.error('Force Refresh: background location status lookup failed: $e');
    }

    final statusResponse = await childRepo.postChildData(statusData);
    if (statusResponse.isSuccess) {
      AppLogger.info('✅ Force Refresh: Device status synced');
    } else {
      AppLogger.error(
        '❌ Force Refresh: Device status failed: ${statusResponse.message}',
      );
    }

    // 5. Post Screen Time
    try {
      if (!injector.isRegistered<ScreenTimeSyncService>()) {
         AppLogger.warning('Force Refresh: ScreenTimeSyncService not registered in injector yet');
      } else {
         final screenTimeService = injector<ScreenTimeSyncService>();
         await screenTimeService.syncScreenTime();
         AppLogger.info('✅ Force Refresh: Screen time synced');
      }
    } catch (e) {
      AppLogger.error('❌ Force Refresh: Screen time sync failed: $e');
    }

    AppLogger.info('🚀 FORCE_REFRESH_DATA: Sync operation finished');
  } catch (e) {
    AppLogger.error('Error during _performForceRefresh: $e');
    rethrow;
  }
}

class FirebaseNotificationService {
  static final FirebaseNotificationService _instance =
      FirebaseNotificationService._internal();

  factory FirebaseNotificationService() {
    return _instance;
  }

  FirebaseNotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final StreamController<RemoteMessage> _messageController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _notificationTapController =
      StreamController<RemoteMessage>.broadcast();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'naviq_notifications',
    'NaviQ Notifications',
    description: 'Notifications from NaviQ',
    importance: Importance.max,
  );

  Stream<RemoteMessage> get messageStream => _messageController.stream;
  Stream<RemoteMessage> get notificationTapStream =>
      _notificationTapController.stream;

  RemoteMessage? _pendingLocationShareRequest;
  RemoteMessage? get pendingLocationShareRequest => _pendingLocationShareRequest;

  // Parent "approve / deny" prompts (child asks for logout / more time) whose
  // notification was tapped before HomePage was listening — a cold start emits
  // the tap on a broadcast stream nobody has subscribed to yet, so it was lost
  // and the app just opened on Home with no sheet. HomePage takes it on start /
  // resume.
  RemoteMessage? _pendingActionTap;

  RemoteMessage? takePendingActionTap() {
    final m = _pendingActionTap;
    _pendingActionTap = null;
    return m;
  }

  void clearPendingLocationShareRequest() {
    _pendingLocationShareRequest = null;
    AppLogger.info('Cleared pending location share request');
  }

  GlobalKey<NavigatorState>? _navigatorKey;
  void setNavigatorKey(GlobalKey<NavigatorState> key) => _navigatorKey = key;

  /// Opens the child a tapped push belongs to (select it, refresh its data,
  /// show Home). Selection is the app's existing one: the `child_id` pref via
  /// SharedPrefsService.switchChild + a HomepageBloc reload.
  late final ChildNotificationRouter childRouter =
      ChildNotificationRouter.withPrefs(
        prefs: injector<SharedPrefsService>(),
        reloadHome: () => injector<HomepageBloc>().add(GetHomepageData()),
        // Drop pushed screens (trip detail, sheets, ...) that still show the
        // previously selected child. Home is the root route; on a cold start
        // the navigator does not exist yet and Home is built after the
        // selection.
        showHome: (_) =>
            _navigatorKey?.currentState?.popUntil((r) => r.isFirst),
        refreshAccessibleChildIds: _refreshAccessibleChildIds,
        onInaccessible: (_) => _showRouteError(
          'That notification is for a child you can no longer access.',
        ),
        onFailure: (_, _) => _showRouteError(
          'Could not open that notification. Please pick the child manually.',
        ),
      );

  void _showRouteError(String message) {
    final context = _navigatorKey?.currentContext;
    if (context != null) AppSnackbar.showError(context, message);
  }

  Future<List<String>> _refreshAccessibleChildIds() async {
    final prefs = injector<SharedPrefsService>();
    try {
      final response = await injector<HomeRepository>().getChildrenProfiles();
      if (response.isSuccess && response.data != null) {
        final existing = prefs.getChildren();
        final parentToken = prefs.getAuthToken() ?? '';
        final fresh = response.data!.map((json) {
          final child = ChildProfile.fromMap(json as Map<String, dynamic>);
          final known = existing.where((c) => c.childId == child.childId);
          return child.copyWith(
            authToken: known.isNotEmpty ? known.first.authToken : parentToken,
          );
        }).toList();
        await prefs.saveChildren(fresh);
        return fresh.map((c) => c.childId).toList();
      }
    } catch (e) {
      AppLogger.warning('Could not refresh children for notification tap: $e');
    }
    return prefs.getChildren().map((c) => c.childId).toList();
  }

  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  /// Initialize Firebase Messaging
  Future<void> initialize() async {
    try {
      // Request notification permissions
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      AppLogger.info(
        'User granted permission: ${settings.authorizationStatus}',
      );

      // Initialize local notifications
      await _initLocalNotifications();

      // Get FCM token
      await _getFCMToken();

      // Listen for token refresh and re-register with server
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        AppLogger.info('FCM Token refreshed: $newToken');
        // CSV gets only a redacted marker, not the full token — the log
        // file can end up shared via WhatsApp/email for diagnosis.
        StructuredLogger.log(
          LogTag.FCM,
          'Token refreshed (…${newToken.length > 6 ? newToken.substring(newToken.length - 6) : newToken})',
        );
        // Re-register the new token with server
        registerTokenWithServer();
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps when app is in background or terminated
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check if app was opened from a notification (terminated state)
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      AppLogger.info('Firebase Notification Service initialized successfully');
    } catch (e) {
      AppLogger.error('Error initializing Firebase Notification Service: $e');
    }
  }

  /// Initialize flutter_local_notifications
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        AppLogger.info('Local notification tapped: ${response.payload}');
        final message = messageFromLocalPayload(response.payload);
        if (message != null) _handleNotificationTap(message);
      },
    );

    // A local notification (shown for a foreground push) tapped after the app
    // was killed launches the app without calling the callback above.
    try {
      final launch = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final message = messageFromLocalPayload(
          launch?.notificationResponse?.payload,
        );
        if (message != null) _handleNotificationTap(message);
      }
    } catch (e) {
      // Must not abort the rest of initialize() (token, FCM listeners).
      AppLogger.warning('Could not read notification launch details: $e');
    }

    // Create the Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  /// Get FCM token
  Future<String?> _getFCMToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      AppLogger.info('FCM Token: $_fcmToken');
      return _fcmToken;
    } catch (e) {
      AppLogger.error('Error getting FCM token: $e');
      return null;
    }
  }

  /// Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    AppLogger.info('Foreground message received: ${message.messageId}');
    AppLogger.info('Message data: ${message.data}');
    AppLogger.info('Message notification: ${message.notification?.title}');

    // Log to CSV for offline analysis — type/title only, not the full data
    // payload (may carry place names / other identifying details).
    StructuredLogger.log(
      LogTag.FCM,
      'FG message received: type=${message.data['type']} title=${message.notification?.title}',
    );

    // Save to SharedPreferences for parent app
    final parsed = parseNotificationContent(message);
    if (parsed['type'] != 'SYNC_SCREEN_TIME' && parsed['type'] != 'SYNC_LOCKED_APPS') {
      try {
        final prefs = SharedPrefsService();
        if (prefs.isParent) {
          await prefs.addNotification({
            'id': message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
            'title': parsed['title'],
            'body': parsed['body'],
            'timestamp': _eventTimestampOrNow(message),
            'type': parsed['type'],
            'isRead': false,
          });
          AppLogger.info('Saved foreground notification locally');

          // Save pending request to local SharedPrefs
          if (message.data['type'] == 'location_share_request') {
            await prefs.setString('pending_location_share_request', json.encode(message.data));
            AppLogger.info('Saved pending location share request from foreground to SharedPrefs');
          }
        }
      } catch (e) {
        AppLogger.error('Failed to save foreground notification: $e');
      }
    }

    // Add to stream for listeners
    _messageController.add(message);

    // Handle SYNC_LOCKED_APPS in foreground — dispatch to AppLockBloc
    if (message.data['type'] == 'SYNC_LOCKED_APPS') {
      try {
        final appLockBloc = injector<AppLockBloc>();
        appLockBloc.add(SyncLockedAppsFromServer());
        AppLogger.info('SYNC_LOCKED_APPS: Dispatched to AppLockBloc');
      } catch (e) {
        AppLogger.error('SYNC_LOCKED_APPS foreground error: $e');
      }
      return; // Don't show notification
    }

    // Handle FORCE_REFRESH_DATA in foreground
    if (message.data['type'] == 'FORCE_REFRESH_DATA') {
      try {
        final prefs = injector<SharedPrefsService>();
        final childId = prefs.getString('child_id');
        if (childId != null && childId.isNotEmpty) {
          await _performForceRefresh(
            childId,
            geofenceProbe: message.data['purpose'] == 'GEOFENCE_VERIFY',
          );
          AppLogger.info('FORCE_REFRESH_DATA (fg): Sync triggered');
        }
      } catch (e) {
        AppLogger.error('FORCE_REFRESH_DATA foreground error: $e');
      }
      return; // Don't show notification
    }

    // Handle WEB_FILTER_UPDATE in foreground
    if (message.data['type'] == 'WEB_FILTER_UPDATE') {
      try {
        final enabledStr = message.data['enabled']?.toString();
        final enabled = enabledStr == 'true';

        final prefs = injector<SharedPrefsService>();
        await prefs.setBool('block_18plus', enabled);
        AppLogger.info('WEB_FILTER_UPDATE (fg): Updated block_18plus to $enabled');

        // Android's enforcement (AppLockService) polls the SharedPreferences
        // value above directly. iOS's ManagedSettings-based filter needs this
        // explicit native call — without it, toggling the setting while the
        // child app is already running never actually changed the filter.
        await injector<DeviceInfoService>().setWebFiltering(enabled);
      } catch (e) {
        AppLogger.error('WEB_FILTER_UPDATE foreground error: $e');
      }
      return; // Don't show notification
    }

    // Handle DELETION_RESTRICTION_UPDATE in foreground
    if (message.data['type'] == 'DELETION_RESTRICTION_UPDATE') {
      try {
        final isAllowDeleteStr = message.data['isallowdelete']?.toString();
        final isAllowDelete = isAllowDeleteStr == 'true';

        final prefs = injector<SharedPrefsService>();
        // AppLockService.kt polls 'flutter.is_allow_delete' directly, so this
        // alone makes the change live for an already-running child device.
        await prefs.setAllowDelete(isAllowDelete);
        AppLogger.info(
          'DELETION_RESTRICTION_UPDATE (fg): Updated is_allow_delete to $isAllowDelete',
        );
      } catch (e) {
        AppLogger.error('DELETION_RESTRICTION_UPDATE foreground error: $e');
      }
      return; // Don't show notification
    }

    // Show local notification for foreground messages
    _showLocalNotification(message);
  }

  /// Use the real-world event time (sent by the backend for geofence alerts,
  /// e.g. see fcm.util.js sendGeofenceAlert) when available, instead of
  /// stamping the notification with the moment this device happened to
  /// process the FCM message. Those can differ significantly if the device
  /// was backgrounded/restricted and only processed the message late — which
  /// otherwise made every notification misleadingly show "Just now" even
  /// when the underlying event happened much earlier.
  static String _eventTimestampOrNow(RemoteMessage message) {
    final raw = message.data['event_timestamp'];
    if (raw != null) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toIso8601String();
    }
    return DateTime.now().toIso8601String();
  }

  static Map<String, String> parseNotificationContent(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String? ?? 'GENERAL';
    final notification = message.notification;

    // Diagnostic logging for parent app fcm
    AppLogger.info('🔥 [FCM DEBUG] type="$type", data=$data, notificationTitle="${notification?.title}", notificationBody="${notification?.body}"');

    String title = notification?.title ?? '';
    String body = notification?.body ?? '';

    // Build title/body from data payload if notification payload is empty or has missing fields
    if (notification == null || title.trim().isEmpty || body.trim().isEmpty) {
      final childName = data['child_name'] ?? 'Child';
      final requesterName = data['requester_name'] ?? 'Someone';
      final normalizedType = type.trim().toLowerCase();

      switch (normalizedType) {
        case 'location_share_request':
          title = '📍 Location Share Request';
          body = '$requesterName is requesting for your kids location';
          break;
        case 'location_share_accepted':
          title = '✅ Location Share Accepted';
          body = 'Location sharing started for $childName';
          break;
        case 'sos':
          title = '🚨 SOS from $childName!';
          body = 'Emergency alert received. Tap to view location.';
          break;
        case 'safe_place_arrival':
          title = '$childName arrived safely';
          body = 'Arrived at ${data['place_name'] ?? 'safe place'}';
          break;
        case 'safe_place_departure':
          title = '$childName left ${data['place_name'] ?? 'safe place'}';
          body = 'Departed from ${data['place_name'] ?? 'safe place'}';
          break;
        case 'trip_started':
          title = '$childName is on the move';
          body = 'Started from ${data['start_place'] ?? 'unknown'}';
          break;
        case 'trip_ended':
          title = '$childName\'s trip ended';
          body = data['from_place'] != null && data['to_place'] != null
              ? '${data['from_place']} → ${data['to_place']} (${data['distance_km'] ?? '?'} km)'
              : 'Trip completed';
          break;
        case 'low_battery':
          title = '$childName\'s device battery low';
          body = 'Battery at ${data['battery_percentage'] ?? '?'}%';
          break;
        case 'device_offline':
          title = '$childName\'s device is offline';
          body = 'Device went offline. Last seen recently.';
          break;
        case 'chat_message':
          title = data['sender_name'] ?? 'New Message';
          body = data['text'] ?? 'Tap to view';
          break;
        case 'sync_screen_time':
        case 'sync_locked_apps':
          title = '';
          body = '';
          break;
        case 'time_extension_request':
          final requesterChildName = data['child_name'] ?? childName;
          title = '$requesterChildName is asking for more time';
          body = '$requesterChildName wants more time on ${data['app_name'] ?? 'an app'}. Tap to review.';
          break;
        case 'time_extension_result':
          final approved = data['approved'] == 'true';
          title = approved ? 'More time granted!' : 'Request denied';
          body = approved
              ? 'You have more time for ${data['app_name'] ?? 'the app'}.'
              : 'Your parent said no to more time for ${data['app_name'] ?? 'the app'}.';
          break;
        default:
          title = 'NaviQ';
          body = 'You have a new notification';
      }
    }

    if (title.isEmpty) title = 'NaviQ';
    if (body.isEmpty) body = 'You have a new notification';

    return {
      'title': title,
      'body': body,
      'type': type,
    };
  }

  /// Payload of the local notification shown for a foreground push: the whole
  /// data map (so `child_id` survives) with the resolved type.
  @visibleForTesting
  static String localPayload(Map<String, dynamic> data, String type) =>
      json.encode({...data, 'type': type});

  /// Inverse of [localPayload]; null when the payload is absent or not JSON.
  @visibleForTesting
  static RemoteMessage? messageFromLocalPayload(String? payload) {
    if (payload == null) return null;
    try {
      final decoded = json.decode(payload) as Map<String, dynamic>;
      return RemoteMessage(
        data: decoded.map((key, value) => MapEntry(key, value.toString())),
      );
    } catch (e) {
      AppLogger.warning('Payload was not JSON, treating as raw: $e');
      return null;
    }
  }

  /// Show a local notification based on FCM message data
  void _showLocalNotification(RemoteMessage message) {
    final parsed = parseNotificationContent(message);
    final title = parsed['title']!;
    final body = parsed['body']!;
    final type = parsed['type']!;

    if (type == 'SYNC_SCREEN_TIME' || type == 'SYNC_LOCKED_APPS') {
      return; // Silent
    }

    _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: type == 'SOS' ? Importance.max : Importance.high,
          priority: type == 'SOS' ? Priority.max : Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: localPayload(message.data, type),
    );
  }

  /// A visible push received while the app was backgrounded / killed never
  /// reaches the Dart handlers, so it is missing from the in-app Notifications
  /// list. Add it when the user taps it (once per message id).
  Future<void> _saveTappedNotification(RemoteMessage message) async {
    try {
      final prefs = SharedPrefsService();
      if (!prefs.isParent) return;
      final parsed = parseNotificationContent(message);
      if (parsed['type'] == 'SYNC_SCREEN_TIME' || parsed['type'] == 'SYNC_LOCKED_APPS') return;
      final id = message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
      if (prefs.getNotifications().any((n) => n['id'] == id)) return;
      await prefs.addNotification({
        'id': id,
        'title': parsed['title'],
        'body': parsed['body'],
        'timestamp': _eventTimestampOrNow(message),
        'type': parsed['type'],
        'isRead': false,
      });
    } catch (e) {
      AppLogger.error('Failed to save tapped notification: $e');
    }
  }

  /// Handle notification tap (when app is in background or terminated)
  void _handleNotificationTap(RemoteMessage message) {
    AppLogger.info('Notification tapped: ${message.messageId}');
    AppLogger.info('Notification data: ${message.data}');

    // Log to CSV — type only, not the full data payload.
    StructuredLogger.log(
      LogTag.FCM,
      'Notification tapped: type=${message.data['type']} id=${message.messageId}',
    );

    if (message.data['type'] == 'location_share_request') {
      _pendingLocationShareRequest = message;
      try {
        final prefs = injector<SharedPrefsService>();
        prefs.setString('pending_location_share_request', json.encode(message.data));
      } catch (e) {
        AppLogger.error('Failed to save tapped request to SharedPrefs: $e');
      }
    }

    final tapType = message.data['type'];
    if (tapType == 'LOGOUT_REQUEST' || tapType == 'TIME_EXTENSION_REQUEST') {
      _pendingActionTap = message;
    }
    _saveTappedNotification(message);

    // Child-specific events: open the child the push is for, not whichever
    // child happens to be selected.
    try {
      unawaited(
        childRouter
            .handleTap(message.data, messageId: message.messageId)
            .catchError((Object e) {
              AppLogger.error('Child notification routing failed: $e');
              return ChildRouteOutcome.failed;
            }),
      );
    } catch (e) {
      // Must never block the existing tap handling below.
      AppLogger.error('Child notification routing failed: $e');
    }

    // Add to stream for navigation or other actions
    _notificationTapController.add(message);

    // Automatic navigation for CHAT_MESSAGE
    if (message.data['type'] == 'CHAT_MESSAGE' && _navigatorKey?.currentState != null) {
      final chatId = message.data['chat_id'];
      final senderId = message.data['sender_id'];
      final senderName = message.data['sender_name'] ?? 'Support';

      if (senderId != null) {
        _navigatorKey!.currentState!.push(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: injector<ChatBloc>(),
              child: ChatScreen(
                chatId: chatId,
                recipientId: senderId,
                recipientName: senderName,
              ),
            ),
          ),
        );
      }
    }
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      AppLogger.info('Subscribed to topic: $topic');
    } catch (e) {
      AppLogger.error('Error subscribing to topic $topic: $e');
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      AppLogger.info('Unsubscribed from topic: $topic');
    } catch (e) {
      AppLogger.error('Error unsubscribing from topic $topic: $e');
    }
  }

  /// Delete FCM token
  Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      _fcmToken = null;
      AppLogger.info('FCM token deleted');
    } catch (e) {
      AppLogger.error('Error deleting FCM token: $e');
    }
  }

  /// Register FCM token with the backend server.
  /// Determines whether user is parent or child from SharedPrefs.
  Future<void> registerTokenWithServer() async {
    if (_fcmToken == null || _fcmToken!.isEmpty) {
      AppLogger.warning('FCM token is null, cannot register with server');
      return;
    }

    try {
      final prefs = injector<SharedPrefsService>();
      final parentId = prefs.getString('parent_id');
      final childId = prefs.getString('child_id');

      // Parent flow: has parent_id and NO child_id (or child_id is from parent's selected child)
      if (parentId != null && parentId.isNotEmpty) {
        // Check if this is a parent user (not a child device)
        // A child device will have child_id but NO parent_id
        final authRepo = injector<AuthRepository>();
        final response = await authRepo.registerParentFcmToken(_fcmToken!);
        if (response.isSuccess) {
          AppLogger.info('Parent FCM token registered with server');
        } else {
          AppLogger.error(
            'Failed to register parent FCM token: ${response.message}',
          );
        }
      } else if (childId != null && childId.isNotEmpty) {
        // Child flow
        final childRepo = injector<ChildRepo>();
        final response = await childRepo.registerChildFcmToken(
          childId: childId,
          fcmToken: _fcmToken!,
        );
        if (response.isSuccess) {
          AppLogger.info('Child FCM token registered with server');
        } else {
          AppLogger.error(
            'Failed to register child FCM token: ${response.message}',
          );
        }
      } else {
        AppLogger.warning(
          'No parent_id or child_id found, skipping FCM token registration',
        );
      }
    } catch (e) {
      AppLogger.error('Error registering FCM token with server: $e');
    }
  }

  /// Remove FCM token from server (call before logout)
  Future<void> removeTokenFromServer() async {
    try {
      final prefs = injector<SharedPrefsService>();
      final parentId = prefs.getString('parent_id');
      final childId = prefs.getString('child_id');

      final token = _fcmToken ?? await _firebaseMessaging.getToken();
      if (token == null || token.isEmpty) {
        AppLogger.warning('FCM token is null, cannot remove from server');
        return;
      }

      if (parentId != null && parentId.isNotEmpty) {
        final authRepo = injector<AuthRepository>();
        final response = await authRepo.removeParentFcmToken(token);
        if (response.isSuccess) {
          AppLogger.info('Parent FCM token removed from server');
        } else {
          AppLogger.error(
            'Failed to remove parent FCM token: ${response.message}',
          );
        }
      } else if (childId != null && childId.isNotEmpty) {
        final childRepo = injector<ChildRepo>();
        final response = await childRepo.removeChildFcmToken(
          childId: childId,
          fcmToken: token,
        );
        if (response.isSuccess) {
          AppLogger.info('Child FCM token removed from server');
        } else {
          AppLogger.error(
            'Failed to remove child FCM token: ${response.message}',
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error removing FCM token from server: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _messageController.close();
    _notificationTapController.close();
  }
}
