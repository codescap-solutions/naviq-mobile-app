import 'dart:async';
import 'package:child_track/app/home/model/home_model.dart';
import 'package:child_track/app/home/model/device_model.dart';
import 'package:child_track/app/home/model/last_trip_model.dart';
import 'package:child_track/app/home/model/location_info_model.dart';
import 'package:child_track/app/home/model/yesterday_trip_summary_model.dart';
import 'package:child_track/app/home/model/cards_model.dart';
import 'package:child_track/app/home/model/trip_list_model.dart';
import 'package:child_track/app/home/model/trip_detail_model.dart';
import 'package:child_track/app/home/model/child_tracking_snapshot.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/app/map/view_model/map_bloc.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/socket_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

part 'homepage_event.dart';

class HomepageBloc extends Bloc<HomepageEvent, HomepageState> {
  final HomeRepository _homeRepository;
  final MapBloc _mapBloc;
  final SharedPrefsService _sharedPrefsService;
  final SocketService _socketService;
  StreamSubscription? _locationSubscription;
  StreamSubscription? _statusSubscription;
  Timer? _snapshotPollTimer;
  String? _joinedRoomChildId;
  DateTime? _lastAppliedLocationTs;
  String? _lastChildId;
  // Which child's data state.currentLocation actually reflects right now.
  // See _isNewerLocationUpdate's use of this below — needed because
  // displayedSince (state.currentLocation?.since) keeps showing the
  // PREVIOUS child's timestamp for the whole async gap between switching
  // children and that child's own fetch landing.
  String? _currentLocationChildId;

  HomepageBloc({
    required HomeRepository homeRepository,
    required MapBloc mapBloc,
    SharedPrefsService? sharedPrefsService,
    required SocketService socketService,
  }) : _homeRepository = homeRepository,
       _mapBloc = mapBloc,
       _sharedPrefsService = sharedPrefsService ?? SharedPrefsService(),
       _socketService = socketService,
       super(HomepageSuccess.initial()) {
    on<GetHomepageData>(_onGetHomepageData);
    on<GetTrips>(_onGetTrips);
    on<GetTripDetail>(_onGetTripDetail);
    on<UpdateSocketLocation>(_onUpdateSocketLocation);
    on<UpdateSocketStatus>(_onUpdateSocketStatus);
    on<UpdateCurrentLocationName>(_onUpdateCurrentLocationName);
    on<RefreshTrackingSnapshot>(_onRefreshTrackingSnapshot);
  }

  void _initSocketListeners(String childId) {
    // Only tear down and recreate the socket when it isn't already connected.
    // This used to run unconditionally on every GetHomepageData dispatch —
    // including the internal 2.5s "progress fetch" that follows every initial
    // load, the "silent refresh" fired after a socket update, and the resume
    // refresh — which meant a perfectly healthy, actively-streaming connection
    // got disposed and rebuilt from scratch on a routine basis. Rebuilding the
    // connection takes a moment (disconnect + reconnect + re-auth + rejoin the
    // room), and any location_update the child emits during that window is
    // lost — most noticeable exactly while the child is moving and posting
    // updates frequently. Listener subscriptions are still refreshed every
    // call since they're cheap and idempotent.
    if (!_socketService.isConnected) {
      _socketService.initSocket();
    }
    // join_child_room was never paired with a leave when the parent switches
    // which child they're viewing, so the socket stayed joined to every
    // room ever viewed this session — the root cause of location/status
    // updates for a different linked child leaking into the current view
    // (see the child_id guards in _onUpdateSocketLocation/_onUpdateSocketStatus,
    // which are the actual fix; this just stops the stale traffic at the
    // source instead of only filtering it after arrival).
    if (_joinedRoomChildId != null && _joinedRoomChildId != childId) {
      _socketService.leaveRoom(_joinedRoomChildId!);
    }
    // Skip re-joining a room we're already connected to. _onGetHomepageData
    // fires from several independent, legitimate triggers within seconds of
    // each other (the isProgressFetching follow-up, silent-refresh after a
    // socket location/status update) — this used to call joinRoom
    // unconditionally on every single one, which re-triggered the server's
    // catch-up snapshot on each redundant join. Confirmed as the cause of a
    // real incident: the map visibly flip-flopped between that repeated
    // catch-up point and whatever REST had just shown (see the
    // device_timestamp guard in _onUpdateSocketLocation/_onGetHomepageData
    // for the other half of that fix — this stops the redundant join at the
    // source, that rejects a stale point if one still gets through).
    final alreadyJoined =
        _joinedRoomChildId == childId && _socketService.isConnected;
    if (!alreadyJoined) {
      _socketService.joinRoom(childId);
      _joinedRoomChildId = childId;
    }

    _locationSubscription?.cancel();
    _locationSubscription = _socketService.locationStream.listen((data) {
      add(UpdateSocketLocation(data));
    });

    _statusSubscription?.cancel();
    _statusSubscription = _socketService.statusStream.listen((data) {
      add(UpdateSocketStatus(data));
    });

    // The tracking-snapshot-driven stale/offline banner (see home_page.dart)
    // otherwise only refreshes on initial load, app resume, or manual
    // pull-to-refresh — so a child going stale/offline while the parent sits
    // on an already-open Home screen wouldn't be reflected until one of those
    // happens. Poll it lightly in the background instead.
    _snapshotPollTimer?.cancel();
    _snapshotPollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      add(const RefreshTrackingSnapshot());
    });
  }

  Future<void> _onRefreshTrackingSnapshot(
    RefreshTrackingSnapshot event,
    Emitter<HomepageState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomepageSuccess) return;

    final childId = _sharedPrefsService.getString('child_id');
    if (childId == null || childId.isEmpty) return;

    try {
      final response = await _homeRepository.getTrackingSnapshot(childId);
      if (response.isSuccess && response.data != null) {
        final freshState = state is HomepageSuccess
            ? state as HomepageSuccess
            : currentState;
        emit(
          freshState.copyWith(
            trackingSnapshot: ChildTrackingSnapshot.fromJson(response.data!),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error polling tracking snapshot: ${e.toString()}');
    }
  }

  @override
  Future<void> close() {
    _locationSubscription?.cancel();
    _statusSubscription?.cancel();
    _snapshotPollTimer?.cancel();
    _socketService.disconnect();
    return super.close();
  }

  Future<void> _onGetHomepageData(
    GetHomepageData event,
    Emitter<HomepageState> emit,
  ) async {
    final currentState = state;

    final childId = _sharedPrefsService.getString('child_id');

    // Captured BEFORE _lastChildId is overwritten below — reused both for
    // the existing timestamp-guard reset and the state-clearing fix right
    // after it.
    final bool isChildSwitch =
        childId != null && _lastChildId != null && _lastChildId != childId;

    // Reset the device-timestamp guard whenever the viewed child changes.
    // Without this, switching from an active child (whose recent live-ping
    // set _lastAppliedLocationTs to e.g. "today") to an offline child
    // (whose last-known REST location is days older) causes
    // _isNewerLocationUpdate to return false, silently skipping the
    // _mapBloc.add(UpdateChildLocation) call and leaving the map marker
    // stuck at the previous child's position. Resetting to null makes
    // _isNewerLocationUpdate "fail open" for the first update after a
    // switch, so whichever timestamp the new child's REST response carries
    // is always applied.
    if (isChildSwitch) {
      _lastAppliedLocationTs = null;
    }
    _lastChildId = childId;

    if (childId != null) {
      _initSocketListeners(childId);
    }

    final HomepageSuccess startingState = currentState is HomepageSuccess
        ? currentState
        : const HomepageSuccess.initial();

    if (!event.isSilentRefresh) {
      // On a genuine child switch, copyWith'ing off startingState would
      // carry the PREVIOUS child's currentLocation/deviceStatus/
      // trackingSnapshot/childAvatar/activeTrip straight into the loading
      // state — copyWith's `x ?? this.x` pattern means passing null here
      // does NOT clear a field, it just falls back to the old value. Since
      // the widget tree doesn't gate every one of those fields behind
      // isLoading, the parent visibly sees the outgoing child's location/
      // battery/etc for the whole fetch window after tapping a different
      // child in Profiles — confirmed real complaint, not just a timing
      // nitpick. Building the loading state off a fresh .initial() instead
      // (only on a real switch, not a same-child refresh — same-child
      // should keep showing its own still-valid data while it silently
      // refreshes, no reason to flicker that) forces every one of those
      // fields back to null until the new child's fetch actually resolves.
      final HomepageSuccess baseState = isChildSwitch
          ? const HomepageSuccess.initial()
          : startingState;
      emit(
        baseState.copyWith(
          isLoading: true,
          trips: event.isProgressFetching ? startingState.trips : [],
          hasReachedMax: event.isProgressFetching
              ? startingState.hasReachedMax
              : false,
          tripsPage: event.isProgressFetching ? startingState.tripsPage : 1,
          waitingForSilentSyncResponse: !event.isProgressFetching,
        ),
      );
    }

    try {
      final response = await _homeRepository.getHomeData(childId: childId);

      ChildTrackingSnapshot? trackingSnapshot;
      if (childId != null) {
        final snapshotResponse = await _homeRepository.getTrackingSnapshot(
          childId,
        );
        if (snapshotResponse.isSuccess && snapshotResponse.data != null) {
          trackingSnapshot = ChildTrackingSnapshot.fromJson(
            snapshotResponse.data!,
          );
        }
      }

      // The parent may have switched to viewing a different child while this
      // request was in flight — childId above was captured before the
      // awaits, so a response resolving after the switch would otherwise
      // still get applied here, silently overwriting the newly-selected
      // child's map marker/battery/name/etc with the previous child's. This
      // is the REST-path counterpart of the child_id guard 374f584 added to
      // the socket handlers (_onUpdateSocketLocation/_onUpdateSocketStatus)
      // — that fix never covered this path, which had no identity check at
      // all, only the timestamp-based _isNewerLocationUpdate freshness
      // guard below (which alone isn't enough: an active child's genuinely
      // newer timestamp can still beat an offline child's older one even
      // though the offline child is who's now selected).
      if (childId != _sharedPrefsService.getString('child_id')) {
        AppLogger.info(
          '[HomepageBloc] Dropping getHomeData response for $childId — '
          'parent is now viewing ${_sharedPrefsService.getString('child_id')}',
        );
        return;
      }

      // Get the freshest state after the async gap to prevent overwriting other events
      final freshState = state is HomepageSuccess
          ? state as HomepageSuccess
          : startingState;

      if (response.isSuccess && response.data != null) {
        final homeData = response.data!;

        if (homeData.childName != null) {
          await _sharedPrefsService.setString(
            'child_name',
            homeData.childName!,
          );
        }
        if (homeData.childCode != null) {
          await _sharedPrefsService.setString(
            'child_code',
            homeData.childCode!,
          );
        }

        final tripsToUse = homeData.yesterdayTrips;
        // Same device_timestamp guard as the socket path — see
        // _isNewerLocationUpdate doc comment. A REST response can arrive
        // after a newer socket update was already shown (or vice versa);
        // only apply whichever is actually newer.
        final applyRestLocation = _isNewerLocationUpdate(
          homeData.currentLocation.since,
        );
        if (applyRestLocation) {
          _mapBloc.add(
            UpdateChildLocation(
              LatLng(homeData.currentLocation.lat, homeData.currentLocation.lng),
              zoom: 16.5,
            ),
          );
        }
        emit(
          freshState.copyWith(
            deviceInfo: homeData.deviceInfo,
            yesterdayTrips: tripsToUse,
            yesterdayTripSummary: homeData.yesterdayTripSummary,
            cards: homeData.cards,
            currentLocation: applyRestLocation
                ? homeData.currentLocation
                : freshState.currentLocation,
            webFilteringEnabled: homeData.webFilteringEnabled,
            childAvatar: homeData.childAvatar,
            features: homeData.features,
            todayRoute: homeData.todayRoute,
            screentimeToday: homeData.screentimeToday,
            sharedChildren: homeData.sharedChildren ?? [],
            activeTrip: homeData.activeTrip,
            trackingSnapshot: trackingSnapshot ?? freshState.trackingSnapshot,
            isLoading: false,
            hasNoChild: false,
            waitingForSilentSyncResponse:
                (event.isSilentRefresh || event.isProgressFetching)
                ? false
                : freshState.waitingForSilentSyncResponse,
          ),
        );

        // If this was the first load (not silent, not progress fetching), call again with progress fetching
        if (!event.isSilentRefresh && !event.isProgressFetching) {
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (!isClosed) {
              add(const GetHomepageData(isProgressFetching: true));
            }
          });
        }
      } else {
        // Check if error is due to no child connected
        if (response.message.toLowerCase().contains('child') ||
            response.message.toLowerCase().contains('not found')) {
          emit(
            startingState.copyWith(
              isLoading: false,
              hasNoChild: true,
              waitingForSilentSyncResponse: false,
            ),
          );
        } else {
          if (event.isProgressFetching || event.isSilentRefresh) {
            emit(freshState.copyWith(isLoading: false));
          } else {
            emit(HomepageError(message: response.message));
          }
        }
      }
    } catch (e) {
      AppLogger.error('Error fetching home data: ${e.toString()}');
      final freshState = state is HomepageSuccess
          ? state as HomepageSuccess
          : startingState;
      if (event.isProgressFetching || event.isSilentRefresh) {
        emit(freshState.copyWith(isLoading: false));
      } else {
        emit(
          HomepageError(message: 'Failed to load home data: ${e.toString()}'),
        );
      }
    }
  }

  Future<void> _onGetTrips(GetTrips event, Emitter<HomepageState> emit) async {
    AppLogger.info('💡 [_onGetTrips] Called with page: ${event.page}');
    final currentState = state;

    if (currentState is! HomepageSuccess) {
      AppLogger.warning(
        '💡 [_onGetTrips] Returned early: state is not HomepageSuccess (${currentState.runtimeType})',
      );
      return;
    }

    // If we've already reached max and trying to fetch more (not refresh), return
    if (currentState.hasReachedMax && event.page != 1) {
      AppLogger.warning(
        '💡 [_onGetTrips] Returned early: hasReachedMax is true',
      );
      return;
    }

    // If already loading trips, avoid duplicate requests
    if (currentState.isLoadingTrips) {
      AppLogger.warning(
        '💡 [_onGetTrips] Returned early: isLoadingTrips is true',
      );
      return;
    }

    AppLogger.info('💡 [_onGetTrips] Proceeding to fetch trips...');
    emit(currentState.copyWith(isLoadingTrips: true));

    try {
      final childId = _sharedPrefsService.getString('child_id');
      AppLogger.info('💡 [_onGetTrips] using childId: $childId');

      final response = await _homeRepository.getTrips(
        childId: childId,
        page: event.page,
        pageSize: event.pageSize,
        includePoints: true,
      );

      if (response.isSuccess && response.data != null) {
        // Get freshet state here too
        final freshState = state is HomepageSuccess
            ? state as HomepageSuccess
            : currentState;

        final tripsData = response.data!;
        final newTrips = tripsData.trips;
        final totalItems = tripsData.totalItems;

        List<Trip> allTrips;
        if (event.page == 1) {
          allTrips = newTrips;
        } else {
          allTrips = List.of(freshState.trips)..addAll(newTrips);
        }

        final hasReachedMax = allTrips.length >= totalItems;

        emit(
          freshState.copyWith(
            trips: allTrips,
            tripsPage: tripsData.page,
            tripsPageSize: tripsData.pageSize,
            tripsTotalItems: totalItems,
            isLoadingTrips: false,
            hasReachedMax: hasReachedMax,
          ),
        );
      } else {
        final freshState = state is HomepageSuccess
            ? state as HomepageSuccess
            : currentState;
        emit(freshState.copyWith(isLoadingTrips: false));
        AppLogger.error('Failed to fetch trips: ${response.message}');
      }
    } catch (e) {
      final freshState = state is HomepageSuccess
          ? state as HomepageSuccess
          : currentState;
      AppLogger.error('Error fetching trips: ${e.toString()}');
      emit(freshState.copyWith(isLoadingTrips: false));
    }
  }

  Future<void> _onGetTripDetail(
    GetTripDetail event,
    Emitter<HomepageState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomepageSuccess) return;
    emit(
      currentState.copyWith(
        isLoadingTripDetail: true,
        selectedTripId: event.tripId,
      ),
    );
    try {
      final childId = _sharedPrefsService.getString('child_id');
      final response = await _homeRepository.getTripDetail(
        event.tripId,
        childId: childId,
      );

      final freshState = state is HomepageSuccess
          ? state as HomepageSuccess
          : currentState;
      if (response.isSuccess && response.data != null) {
        emit(
          freshState.copyWith(
            selectedTripDetail: response.data!,
            isLoadingTripDetail: false,
          ),
        );
      } else {
        emit(freshState.copyWith(isLoadingTripDetail: false));
        AppLogger.error('Failed to fetch trip detail: ${response.message}');
      }
    } catch (e) {
      final freshState = state is HomepageSuccess
          ? state as HomepageSuccess
          : currentState;
      AppLogger.error('Error fetching trip detail: ${e.toString()}');
      emit(freshState.copyWith(isLoadingTripDetail: false));
    }
  }

  // Shared by both write paths (REST in _onGetHomepageData, socket in
  // _onUpdateSocketLocation) so whichever source has the actually-newer
  // device_timestamp wins, regardless of which one happens to arrive last in
  // wall-clock order. Confirmed root cause of a real incident: without this,
  // a redundant socket catch-up snapshot (re-triggered by a rejoined room)
  // and a REST response could each overwrite the other within seconds,
  // visibly flip-flopping the map marker between an old and a new point.
  // Fails open (returns true) on unparseable/missing timestamps rather than
  // permanently blocking updates over a formatting quirk.
  //
  // The baseline used to be a standalone _lastAppliedLocationTs field that
  // only ever moved forward, independent of what was actually on screen.
  // Confirmed root cause of a second, real incident (2026-08-14): once
  // anything set that field ahead of the child device's own clock — e.g. a
  // REST /parent/home response whose `since` came from a different
  // timestamp source than the socket's device_timestamp — every genuinely
  // newer socket location_update after that point kept losing to it and
  // got silently dropped ("Ignoring stale location_update"), permanently
  // freezing the map marker for an actively-moving child until the parent
  // switched children (which resets the field) and back. Re-anchoring the
  // baseline to state.currentLocation.since — what's actually displayed —
  // instead of the private watermark makes it self-correcting: it can never
  // drift ahead of reality, because it *is* reality.
  //
  // Third incident (2026-08-16): that self-correcting baseline defeated the
  // separate "reset _lastAppliedLocationTs on child switch" fix above. The
  // reset only clears the private watermark — displayedSince is derived
  // live from state.currentLocation?.since, which for the whole async gap
  // between switching children and the new child's own getHomeData/socket
  // response landing is still the PREVIOUS child's timestamp (often
  // recent/live). An offline child switched to right after an active one
  // then had their older real timestamp rejected as "stale" against the
  // previous child's fresher one, leaving the map/address permanently
  // showing the previous child's location mislabeled with the new child's
  // name — confirmed on two real children this way. displayedSince is only
  // trustworthy as a baseline when it actually belongs to the
  // currently-viewed child; otherwise fall through to the watermark (which
  // the switch-reset above correctly nulls out).
  bool _isNewerLocationUpdate(String? deviceTimestampStr) {
    final incoming = deviceTimestampStr != null
        ? DateTime.tryParse(deviceTimestampStr)
        : null;
    if (incoming == null) return true;

    final currentState = state;
    final displayedSince =
        currentState is HomepageSuccess && _currentLocationChildId == _lastChildId
        ? DateTime.tryParse(currentState.currentLocation?.since ?? '')
        : null;
    final baseline = displayedSince ?? _lastAppliedLocationTs;

    if (baseline != null && incoming.isBefore(baseline)) {
      AppLogger.info(
        '[HomepageBloc] Rejecting location_update ($incoming) — older than '
        'displayed baseline ($baseline)',
      );
      return false;
    }
    _lastAppliedLocationTs = incoming;
    _currentLocationChildId = _lastChildId;
    return true;
  }

  Future<void> _onUpdateSocketLocation(
    UpdateSocketLocation event,
    Emitter<HomepageState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomepageSuccess) return;

    try {
      final data = event.locationData;
      AppLogger.info('[HomepageBloc] Processing socket location update: $data');

      // The socket connection accumulates a joined room for every child the
      // parent has ever viewed this session (join_child_room is never paired
      // with a leave when switching), so a location ping from a DIFFERENT
      // linked child can still arrive here well after the parent has moved
      // on to viewing someone else. The server always includes child_id in
      // this payload — drop anything that doesn't match who's currently
      // selected instead of overwriting the map with the wrong child.
      final eventChildId = data['child_id']?.toString();
      final selectedChildId = _sharedPrefsService.getString('child_id');
      if (eventChildId != null &&
          selectedChildId != null &&
          eventChildId != selectedChildId) {
        AppLogger.info(
          '[HomepageBloc] Ignoring location_update for $eventChildId — currently viewing $selectedChildId',
        );
        return;
      }

      if (currentState.waitingForSilentSyncResponse) {
        emit(currentState.copyWith(waitingForSilentSyncResponse: false));
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (!isClosed) {
            add(const GetHomepageData(isSilentRefresh: true));
          }
        });
      }

      // Helper to safely extract double value
      double toDouble(dynamic value) {
        if (value == null) return 0.0;
        if (value is double) return value;
        if (value is int) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0.0;
        return 0.0;
      }

      // Extract lat/lng
      final lat = toDouble(data['lat'] ?? data['latitude']);
      final lng = toDouble(data['lng'] ?? data['longitude']);

      if (lat == 0.0 && lng == 0.0) {
        AppLogger.warning(
          '[HomepageBloc] Invalid location data: lat=$lat, lng=$lng',
        );
        return;
      }

      // Map 'timestamp' from socket (or 'since') to the 'since' field in model
      final since =
          (data['timestamp'] ??
                  data['last_update'] ??
                  DateTime.now().toIso8601String())
              .toString();

      // Reject a point older than what's currently displayed — see
      // _isNewerLocationUpdate doc comment.
      if (!_isNewerLocationUpdate(since)) {
        AppLogger.info(
          '[HomepageBloc] Ignoring stale location_update (since: $since, is_catch_up: ${data['is_catch_up']}) — older than what is already displayed',
        );
        return;
      }

      // Update MapBloc
      _mapBloc.add(UpdateChildLocation(LatLng(lat, lng), zoom: 16.5));

      // Extract other fields using the payload keys provided
      final address = data['address'] as String? ?? 'Unknown Location';
      // Extract place name logic
      String finalPlaceName = 'Unknown Place';
      final rawPlace =
          data['current_place'] ?? data['place_name'] ?? data['placeName'];

      if (rawPlace is Map) {
        finalPlaceName =
            rawPlace['placeName'] ?? rawPlace['place_name'] ?? 'Unknown Place';
      } else if (rawPlace is String) {
        finalPlaceName = rawPlace;
      }

      // Update state.currentLocation
      LocationInfo updatedLocation;
      if (currentState.currentLocation != null) {
        // Update existing location
        updatedLocation = currentState.currentLocation!.copyWith(
          lat: lat,
          lng: lng,
          address: address,
          placeName: finalPlaceName,
          since: since,
          // Preserving durationMinutes as it's not in the new payload, or default to 0
          durationMinutes: currentState.currentLocation!.durationMinutes,
        );
      } else {
        // Create new location if it doesn't exist
        updatedLocation = LocationInfo(
          lat: lat,
          lng: lng,
          address: address,
          placeName: finalPlaceName,
          since: since,
          durationMinutes: 0,
        );
      }

      emit(currentState.copyWith(currentLocation: updatedLocation));
    } catch (e, stackTrace) {
      AppLogger.error('Error handling socket location update: $e');
      AppLogger.error('Stack trace: $stackTrace');
    }
  }

  Future<void> _onUpdateSocketStatus(
    UpdateSocketStatus event,
    Emitter<HomepageState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomepageSuccess) return;

    try {
      final data = event.statusData;
      AppLogger.info('[HomepageBloc] Processing socket status update: $data');

      // Same cross-child leakage risk as _onUpdateSocketLocation — the
      // socket stays joined to every room the parent has viewed this
      // session, so a status_update for a different linked child can still
      // arrive here.
      final eventChildId = data['child_id']?.toString();
      final selectedChildId = _sharedPrefsService.getString('child_id');
      if (eventChildId != null &&
          selectedChildId != null &&
          eventChildId != selectedChildId) {
        AppLogger.info(
          '[HomepageBloc] Ignoring status_update for $eventChildId — currently viewing $selectedChildId',
        );
        return;
      }

      if (currentState.waitingForSilentSyncResponse) {
        emit(currentState.copyWith(waitingForSilentSyncResponse: false));
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (!isClosed) {
            add(const GetHomepageData(isSilentRefresh: true));
          }
        });
      }

      final deviceInfo = currentState.deviceInfo;
      if (deviceInfo == null) return;

      final updatedDeviceInfo = deviceInfo.copyWith(
        batteryPercentage: data['battery_percentage'] as int?,
        networkStatus: data['network_status'] as String?,
        networkType: data['network_type'] as String?,
        soundProfile: data['sound_profile'] as String?,
        isOnline: data['is_online'] as bool?,
        isCharging: data['is_charging'] as bool?,
        onlineSince: data['last_update'] as String?,
      );

      emit(currentState.copyWith(deviceInfo: updatedDeviceInfo));
    } catch (e) {
      AppLogger.error('Error handling socket status update: $e');
    }
  }

  void _onUpdateCurrentLocationName(
    UpdateCurrentLocationName event,
    Emitter<HomepageState> emit,
  ) {
    final currentState = state;
    if (currentState is HomepageSuccess &&
        currentState.currentLocation != null) {
      final updatedLocation = currentState.currentLocation!.copyWith(
        placeName: event.newName,
      );
      emit(currentState.copyWith(currentLocation: updatedLocation));
    }
  }
}
