import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:child_track/app/childapp/view_model/repository/child_location_repo.dart';
import 'package:child_track/core/services/csv_file_logger.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/services/connectivity/bloc/connectivity_bloc.dart';
import 'package:child_track/core/utils/structured_logger.dart';
import 'package:child_track/core/services/location_state_machine.dart';
import 'package:child_track/core/services/tracking/tracking_profile_manager.dart';
import 'package:child_track/core/services/tracking/tracking_config_service.dart';
import 'package:child_track/core/services/tracking/geofence_tracking_config.dart';
import 'package:child_track/core/services/tracking/tracking_recovery_policy.dart';
import 'package:child_track/core/utils/location_payload.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;

class BackgroundLocationService {
  static final BackgroundLocationService _instance =
      BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  /// Android-only: arms/disarms the native FusedLocationProviderClient
  /// background ping (NativeLocationPingManager.kt) + its WorkManager
  /// watchdog, so there's still a baseline location signal reaching the
  /// server if this foreground service itself gets killed (force-kill,
  /// aggressive OEM battery management). No-op on iOS, which already has its
  /// own always-on CLLocationManager background updates (AppDelegate.swift).
  static const MethodChannel _backgroundLocationChannel = MethodChannel(
    'com.truenyx.naviq/background_location',
  );

  /// Initialize the background service
  Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'child_track_location',
      'Location Tracking',
      description: 'Tracking your location in background',
      importance: Importance.low,
      showBadge: false,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'child_track_location',
        initialNotificationTitle: 'Location Tracking',
        initialNotificationContent: 'Tracking Active',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  Future<void> start() async {
    try {
      final service = FlutterBackgroundService();
      final running = await service.isRunning();
      if (!running) {
        StructuredLogger.log(LogTag.BG, 'Starting service manually');
        await service.startService();
      } else {
        StructuredLogger.log(
          LogTag.BG,
          'Service already running, skipping start',
        );
      }
    } catch (e) {
      StructuredLogger.log(LogTag.BG, 'Failed to start service', error: e);
    }

    if (Platform.isAndroid) {
      try {
        await _backgroundLocationChannel.invokeMethod('start');
        StructuredLogger.log(
          LogTag.BG,
          'Native background location ping armed',
        );
      } catch (e) {
        StructuredLogger.log(
          LogTag.BG,
          'Failed to arm native background location ping',
          error: e,
        );
      }
    }
  }

  Future<void> stop() async {
    try {
      final service = FlutterBackgroundService();
      StructuredLogger.log(LogTag.BG, 'Stopping service manually');
      service.invoke('stop');
    } catch (e) {
      StructuredLogger.log(LogTag.BG, 'Failed to stop service', error: e);
    }

    if (Platform.isAndroid) {
      try {
        await _backgroundLocationChannel.invokeMethod('stop');
        StructuredLogger.log(
          LogTag.BG,
          'Native background location ping disarmed',
        );
      } catch (e) {
        StructuredLogger.log(
          LogTag.BG,
          'Failed to disarm native background location ping',
          error: e,
        );
      }
    }
  }

  Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  static DateTime? _lastRecoveryAttempt;

  @visibleForTesting
  static void resetRecoveryThrottleForTests() => _lastRecoveryAttempt = null;

  /// Restart the high-accuracy foreground service if it is not running, from a
  /// context Android allows it (a high-priority FCM message is a documented
  /// foreground-service-start exemption). Safe to call repeatedly: the policy
  /// refuses when the device is not a logged-in child, location permission is
  /// missing, the service already runs, or an attempt was made moments ago.
  /// Never throws; the native fallback ping is left untouched either way.
  /// Returns the decision so callers/tests can see why nothing happened.
  static Future<RecoveryDecision> recoverIfStopped({
    required String reason,
    @visibleForTesting TrackingRecoveryProbe? probe,
  }) async {
    final p = probe ?? TrackingRecoveryProbe.real();
    try {
      final now = DateTime.now();
      final decision = TrackingRecoveryPolicy.decide(
        isAndroid: p.isAndroid,
        isChildDevice: await p.isChildDevice(),
        hasLocationPermission: await p.hasLocationPermission(),
        hasBackgroundLocation: await p.hasBackgroundLocation(),
        serviceRunning: await p.serviceRunning(),
        sinceLastAttempt: _lastRecoveryAttempt == null
            ? null
            : now.difference(_lastRecoveryAttempt!),
      );
      if (decision != RecoveryDecision.start) {
        StructuredLogger.log(
          LogTag.BG,
          'Tracking recovery ($reason): skipped → ${decision.name}',
        );
        return decision;
      }
      _lastRecoveryAttempt = now;
      try {
        await p.startService();
        StructuredLogger.log(
          LogTag.BG,
          'Tracking recovery ($reason): foreground service start requested',
        );
        return RecoveryDecision.start;
      } catch (e) {
        StructuredLogger.log(
          LogTag.BG,
          'Tracking recovery ($reason): start failed',
          error: e,
        );
        return RecoveryDecision.startFailed;
      }
    } catch (e) {
      StructuredLogger.log(
        LogTag.BG,
        'Tracking recovery ($reason): check failed',
        error: e,
      );
      return RecoveryDecision.startFailed;
    }
  }
}

// ── Global stream state ──────────────────────────────────────────────────────

StreamSubscription<Position>? _positionSubscription;
StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
LocationStateMachine? _stateMachine;

/// Adaptive tracking profile manager (shared between stream restarts).
final _profileManager = TrackingProfileManager();

bool _resubscribeScheduled = false;
ServiceStatus? _lastServiceStatus;

/// Mirrors ChildInfoService/DeviceInfoService's mapping so the string values
/// posted to the backend stay consistent regardless of which code path
/// reported them.
Future<String> _getLocationPermissionStatus() async {
  try {
    final permissionStatus = await Permission.locationAlways.status;
    if (permissionStatus.isGranted) return 'granted';
    if (permissionStatus.isDenied) return 'denied';
    if (permissionStatus.isPermanentlyDenied) return 'denied_forever';
    final inUseStatus = await Permission.locationWhenInUse.status;
    if (inUseStatus.isGranted) return 'while_using';
    return permissionStatus.name;
  } catch (e) {
    StructuredLogger.log(LogTag.BG, 'Permission status check failed', error: e);
    return 'unknown';
  }
}

Timer? _boostTimer;
Timer? _aliveTimer;

/// Epoch-ms heartbeat of this isolate (key shared with TrackingRecovery.kt).
void _writeAliveMarker(SharedPrefsService prefs) {
  prefs.setInt(
    TrackingRecoveryPolicy.aliveMarkerKey,
    DateTime.now().millisecondsSinceEpoch,
  );
}

/// Start/extend a time-boxed boost and make sure the stream actually ends it
/// even if no further position arrives (e.g. the device goes still).
void _applyBoost(ServiceInstance service, Duration duration) {
  final newlyActive = _profileManager.startBoost(duration);
  _boostTimer?.cancel();
  _boostTimer = Timer(duration + const Duration(seconds: 1), () {
    if (_profileManager.expireBoostIfDue()) {
      StructuredLogger.log(LogTag.BG, 'Boost expired → restarting stream');
      _startLocationStream(service);
    }
  });
  if (newlyActive) {
    StructuredLogger.log(
      LogTag.BG,
      'Boost started (${duration.inSeconds}s) → restarting stream',
    );
    _startLocationStream(service);
  }
}

/// Restart the location stream whenever the profile changes.
void _startLocationStream(ServiceInstance service) {
  _positionSubscription?.cancel();

  final LocationSettings settings;
  if (Platform.isAndroid) {
    settings = _profileManager.buildAndroidSettings();
  } else if (Platform.isIOS) {
    settings = _profileManager.buildAppleSettings();
  } else {
    settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _profileManager.currentConfig.distanceFilter,
    );
  }

  StructuredLogger.log(
    LogTag.BG,
    'Starting stream • profile=${_profileManager.currentProfile.name} '
    '• interval=${_profileManager.currentConfig.interval.inSeconds}s '
    '• filter=${_profileManager.currentConfig.distanceFilter}m',
  );

  _positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
    (Position position) {
      _stateMachine?.processLocation(position);

      // Dynamically adapt tracking profile based on speed
      final changed = _profileManager.updateFromSpeed(
        position.speed < 0 ? 0 : position.speed,
      );
      // Geofence-aware: near a saved place the low-power `still` profile is
      // upgraded to precise fixes (see GeofenceTrackingConfig); a finished
      // boost is dropped here too.
      final nearChanged = _profileManager.setNearFence(
        _stateMachine?.updateNearFence(position) ?? false,
      );
      final boostEnded = _profileManager.expireBoostIfDue();
      if (changed || nearChanged || boostEnded) {
        StructuredLogger.log(
          LogTag.BG,
          'Tracking settings changed → ${_profileManager.effectiveProfileLabel}'
          '${changed ? " (profile)" : ""}${nearChanged ? " (near-fence)" : ""}'
          '${boostEnded ? " (boost ended)" : ""}. Restarting stream.',
        );
        // Restart stream with new settings
        _startLocationStream(service);
      }

      // Update notification
      if (service is AndroidServiceInstance) {
        final sm = _stateMachine;
        String content;
        if (sm != null && sm.isTripTracking) {
          final mode = sm.tripMode == BgTripMode.walking
              ? 'Walking'
              : 'Vehicle';
          // Use the last distance-filter-accepted speed, not this raw
          // per-callback reading — a filtered/rejected point (e.g. a GPS
          // glitch under 5m of real displacement) could otherwise still
          // show an implausible speed in this visible banner even though
          // it never actually fed into trip/location processing.
          final displaySpeed = sm.lastAcceptedPosition?.speed ?? position.speed;
          content =
              'Trip ($mode) • ${(displaySpeed * 3.6).toStringAsFixed(1)} km/h';
        } else {
          content = 'Tracking • ${_profileManager.currentConfig.label} mode';
        }
        service.setForegroundNotificationInfo(
          title: 'NaviQ Active',
          content: content,
        );
      }
    },
    onError: (e) async {
      StructuredLogger.log(LogTag.BG, 'Stream Error', error: e);

      // The stream dies permanently on error with no auto-resubscribe —
      // previously this meant a transient failure (or a permission revoke
      // that later gets fixed by the child, e.g. in Settings) left location
      // updates dead until the app was fully restarted, even though nothing
      // else in this isolate would ever know to retry. Guard against
      // stacking multiple pending retries if onError fires repeatedly.
      if (_resubscribeScheduled) return;
      _resubscribeScheduled = true;
      Future.delayed(const Duration(seconds: 10), () async {
        _resubscribeScheduled = false;
        final status = await _getLocationPermissionStatus();
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if ((status == 'granted' || status == 'while_using') &&
            serviceEnabled) {
          StructuredLogger.log(
            LogTag.BG,
            'Resubscribing to location stream after error',
          );
          _startLocationStream(service);
        } else {
          StructuredLogger.log(
            LogTag.BG,
            'Not resubscribing — permission=$status, serviceEnabled=$serviceEnabled',
          );
        }
      });
    },
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    await dotenv.load(fileName: '.env');

    await CsvFileLogger.instance.init();
    StructuredLogger.log(LogTag.BG, 'Service onStart initiated');

    if (service is AndroidServiceInstance) {
      await service.setAsForegroundService();
    }

    // Service control listeners
    if (service is AndroidServiceInstance) {
      service
          .on('setAsForeground')
          .listen((_) => service.setAsForegroundService());
      service
          .on('setAsBackground')
          .listen((_) => service.setAsBackgroundService());
    }

    service.on('stopService').listen((_) {
      StructuredLogger.log(LogTag.BG, 'Stop signal received');
      _aliveTimer?.cancel();
      _positionSubscription?.cancel();
      _serviceStatusSubscription?.cancel();
      _stateMachine?.dispose();
      service.stopSelf();
    });

    // Fresh-evidence boost requested from another isolate (FCM handler:
    // server geofence-verification probe) — high accuracy / small filter for
    // a short, time-boxed window, then back to normal.
    service.on('boost').listen((event) {
      final seconds = (event?['seconds'] as num?)?.toInt();
      _applyBoost(
        service,
        seconds != null
            ? Duration(seconds: seconds)
            : GeofenceTrackingConfig.boostDuration,
      );
    });

    // Allow profile override from UI isolate
    service.on('setProfile').listen((event) {
      final profileName = event?['profile'] as String?;
      if (profileName != null) {
        final p = TrackingProfile.values.firstWhere(
          (e) => e.name == profileName,
          orElse: () => TrackingProfile.still,
        );
        final changed = _profileManager.setProfile(p);
        if (changed) _startLocationStream(service);
      }
    });

    // Dependencies
    await SharedPrefsService.init();
    final sharedPrefsService = SharedPrefsService();

    if (sharedPrefsService.isParent) {
      StructuredLogger.log(
        LogTag.BG,
        'Parent device detected – killing service',
      );
      service.stopSelf();
      return;
    }

    final connectivity = Connectivity();
    final connectivityBloc = ConnectivityBloc(connectivity: connectivity);
    final dioClient = DioClient(
      connectivityBloc: connectivityBloc,
      sharedPrefsService: sharedPrefsService,
    );
    final childRepo = ChildRepo(
      dioClient: dioClient,
      sharedPrefsService: sharedPrefsService,
    );
    final childLocationRepo = ChildGoogleMapsRepo();
    final battery = Battery();

    final trackingConfigService = TrackingConfigService(
      dio: dioClient,
      prefs: sharedPrefsService,
    );

    _stateMachine = LocationStateMachine(
      childRepo: childRepo,
      locationRepo: childLocationRepo,
      prefs: sharedPrefsService,
      battery: battery,
      configService: trackingConfigService,
    );

    _stateMachine!.onRequestBoost = (d) => _applyBoost(service, d);
    _stateMachine!.profileLabelProvider = () =>
        _profileManager.effectiveProfileLabel;

    // Start with 'still' profile — adapts on first position
    _startLocationStream(service);

    // Liveness marker for the native layer (TrackingRecovery.kt reads it): the
    // Android service existing is not proof that THIS isolate is still running
    // the location stream, and a stationary child emits no fixes to infer it
    // from. Only the isolate itself can write it.
    _writeAliveMarker(sharedPrefsService);
    _aliveTimer?.cancel();
    _aliveTimer = Timer.periodic(
      TrackingRecoveryPolicy.aliveMarkerInterval,
      (_) => _writeAliveMarker(sharedPrefsService),
    );

    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen(
      (ServiceStatus status) async {
        if (status != _lastServiceStatus) {
          StructuredLogger.log(
            LogTag.GPS,
            'Location services ${_lastServiceStatus == null ? "" : "changed "}'
            '→ $status'
            '${_lastServiceStatus != null ? " (was $_lastServiceStatus)" : ""}',
          );
          _lastServiceStatus = status;
        }
        final isEnabled = status == ServiceStatus.enabled;
        if (isEnabled) {
          _startLocationStream(service);
        } else {
          _positionSubscription?.cancel();
        }

        // Report the toggle to the backend immediately, rather than waiting
        // for the next cold-start/resume/force-refresh device-status post —
        // this is what makes the parent's location-on/off status reflect the
        // real OS toggle right away instead of going stale for however long
        // it takes for one of those other triggers to happen. Also refreshes
        // deviceStatus.lastHeartbeat, which keeps the tracking-snapshot
        // staleness check accurate even when nothing else has changed.
        //
        // Also opportunistically re-checks permission here too — Android has
        // no OS-level stream for permission changes the way it does for the
        // service toggle, so this is a second free chance to notice the
        // child fixed it in Settings, on top of the app-resume re-check in
        // ChildBloc.didChangeAppLifecycleState.
        final childId = sharedPrefsService.getString('child_id');
        if (childId != null && childId.isNotEmpty) {
          final permissionStatus = await _getLocationPermissionStatus();
          childRepo.postChildData({
            'child_id': childId,
            'gps_enabled': isEnabled,
            'location_permission': permissionStatus,
          });
        }
      },
      onError: (e) {
        StructuredLogger.log(
          LogTag.BG,
          'Service Status Stream Error',
          error: e,
        );
      },
    );
  } catch (e) {
    StructuredLogger.log(LogTag.BG, 'onStart Fatal Error', error: e);
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  StructuredLogger.log(LogTag.BG, 'iOS Background Fetch Triggered');

  // Previously a no-op. iOS invokes this — instead of keeping the continuous
  // position stream from onStart/onForeground alive — once the app has been
  // backgrounded long enough for iOS to suspend it. iOS schedules background
  // fetch opportunistically (commonly tens of minutes apart, entirely OS
  // controlled), so doing nothing here meant location pings — and therefore
  // geofence detection, which depends on them (see LocationStateMachine) —
  // could stall for that entire window until the app was foregrounded again.
  // Take a single quick fix and post it so the server's existing near-real-time
  // geofence pipeline (QueueService → geofence.service.checkGeofencesBatch)
  // has something fresh to evaluate instead of waiting for app resume.
  try {
    await dotenv.load(fileName: '.env');
    await SharedPrefsService.init();
    final prefs = SharedPrefsService();

    if (prefs.isParent) return true;

    final childId = prefs.getString('child_id');
    if (childId == null || childId.isEmpty) {
      StructuredLogger.log(
        LogTag.BG,
        'iOS Background Fetch: no child_id – skipping',
      );
      return true;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20),
    );

    final dioClient = DioClient(sharedPrefsService: prefs);
    final childRepo = ChildRepo(
      dioClient: dioClient,
      sharedPrefsService: prefs,
    );

    final response = await childRepo.postChildLocation({
      'child_id': childId,
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'accuracy_m': position.accuracy,
      ...speedFields(position),
      ...locationDiagnostics(fixSource: 'ios_background_fetch'),
      'bearing': position.heading < 0 ? 0.0 : position.heading,
      // position.timestamp, not DateTime.now() — see location_state_machine.dart's
      // _postChildLocation for why: a stale cached OS fix relabeled with a
      // fresh wall-clock timestamp looks like real new movement to the
      // backend's trip detection when it's actually the same old point.
      'timestamp': position.timestamp.toUtc().toIso8601String(),
    });

    StructuredLogger.log(
      LogTag.BG,
      'iOS Background Fetch: posted location fix (success=${response.isSuccess})',
    );
    StructuredLogger.log(
      LogTag.LOCATION,
      'source=ios_background_fetch lat=${position.latitude} lng=${position.longitude} '
      'acc=${position.accuracy.toStringAsFixed(1)}m '
      'status=${response.isSuccess ? "posted" : "failed"}',
      buffered: true,
    );
  } catch (e) {
    StructuredLogger.log(
      LogTag.BG,
      'iOS Background Fetch: failed to post location',
      error: e,
    );
    StructuredLogger.log(
      LogTag.LOCATION,
      'source=ios_background_fetch status=failed',
      error: e,
    );
  }

  return true;
}
