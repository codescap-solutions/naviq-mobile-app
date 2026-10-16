import 'dart:async';

import 'package:child_track/app/home/model/home_model.dart';
import 'package:child_track/app/home/model/trip_list_model.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_state.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/app/map/view_model/map_bloc.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/notifications/child_notification_router.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHomeRepo extends Mock implements HomeRepository {}

class MockMapBloc extends Mock implements MapBloc {}

class MockSocket extends Mock implements SocketService {}

const kidA = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const kidB = 'bbbbbbbbbbbbbbbbbbbbbbbb';
const kidC = 'cccccccccccccccccccccccc';

ChildProfile profile(String id) => ChildProfile(
  childId: id,
  childCode: 'CODE-$id',
  childName: 'Kid-$id',
  authToken: 'parent-token',
  lastActiveAt: DateTime(2026, 10, 1),
);

TripListResponse tripsFor(String tripId) => TripListResponse(
  trips: [
    Trip(tripId: tripId, dayLabel: 'Today', startTime: '', endTime: '', distanceKm: '1', eventsCount: 0, fromPlace: '', toPlace: '', points: const [], rideMode: 'driving'),
  ],
  page: 1,
  pageSize: 10,
  totalItems: 1,
);

/// The REAL router wired to the REAL HomepageBloc exactly as FirebaseNotificationService
/// wires them (selection persisted, then a Home reload) — only the network is faked.
/// Proves ordering and stale-response handling at code level; real FCM/APNs delivery,
/// navigator behaviour and a mounted HomePage are not covered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockHomeRepo repo;
  late SharedPrefsService prefs;
  late HomepageBloc bloc;
  late ChildNotificationRouter router;
  late List<String> homeDataRequests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.init();
    prefs = SharedPrefsService();
    await prefs.setAuthToken('parent-token');
    await prefs.setUserId('parent-1');
    await prefs.setString('parent_id', 'parent-1');
    await prefs.saveChildren([profile(kidA), profile(kidB), profile(kidC)]);
    await prefs.setString('child_id', kidA);

    repo = MockHomeRepo();
    homeDataRequests = [];
    when(() => repo.getHomeData(childId: any(named: 'childId'))).thenAnswer((i) async {
      homeDataRequests.add(i.namedArguments[#childId] as String);
      return BaseResponse.error(message: 'not needed here');
    });
    when(() => repo.getTrackingSnapshot(any())).thenAnswer((_) async => BaseResponse.error(message: 'n/a'));
    final socket = MockSocket();
    when(() => socket.isConnected).thenReturn(false);
    when(() => socket.locationStream).thenAnswer((_) => const Stream.empty());
    when(() => socket.statusStream).thenAnswer((_) => const Stream.empty());
    bloc = HomepageBloc(homeRepository: repo, mapBloc: MockMapBloc(), sharedPrefsService: prefs, socketService: socket);
    router = ChildNotificationRouter.withPrefs(
      prefs: prefs,
      reloadHome: () => bloc.add(const GetHomepageData()),
      showHome: (_) {},
    );
  });
  tearDown(() async {
    router.dispose();
    await bloc.close();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

  test("a Kid B notification makes Home fetch Kid B's data — selection is persisted BEFORE the reload", () async {
    final outcome = await router.handleTap({'type': 'TRIP_STARTED', 'child_id': kidB});
    await settle();

    expect(outcome, ChildRouteOutcome.switched);
    expect(prefs.getString('child_id'), kidB);
    expect(homeDataRequests, [kidB], reason: 'Home must never fetch for the previously selected Kid A');
  });

  test("a Kid A response still in flight when the Kid B notification is tapped never lands on Kid B", () async {
    // Kid B's own Home fetch stays pending, so the bloc keeps showing a loading state
    // (a failed fetch would legitimately replace it with an error screen).
    when(() => repo.getHomeData(childId: any(named: 'childId'))).thenAnswer((i) {
      homeDataRequests.add(i.namedArguments[#childId] as String);
      return Completer<BaseResponse<HomeResponse>>().future;
    });
    final slowTripsA = Completer<BaseResponse<TripListResponse>>();
    when(() => repo.getTrips(childId: kidA, page: any(named: 'page'), pageSize: any(named: 'pageSize'), includePoints: any(named: 'includePoints')))
        .thenAnswer((_) => slowTripsA.future);
    bloc.add(const GetTrips());
    await settle();
    expect((bloc.state as HomepageSuccess).isLoadingTrips, isTrue);

    await router.handleTap({'type': 'SAFE_PLACE_ARRIVAL', 'child_id': kidB});
    slowTripsA.complete(BaseResponse.success(data: tripsFor('trip-of-A')));
    await settle();

    final state = bloc.state as HomepageSuccess;
    expect(state.trips.where((t) => t.tripId == 'trip-of-A'), isEmpty);
    expect(state.isLoadingTrips, isFalse);
  });

  test('rapid taps for B then C: selection ends on C and Home last fetched C', () async {
    final first = router.handleTap({'type': 'SOS', 'child_id': kidB});
    final second = router.handleTap({'type': 'LOW_BATTERY', 'child_id': kidC});
    await Future.wait([first, second]);
    await settle();

    expect(prefs.getString('child_id'), kidC);
    expect(homeDataRequests.last, kidC);
    expect(homeDataRequests, isNot(contains(kidA)), reason: 'neither tap may reload the old child');
  });

  test('a duplicate delivery of the same tap (initial message + opened-app) reloads Home once', () async {
    await router.handleTap({'type': 'GEOFENCE_ALERT', 'child_id': kidB}, messageId: 'm1');
    final dup = await router.handleTap({'type': 'GEOFENCE_ALERT', 'child_id': kidB}, messageId: 'm1');
    await settle();

    expect(dup, ChildRouteOutcome.duplicate);
    expect(homeDataRequests, [kidB]);
  });

  test('request notifications (logout / time extension) never switch the child or reload Home', () async {
    for (final type in ['LOGOUT_REQUEST', 'TIME_EXTENSION_REQUEST']) {
      final outcome = await router.handleTap({'type': type, 'request_id': 'r1', 'child_id': kidB});
      expect(outcome, ChildRouteOutcome.ignored, reason: type);
    }
    await settle();
    expect(prefs.getString('child_id'), kidA);
    expect(homeDataRequests, isEmpty);
  });

  test('a tap for a child this parent cannot access changes nothing', () async {
    final outcome = await router.handleTap({'type': 'SOS', 'child_id': 'dddddddddddddddddddddddd'});
    await settle();
    expect(outcome, ChildRouteOutcome.inaccessible);
    expect(prefs.getString('child_id'), kidA);
    expect(homeDataRequests, isEmpty);
  });

  test('HomePage init order: flushPending() immediately followed by resolved.listen() still receives the event', () async {
    var ready = false;
    final shown = <String>[];
    final r = ChildNotificationRouter(
      isReady: () => ready,
      accessibleChildIds: () => [kidA, kidB],
      currentChildId: () => kidA,
      selectChild: (_) async {},
      showHome: (i) => shown.add(i.childId),
    );
    // cold start: tapped before the session was ready
    expect(await r.handleTap({'type': 'SOS', 'child_id': kidB}), ChildRouteOutcome.deferred);
    ready = true; // session restored; HomePage.initState runs:
    r.flushPending(); // exactly the call order used in HomePage.initState
    final received = <String>[];
    final sub = r.resolved.listen((i) => received.add(i.childId));
    await settle();
    await sub.cancel();
    r.dispose();
    expect(received, [kidB], reason: 'the listener attached right after flushPending() must not miss the resolution');
    expect(shown, [kidB]);
  });
}
