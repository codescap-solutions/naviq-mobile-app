import 'dart:async';

import 'package:child_track/app/home/model/home_model.dart';
import 'package:child_track/app/home/model/trip_list_model.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/app/map/view_model/map_bloc.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHomeRepo extends Mock implements HomeRepository {}

class MockMapBloc extends Mock implements MapBloc {}

class MockSocket extends Mock implements SocketService {}

TripListResponse tripsFor(String tripId) => TripListResponse(
  trips: [
    Trip(
      tripId: tripId,
      dayLabel: 'Today',
      startTime: '',
      endTime: '',
      distanceKm: '1',
      eventsCount: 0,
      fromPlace: '',
      toPlace: '',
      points: const [],
      rideMode: 'driving',
    ),
  ],
  page: 1,
  pageSize: 10,
  totalItems: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHomeRepo repo;
  late SharedPrefsService prefs;
  late HomepageBloc bloc;
  late MockSocket socket;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'child_id': 'kidA'});
    await SharedPrefsService.init();
    prefs = SharedPrefsService();
    repo = MockHomeRepo();
    socket = MockSocket();
    when(() => socket.isConnected).thenReturn(false);
    when(() => socket.locationStream).thenAnswer((_) => const Stream.empty());
    when(() => socket.statusStream).thenAnswer((_) => const Stream.empty());
    bloc = HomepageBloc(
      homeRepository: repo,
      mapBloc: MockMapBloc(),
      sharedPrefsService: prefs,
      socketService: socket,
    );
  });

  tearDown(() => bloc.close());

  test("Kid A's slow trips response cannot land in Kid B's list", () async {
    final slowA = Completer<BaseResponse<TripListResponse>>();
    when(
      () => repo.getTrips(
        childId: 'kidA',
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
        includePoints: any(named: 'includePoints'),
      ),
    ).thenAnswer((_) => slowA.future);

    bloc.add(const GetTrips());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect((bloc.state as HomepageSuccess).isLoadingTrips, isTrue);

    await prefs.setString('child_id', 'kidB'); // notification selects Kid B
    slowA.complete(BaseResponse.success(data: tripsFor('trip-of-A')));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final state = bloc.state as HomepageSuccess;
    expect(state.trips, isEmpty, reason: "Kid A's trips must be dropped");
    expect(state.isLoadingTrips, isFalse, reason: 'loading flag must reset');
  });

  test('a response for the still-selected child is applied', () async {
    when(
      () => repo.getTrips(
        childId: 'kidA',
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
        includePoints: any(named: 'includePoints'),
      ),
    ).thenAnswer(
      (_) async => BaseResponse.success(data: tripsFor('trip-of-A')),
    );

    bloc.add(const GetTrips());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect((bloc.state as HomepageSuccess).trips.single.tripId, 'trip-of-A');
  });

  test("an error for Kid A after switching to Kid B does not replace Kid B's "
      'screen with an error', () async {
    final slowA = Completer<BaseResponse<HomeResponse>>();
    when(
      () => repo.getHomeData(childId: 'kidA'),
    ).thenAnswer((_) => slowA.future);

    bloc.add(const GetHomepageData());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await prefs.setString('child_id', 'kidB');
    slowA.completeError(Exception('boom for A'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(bloc.state, isA<HomepageSuccess>());
  });

  test("a failed (non-throwing) response for Kid A is dropped after the "
      'switch', () async {
    final slowA = Completer<BaseResponse<HomeResponse>>();
    when(
      () => repo.getHomeData(childId: 'kidA'),
    ).thenAnswer((_) => slowA.future);

    bloc.add(const GetHomepageData());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await prefs.setString('child_id', 'kidB');
    when(() => repo.getTrackingSnapshot('kidA')).thenAnswer(
      (_) async => BaseResponse<Map<String, dynamic>>.error(message: 'none'),
    );
    slowA.complete(BaseResponse.error(message: 'Server exploded'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(bloc.state, isA<HomepageSuccess>());
  });

  test("Kid A's stale trips response does not clear Kid B's loading flag "
      'or list', () async {
    final tripsA = Completer<BaseResponse<TripListResponse>>();
    final tripsB = Completer<BaseResponse<TripListResponse>>();
    when(
      () => repo.getTrips(
        childId: 'kidA',
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
        includePoints: any(named: 'includePoints'),
      ),
    ).thenAnswer((_) => tripsA.future);
    when(
      () => repo.getTrips(
        childId: 'kidB',
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
        includePoints: any(named: 'includePoints'),
      ),
    ).thenAnswer((_) => tripsB.future);
    when(() => repo.getHomeData(childId: 'kidB')).thenAnswer(
      (_) async => BaseResponse.success(data: HomeResponse.fromJson({})),
    );
    when(() => repo.getTrackingSnapshot('kidB')).thenAnswer(
      (_) async => BaseResponse<Map<String, dynamic>>.error(message: 'none'),
    );

    // Kid A was on screen first (a real child switch needs a previous load).
    when(() => repo.getHomeData(childId: 'kidA')).thenAnswer(
      (_) async => BaseResponse.success(data: HomeResponse.fromJson({})),
    );
    when(() => repo.getTrackingSnapshot('kidA')).thenAnswer(
      (_) async => BaseResponse<Map<String, dynamic>>.error(message: 'none'),
    );
    bloc.add(const GetHomepageData());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    bloc.add(const GetTrips()); // Kid A, still in flight
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await prefs.setString('child_id', 'kidB'); // notification -> Kid B
    bloc.add(const GetHomepageData()); // resets the state for the new child
    await Future<void>.delayed(const Duration(milliseconds: 50));
    bloc.add(const GetTrips()); // Kid B's own request
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect((bloc.state as HomepageSuccess).isLoadingTrips, isTrue);

    tripsA.complete(BaseResponse.success(data: tripsFor('trip-of-A')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    var state = bloc.state as HomepageSuccess;
    expect(state.trips, isEmpty);
    expect(
      state.isLoadingTrips,
      isTrue,
      reason: "Kid B's request is still running",
    );

    tripsB.complete(BaseResponse.success(data: tripsFor('trip-of-B')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    state = bloc.state as HomepageSuccess;
    expect(state.trips.single.tripId, 'trip-of-B');
    expect(state.isLoadingTrips, isFalse);
  });
}
