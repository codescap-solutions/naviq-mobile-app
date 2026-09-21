import 'dart:async';
import 'dart:io';
import 'package:child_track/app/childapp/model/scree_time_model.dart';
import 'package:child_track/app/childapp/view_model/repository/child_location_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/device_info_service.dart';
import 'package:child_track/app/home/model/device_model.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/structured_logger.dart';
import 'package:child_track/core/services/csv_file_logger.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/screen_time_sync_service.dart';
import 'package:child_track/core/services/background_task_service.dart';
import 'package:child_track/core/services/oem_battery_helper.dart';
import 'package:geolocator/geolocator.dart';
part 'child_event.dart';
part 'child_state.dart';

class ChildBloc extends Bloc<ChildEvent, ChildState> with WidgetsBindingObserver {
  final ChildInfoService _deviceInfoService;
  final ChildRepo _childRepo;
  final ChildGoogleMapsRepo _childLocationRepo;
  final SharedPrefsService _sharedPrefsService;
  final ScreenTimeSyncService _screenTimeSyncService;

  StreamSubscription<Position>? _locationSubscription;

  ChildBloc({
    required ChildRepo childRepo,
    required ChildGoogleMapsRepo childLocationRepo,
    required SharedPrefsService sharedPrefsService,
    required ChildInfoService deviceInfoService,
    required ScreenTimeSyncService screenTimeSyncService,
  }) : _deviceInfoService = deviceInfoService,
       _childRepo = childRepo,
       _childLocationRepo = childLocationRepo,
       _sharedPrefsService = sharedPrefsService,
       _screenTimeSyncService = screenTimeSyncService,
       super(ChildDeviceInfoLoaded.initial()) {
    on<LoadDeviceInfo>(_onLoadDeviceInfo);
    on<PostDeviceInfo>(_onPostDeviceInfo);
    on<GetScreenTime>(_onGetScreenTime);
    on<PostScreenTime>(_onPostScreenTime);
    on<OpenUsageSettings>(_onOpenUsageSettings);
    on<CheckUsagePermission>(_onCheckUsagePermission);
    on<GetChildLocation>(_onGetChildLocation);
    on<PostChildLocation>(_onPostChildLocation);
    on<StartTripTracking>(_onStartTripTracking);
    on<StopTripTracking>(_onStopTripTracking);
    on<UpdateTripLocation>(_onUpdateTripLocation);
  }

  void onInitialize() {
    final childId  = _sharedPrefsService.getString('child_id');
    final parentId = _sharedPrefsService.getString('parent_id');

    if (childId != null &&
        childId.isNotEmpty &&
        (parentId == null || parentId.isEmpty)) {
      AppLogger.info('ChildBloc: Initializing for child_id: $childId');
      StructuredLogger.log(LogTag.LIFECYCLE, 'Cold launch — child device init');
      add(LoadDeviceInfo());
      add(CheckUsagePermission());
      add(GetChildLocation());

      // Initialize Socket for real-time updates
      _childRepo.initializeSocket(childId);

      // Schedule background sync
      BackgroundTaskService.schedulePeriodicSync();

      // Register FCM token with server for child device
      FirebaseNotificationService().registerTokenWithServer();

      // iOS: sync credentials to App Group so native Swift can POST in background
      if (Platform.isIOS) {
        _childRepo.syncAppGroupCredentials();
      }

      // iOS lifecycle observer — refreshes Bloc state after native background sync
      WidgetsBinding.instance.addObserver(this);
    } else {
      AppLogger.info(
        'ChildBloc: Skipping initialization - not logged in as child',
      );
    }
  }

  /// Called by the Flutter framework when the app lifecycle changes.
  /// On iOS, after the native Swift handler runs a background sync while the app
  /// is suspended, the Bloc state is stale (old battery/location values).
  /// On Android, location permission has no OS-level change stream to listen
  /// to — the only reliable way to notice the child granted it in Settings
  /// (or it got revoked) is to re-check on resume, same as here. Previously
  /// this whole block was iOS-only, so an Android child could fix their
  /// permission in Settings, come back to the app, and the backend would
  /// keep serving the old denied/stale status indefinitely — nothing else
  /// re-checks it short of a cold start or a parent-triggered force-refresh.
  /// When the child opens the app (resumed), we re-fetch everything so the
  /// UI and backend both show accurate data immediately.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    StructuredLogger.log(LogTag.LIFECYCLE, 'App lifecycle → $state');

    if (state == AppLifecycleState.resumed) {
      AppLogger.info('ChildBloc: App resumed — refreshing location & device info');
      add(GetChildLocation());
      add(LoadDeviceInfo());
      if (_locationSubscription == null) {
        _startChildLocationStream();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Flush any buffered log rows now, in case the OS suspends/kills the
      // process while backgrounded — better to have them on disk a couple
      // seconds early than lose them entirely.
      CsvFileLogger.instance.flush();
    }
  }

  //get child location
  Future<void> _onGetChildLocation(
    GetChildLocation event,
    Emitter<ChildState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ChildDeviceInfoLoaded) return;

    try {
      final location = await _childLocationRepo.getChildLocation();
      if (location != null) {
        emit(currentState.copyWith(childLocation: location));
        final lastPosted = currentState.lastPostedLocation;
        final distance = lastPosted != null
            ? await _childLocationRepo.getDistanceBetweenTwoPoints(
                lastPosted,
                location,
              )
            : 0.0;
        AppLogger.info('new logic: get child location $distance meters');

        if (lastPosted == null || distance >= 10) {
          emit(currentState.copyWith(lastPostedLocation: location));
          AppLogger.info('new logic: Posting child location $location');
          add(PostChildLocation(childLocation: location));

          // Trip Logic
          if (currentState.isTripTracking) {
            add(UpdateTripLocation(location: location));
          } else {
            // Start trip if not already tracking and moved > 10m
            _processTripStartLogic(location, currentState, emit);
          }
        }
        if (_locationSubscription == null) {
          _startChildLocationStream();
        }
      }
    } catch (e) {
      AppLogger.error('Failed to get child location: ${e.toString()}');
    }
  }

  void _processTripStartLogic(
    Position location,
    ChildDeviceInfoLoaded currentState,
    Emitter<ChildState> emit,
  ) {
    // 1. FILTER NOISE
    if (location.accuracy > 30.0) {
      AppLogger.info(
        'new logic:TripCandidate: Ignored poor accuracy point (${location.accuracy}m)',
      );
      return;
    }

    // 2. SLIDING WINDOW MANAGEMENT
    List<Position> newWindow = List.from(currentState.candidatePoints);
    newWindow.add(location);

    // Keep last 15 points max (to allow catching 100m vehicle moves with ~10m gaps)
    if (newWindow.length > 15) {
      newWindow.removeAt(0);
    }

    // 3. CHECK FOR RESET (TIMEOUT)
    if (newWindow.isNotEmpty) {
      final lastPoint = newWindow.last;

      // Check gap from previous point to detect stale window
      if (newWindow.length > 1) {
        final prevPoint = newWindow[newWindow.length - 2];
        final gap = lastPoint.timestamp
            .difference(prevPoint.timestamp)
            .inSeconds;
        // If we haven't moved 10m in 5 minutes, reset window.
        // Child might have stopped and started again later.
        if (gap > 300) {
          AppLogger.info(
            'new logic:TripCandidate: Gap too large ($gap s), resetting window',
          );
          newWindow = [location];
        }
      }
    }

    // 4. ANALYZE WINDOW SIGNALS
    if (newWindow.length < 3) {
      // Not enough points yet
      emit(
        currentState.copyWith(
          candidatePoints: newWindow,
          detectionStatus: TripDetectionStatus.candidate,
        ),
      );
      return;
    }

    // Calculate Metrics
    double totalDistance = 0;
    for (int i = 0; i < newWindow.length - 1; i++) {
      totalDistance += Geolocator.distanceBetween(
        newWindow[i].latitude,
        newWindow[i].longitude,
        newWindow[i + 1].latitude,
        newWindow[i + 1].longitude,
      );
    }

    final startPoint = newWindow.first;
    final endPoint = newWindow.last;
    final straightDist = Geolocator.distanceBetween(
      startPoint.latitude,
      startPoint.longitude,
      endPoint.latitude,
      endPoint.longitude,
    );

    final durationSeconds = endPoint.timestamp
        .difference(startPoint.timestamp)
        .inSeconds;

    // Avoid division by zero or super short duration
    if (durationSeconds < 1) return;

    final avgSpeed = totalDistance / durationSeconds;
    final consistencyRatio = totalDistance > 0
        ? straightDist / totalDistance
        : 0.0;

    AppLogger.info(
      'new logic:',
      'TripCandidate: Window=${newWindow.length} pts, Dur=${durationSeconds}s, '
          'Dist=${totalDistance.toStringAsFixed(1)}m, Speed=${avgSpeed.toStringAsFixed(1)}m/s, '
          'Consistency=${consistencyRatio.toStringAsFixed(2)}',
    );

    // 5. DETERMINE MODE & CHECK RULES
    TripMode? estimatedMode;
    bool rulesMet = false;

    // Mode Thresholds
    // Walking: > 30m, Speed 0.6-1.8 m/s, Duration > 30s
    if (avgSpeed >= 0.6 && avgSpeed <= 1.8) {
      if (totalDistance >= 30 && durationSeconds >= 30) {
        estimatedMode = TripMode.walking;
        rulesMet = true;
      }
    }
    // Cycling/Running: > 60m, Speed 1.8-5.0 m/s
    else if (avgSpeed > 1.8 && avgSpeed <= 5.0) {
      if (totalDistance >= 60 && durationSeconds >= 20) {
        // Treating as vehicle for now or specifically cycling if supported
        estimatedMode = TripMode.vehicle;
        rulesMet = true;
      }
    }
    // Vehicle: > 100m, Speed > 5.0 m/s
    else if (avgSpeed > 5.0) {
      if (totalDistance >= 100 && durationSeconds >= 20) {
        estimatedMode = TripMode.vehicle;
        rulesMet = true;
      }
    }

    // 6. DIRECTION CONSISTENCY CHECK
    if (rulesMet) {
      if (consistencyRatio < 0.6) {
        AppLogger.info(
          'TripCandidate: Rejected due to low consistency ($consistencyRatio)',
        );
        rulesMet = false;
      }
    }

    // 7. DECISION
    if (rulesMet && estimatedMode != null) {
      AppLogger.info('TripCandidate: TRIP CONFIRMED! Mode: $estimatedMode');
      add(StartTripTracking(initialMode: estimatedMode));
      // ALSO: Clear the candidate window?
      // Optional, but good practice.
      // But `StartTripTracking` handler will reset some state?
      // Actually `StartTripTracking` logic (which I saw earlier) resets `tripStartTime` but maybe not `candidatePoints`.
      // It's safer to clear it here or let `StartTripTracking` handle it.
      // `StartTripTracking` handler sets `tripStatus` to moving.
      // I'll leave candidatePoints as is, they might be useful for history or just ignored once tracking starts.
    } else {
      emit(
        currentState.copyWith(
          candidatePoints: newWindow,
          detectionStatus: TripDetectionStatus.candidate,
        ),
      );
    }
  }

  DateTime? _lastStreamEventTime;

  void _startChildLocationStream() {
    _stopChildLocationStream();
    if (isClosed || !_isChildLoggedIn()) return;

    _locationSubscription = _childLocationRepo
        .getPositionStream(5)
        ?.listen(
          (Position position) async {
            // Hotfix: Throttle rapid continuous emissions on iOS
            final now = DateTime.now();
            if (_lastStreamEventTime != null &&
                now.difference(_lastStreamEventTime!).inSeconds < 5) {
              return; // Discard events hitting faster than 5 seconds apart
            }
            _lastStreamEventTime = now;

            AppLogger.debug('new logic: get child stream');
            if (isClosed || !_isChildLoggedIn()) {
              AppLogger.info('new logic: get child stream closed');
              _stopChildLocationStream();
              return;
            }
            final currentState = state;
            if (currentState is ChildDeviceInfoLoaded) {
              AppLogger.info(
                'new logic: get child stream loaded ${position.latitude} ${position.longitude} get called',
              );
              add(GetChildLocation());
            }
          },
          onError: (e) {
            AppLogger.error('new logic: Location stream error: $e');
          },
        );
  }

  void _stopChildLocationStream() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  bool _isChildLoggedIn() {
    final childId = _sharedPrefsService.getString('child_id');
    return childId != null && childId.isNotEmpty;
  }

  @override
  Future<void> close() {
    WidgetsBinding.instance.removeObserver(this);
    _stopChildLocationStream();
    return super.close();
  }

  // to post child location to api in background
  Future<void> _onPostChildLocation(
    PostChildLocation event,
    Emitter<ChildState> emit,
  ) async {
    try {
      final childId = _sharedPrefsService.getString('child_id');
      if (childId == null || childId.isEmpty) {
        AppLogger.warning('new logic: child_id is null, post location');
        return;
      }

      // Address/place_name used to be resolved here via a live reverse-
      // geocoding API call on EVERY location post (every ~5m of movement,
      // per tracking_profile_manager.dart's distanceFilter) — confirmed as
      // the direct cause of a $2500 surprise Google Cloud bill in one month
      // (22,840 Geocoding API calls, mostly from a single actively-moving
      // child, with zero caching). The backend now resolves this itself
      // (child.controller.js saveLocation), cached and distance-gated so it
      // only re-queries once the child has actually moved to a
      // meaningfully different spot — see geocoding.util.js.
      final requestBody = {
        "child_id": childId,
        "lat": event.childLocation.latitude,
        "lng": event.childLocation.longitude,
        "accuracy_m": event.childLocation.accuracy,
        "speed_mps": event.childLocation.speed,
        "bearing": event.childLocation.heading,
        "timestamp": DateTime.now().toUtc().toIso8601String(),
      };
      AppLogger.info(
        'new logic: child location posting to api: reqest $requestBody',
      );

      await _childRepo.postChildLocation(requestBody);
    } catch (e) {
      AppLogger.error(
        'new logic: Failed to post child location: ${e.toString()}',
      );
    }
  }

  // to load device info
  Future<void> _onLoadDeviceInfo(
    LoadDeviceInfo event,
    Emitter<ChildState> emit,
  ) async {
    try {
      final deviceInfo = await _deviceInfoService.getDeviceInfo();
      final currentState = state;
      if (currentState is ChildDeviceInfoLoaded) {
        emit(currentState.copyWith(deviceInfo: deviceInfo));
      } else {
        emit(
          ChildDeviceInfoLoaded(
            deviceInfo: deviceInfo,
            // Preserve defaults for others if initial load
          ),
        );
      }
      add(PostDeviceInfo(deviceInfo: deviceInfo));
    } catch (e) {
      AppLogger.error('Failed to load device info: ${e.toString()}');
    }
  }

  // to post device info
  Future<void> _onPostDeviceInfo(
    PostDeviceInfo event,
    Emitter<ChildState> emit,
  ) async {
    try {
      final childId = _sharedPrefsService.getString('child_id');

      // Telemetry only — lets future background-suspension incidents (e.g.
      // the 390SLW/POCO/Kusma cases) be triaged from server data alone,
      // without needing physical device access to find the manufacturer or
      // whether the OEM battery-onboarding step was ever completed.
      final oemHelper = OemBatteryHelper();
      final manufacturer = await oemHelper.getRawManufacturer();
      final oemOnboardingStatus = await oemHelper.getOnboardingStatus();

      final requestBody = {
        "child_id": childId,
        "battery_percentage": event.deviceInfo.batteryPercentage,
        "network_status": event.deviceInfo.networkStatus,
        "network_type": event.deviceInfo.networkType,
        "sound_profile": event.deviceInfo.soundProfile,
        "is_online": event.deviceInfo.isOnline,
        "gps_enabled": event.deviceInfo.gpsEnabled,
        "location_permission": event.deviceInfo.locationPermissionStatus,
        "timestamp": DateTime.now().toUtc().toIso8601String(),
        if (manufacturer != null) "manufacturer": manufacturer,
        "oem_onboarding_status": oemOnboardingStatus,
      };
      await _childRepo.postChildData(requestBody);
    } catch (e) {
      AppLogger.error('Failed to post device info: ${e.toString()}');
    }
  }

  // to get permission to get child used apps
  Future<void> _onCheckUsagePermission(
    CheckUsagePermission event,
    Emitter<ChildState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ChildDeviceInfoLoaded) {
      AppLogger.warning(
        'ChildBloc: Ignore check permission, state is $currentState',
      );
      return;
    }
    AppLogger.info('ChildBloc: Checking usage permission...');
    final hasPermission = await _deviceInfoService.checkUsagePermission();
    AppLogger.info('ChildBloc: Usage permission result: $hasPermission');
    emit(currentState.copyWith(hasUsagePermission: hasPermission));
    if (hasPermission) {
      add(GetScreenTime());
    }
  }

  // to get child used apps
  Future<void> _onGetScreenTime(
    GetScreenTime event,
    Emitter<ChildState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ChildDeviceInfoLoaded) return;

    // Only check permission if we haven't confirmed it yet
    // Avoid repeated permission checks for performance
    if (!currentState.hasUsagePermission) {
      AppLogger.info('ChildBloc: Permission not yet confirmed, checking...');
      final hasPermission = await _deviceInfoService.checkUsagePermission();
      if (!hasPermission) {
        AppLogger.warning('ChildBloc: Usage permission not granted');
        emit(currentState.copyWith(hasUsagePermission: false, screenTime: []));
        return;
      }
      emit(currentState.copyWith(hasUsagePermission: true));
    }

    try {
      AppLogger.info('ChildBloc: Fetching screen time data');
      final mergedScreenTime = await _screenTimeSyncService
          .fetchScreenTimeData();

      AppLogger.info('ChildBloc: Retrieved ${mergedScreenTime.length} apps');
      emit(currentState.copyWith(screenTime: mergedScreenTime));
      add(PostScreenTime(appScreenTimes: mergedScreenTime));
    } catch (e) {
      AppLogger.error('Failed to get screen time: ${e.toString()}');
    }
  }

  // to post child used apps
  Future<void> _onPostScreenTime(
    PostScreenTime event,
    Emitter<ChildState> emit,
  ) async {
    try {
      final childId = _sharedPrefsService.getString('child_id');
      if (childId == null || childId.isEmpty) {
        AppLogger.warning(
          'ChildBloc: child_id is null, stopping screen time timer',
        );
        return;
      }

      await _screenTimeSyncService.uploadScreenTimeData(
        event.appScreenTimes,
        childId,
      );

      // Icon sync: run after every successful screen-time upload.
      // Uses the same list already fetched — no extra native call.
      // Non-blocking: icon upload failures are caught internally.
      _screenTimeSyncService
          .syncAppIconsOnly(event.appScreenTimes)
          .catchError((e) {
        AppLogger.error('ChildBloc: Icon sync error (non-fatal): $e');
      });
    } catch (e) {
      AppLogger.error('Failed to post screen time: ${e.toString()}');
    }
  }

  // to open usage settings to allow app to access usage data
  Future<void> _onOpenUsageSettings(
    OpenUsageSettings event,
    Emitter<ChildState> emit,
  ) async {
    await _deviceInfoService.openUsageSettings();
  }

  Future<void> _onStartTripTracking(
    StartTripTracking event,
    Emitter<ChildState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ChildDeviceInfoLoaded) return;

    AppLogger.info('new logic:Tripping... Starting trip tracking');

    try {
      final location = await _childLocationRepo.getChildLocation();
      if (location != null) {
        final now = DateTime.now();
        final mode = event.initialMode;

        final pointsToPost = currentState.candidatePoints.isNotEmpty
            ? List<Position>.from(currentState.candidatePoints)
            : [location];

        emit(
          currentState.copyWith(
            isTripTracking: true,
            tripStartTime: now,
            tripLocations: pointsToPost,
            lastTrackedLocation: pointsToPost.last,
            childLocation: location,
            tripStatus: TripStatus.moving,
            tripMode: mode,
            candidatePoints: [],
          ),
        );

        // Immediately trigger API post with the full historical batch
        final childId = _sharedPrefsService.getString('child_id');
        if (childId != null && childId.isNotEmpty) {
          await _postTripBatch(pointsToPost, childId);
        }
      }
    } catch (e) {
      AppLogger.error('Failed to start trip tracking: ${e.toString()}');
    }
  }

  Future<void> _onStopTripTracking(
    StopTripTracking event,
    Emitter<ChildState> emit,
  ) async {
    final currentState = state;
    // Defensive check: only stop if we know we are tracking or have residual state
    if (currentState is! ChildDeviceInfoLoaded) {
      return;
    }

    AppLogger.info(
      'new logic:Tripping... Stopping trip tracking & clearing state',
    );

    emit(
      currentState.copyWith(
        isTripTracking: false,
        tripLocations: [],
        tripStartTime: null,
        lastTrackedLocation: null,
        // Clear candidate window and status to ensure clean slate for next trip
        candidatePoints: [],
        detectionStatus: TripDetectionStatus.idle,
      ),
    );
  }

  Future<void> _onUpdateTripLocation(
    UpdateTripLocation event,
    Emitter<ChildState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ChildDeviceInfoLoaded ||
        !currentState.isTripTracking) {
      return;
    }

    try {
      final childId = _sharedPrefsService.getString('child_id');
      if (childId == null || childId.isEmpty) {
        return;
      }

      final newLocation = event.location;

      // Update local state
      final updatedLocations = [...currentState.tripLocations, newLocation];
      emit(
        currentState.copyWith(
          tripLocations: updatedLocations,
          lastTrackedLocation: newLocation,
        ),
      );

      // Prepare API Payload
      await _postTripBatch([newLocation], childId);
    } catch (e) {
      AppLogger.error('Failed to update trip location: ${e.toString()}');
    }
  }

  Future<void> _postTripBatch(List<Position> points, String childId) async {
    if (points.isEmpty) return;

    try {
      final batteryPercentage = await _deviceInfoService.getBatteryPercentage();

      final formattedPoints = points
          .map(
            (pos) => {
              "lat": pos.latitude,
              "lng": pos.longitude,
              "speed": pos.speed,
              "accuracy": pos.accuracy,
              "ts": pos.timestamp.toUtc().toIso8601String(),
              "battery": batteryPercentage,
            },
          )
          .toList();

      final requestBody = {"points": formattedPoints};

      AppLogger.info(
        'Tripping... Post Trip Location Batch Request: $requestBody',
      );

      final response = await _childRepo.postTripLocation(
        childId: childId,
        data: requestBody,
      );

      AppLogger.info(
        'new logic:Tripping... Post Trip Location Batch Response: ${response.data}',
      );

      if (response.isSuccess && response.data != null) {
        if (_shouldStopTrip(response.data)) {
          AppLogger.info(
            'new logic:Tripping... Backend requested STOP. Stopping now.',
          );
          add(StopTripTracking());
        }
      }
    } catch (e) {
      AppLogger.error('Failed to post trip location batch: ${e.toString()}');
    }
  }

  bool _shouldStopTrip(dynamic responseData) {
    if (responseData == null) return false;

    try {
      final currentState = responseData['currentState'];
      // Condition 1: Current State must be IDLE
      if (currentState != 'IDLE') return false;

      final transitions = responseData['stateTransitions'];
      if (transitions is List && transitions.isNotEmpty) {
        // Condition 2: Must have specific transition to ENDED with confirmation
        for (var transition in transitions) {
          if (transition['to'] == 'ENDED' &&
              transition['reason'] == 'STATIONARY_CONFIRMED') {
            return true;
          }
        }
      }
    } catch (e) {
      AppLogger.error('Error parsing stop trip response: $e');
    }

    return false;
  }

  void stopChildTracking() {
    _stopChildLocationStream();
    BackgroundTaskService.cancelAll();
    add(StopTripTracking());
  }
}
