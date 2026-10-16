import 'dart:async';

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

Map<String, dynamic> snapshotOf(String id) => {
  'snapshot_id': id,
  'server_time': '2026-10-10T10:00:00.000Z',
  'device_status': 'ONLINE',
  'gps_status': 'ON',
  'permission_status': 'granted',
  'ui_directive': {
    'display_state': 'STALE',
    'banner_message': "Child's phone clock is wrong.",
    'action_required': 'fix_child_device_clock',
  },
  'tracking_warning': {'code': 'CLOCK_SKEW', 'offset_seconds': 900},
};

/// The periodic tracking-snapshot poll must not leak one child's snapshot (and
/// its clock-skew warning) into the screen of the child selected meanwhile —
/// e.g. after a notification tap switched the selection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockHomeRepo repo;
  late SharedPrefsService prefs;
  late HomepageBloc bloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'child_id': 'kidA'});
    await SharedPrefsService.init();
    prefs = SharedPrefsService();
    repo = MockHomeRepo();
    final socket = MockSocket();
    when(() => socket.isConnected).thenReturn(false);
    when(() => socket.locationStream).thenAnswer((_) => const Stream.empty());
    when(() => socket.statusStream).thenAnswer((_) => const Stream.empty());
    bloc = HomepageBloc(homeRepository: repo, mapBloc: MockMapBloc(), sharedPrefsService: prefs, socketService: socket);
  });
  tearDown(() => bloc.close());

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  test("Kid A's slow snapshot is dropped when Kid B was selected meanwhile", () async {
    final slowA = Completer<BaseResponse<Map<String, dynamic>>>();
    when(() => repo.getTrackingSnapshot('kidA')).thenAnswer((_) => slowA.future);

    bloc.add(const RefreshTrackingSnapshot());
    await settle();
    await prefs.setString('child_id', 'kidB');
    slowA.complete(BaseResponse.success(data: snapshotOf('snap-of-A')));
    await settle();

    expect((bloc.state as HomepageSuccess).trackingSnapshot, isNull, reason: "Kid A's snapshot / clock warning must not appear for Kid B");
  });

  test('a snapshot for the still-selected child is applied', () async {
    when(() => repo.getTrackingSnapshot('kidA')).thenAnswer((_) async => BaseResponse.success(data: snapshotOf('snap-of-A')));
    bloc.add(const RefreshTrackingSnapshot());
    await settle();
    expect((bloc.state as HomepageSuccess).trackingSnapshot!.snapshotId, 'snap-of-A');
  });

  test("a stale snapshot for Kid A never replaces Kid B's already-loaded snapshot", () async {
    final slowA = Completer<BaseResponse<Map<String, dynamic>>>();
    when(() => repo.getTrackingSnapshot('kidA')).thenAnswer((_) => slowA.future);
    when(() => repo.getTrackingSnapshot('kidB')).thenAnswer((_) async => BaseResponse.success(data: snapshotOf('snap-of-B')));

    bloc.add(const RefreshTrackingSnapshot()); // in flight for A
    await settle();
    await prefs.setString('child_id', 'kidB');
    bloc.add(const RefreshTrackingSnapshot()); // B's own poll
    await settle();
    expect((bloc.state as HomepageSuccess).trackingSnapshot!.snapshotId, 'snap-of-B');

    slowA.complete(BaseResponse.success(data: snapshotOf('snap-of-A')));
    await settle();
    expect((bloc.state as HomepageSuccess).trackingSnapshot!.snapshotId, 'snap-of-B');
  });
}
