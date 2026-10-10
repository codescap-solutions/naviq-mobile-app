import 'package:child_track/app/childapp/view_model/repository/logout_request_repository.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/app/notification/view/notification_page.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHomeRepo extends Mock implements HomeRepository {}

class MockLogoutRepo extends Mock implements LogoutRequestRepository {}

BaseResponse<List<dynamic>> list(List<Map<String, dynamic>> rows) => BaseResponse.success(data: rows);

Map<String, dynamic> request(String id) => {
  '_id': id,
  'child_id': 'c1',
  'created_at': DateTime.now().toUtc().toIso8601String(),
  'status': 'pending',
};

Map<String, dynamic> feedRow(String requestId) => {
  'id': 'log-$requestId',
  'title': 'Kusuma wants to log out',
  'body': 'Kusuma is asking for permission to log out of the app. Tap to review.',
  'created_at': DateTime.now().toUtc().toIso8601String(),
  'type': 'LOGOUT_REQUEST',
  'status': 'SENT_SUCCESS',
  'is_silent': false,
  'data': {'type': 'LOGOUT_REQUEST', 'request_id': requestId},
};

void main() {
  late MockHomeRepo home;
  late MockLogoutRepo logout;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.init();
    await injector.reset();
    home = MockHomeRepo();
    logout = MockLogoutRepo();
    injector.registerSingleton<HomeRepository>(home);
    injector.registerSingleton<LogoutRequestRepository>(logout);
    when(() => home.getNotificationFeed(page: any(named: 'page'), pageSize: any(named: 'pageSize'))).thenAnswer(
      (_) async => BaseResponse.success(data: {'logs': [feedRow('r1')], 'pagination': {'has_next': false}}),
    );
    when(() => logout.listByStatus(any())).thenAnswer((_) async => list([]));
  });
  tearDown(() => injector.reset());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('a pending request shows Accept and Reject', (tester) async {
    when(() => logout.listPending()).thenAnswer((_) async => list([request('r1')]));
    await pumpPage(tester);

    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Rejected'), findsNothing);
    // the same request is not shown twice (card + feed row)
    expect(find.text('Kusuma wants to log out'), findsNothing); // child name unknown locally → "Your child"
    expect(find.text('Your child wants to log out'), findsOneWidget);
  });

  testWidgets('Reject calls the API with approve=false and the card then says "Rejected" with no buttons', (tester) async {
    when(() => logout.listPending()).thenAnswer((_) async => list([request('r1')]));
    when(() => logout.resolveLogoutRequest(requestId: any(named: 'requestId'), approve: any(named: 'approve')))
        .thenAnswer((_) async => BaseResponse.success(data: {}));
    await pumpPage(tester);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    verify(() => logout.resolveLogoutRequest(requestId: 'r1', approve: false)).called(1);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Approved'), findsNothing);
  });

  testWidgets('Accept shows "Approved"', (tester) async {
    when(() => logout.listPending()).thenAnswer((_) async => list([request('r1')]));
    when(() => logout.resolveLogoutRequest(requestId: any(named: 'requestId'), approve: any(named: 'approve')))
        .thenAnswer((_) async => BaseResponse.success(data: {}));
    await pumpPage(tester);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    verify(() => logout.resolveLogoutRequest(requestId: 'r1', approve: true)).called(1);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
  });

  testWidgets('a failed resolve keeps the buttons (nothing is claimed as rejected)', (tester) async {
    when(() => logout.listPending()).thenAnswer((_) async => list([request('r1')]));
    when(() => logout.resolveLogoutRequest(requestId: any(named: 'requestId'), approve: any(named: 'approve')))
        .thenAnswer((_) async => BaseResponse.error(message: 'Request not found or already resolved'));
    await pumpPage(tester);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Rejected'), findsNothing);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('a request rejected earlier shows "Rejected" on its list row after reopening the page', (tester) async {
    when(() => logout.listPending()).thenAnswer((_) async => list([]));
    when(() => logout.listByStatus('denied')).thenAnswer((_) async => list([request('r1')..['status'] = 'denied']));
    await pumpPage(tester);

    expect(find.text('Kusuma wants to log out'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('a request approved earlier shows "Approved" on its list row', (tester) async {
    when(() => logout.listPending()).thenAnswer((_) async => list([]));
    when(() => logout.listByStatus('approved')).thenAnswer((_) async => list([request('r1')..['status'] = 'approved']));
    await pumpPage(tester);

    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('an expired request (server dropped it after 24 h) shows the plain row, no buttons, no status', (tester) async {
    when(() => logout.listPending()).thenAnswer((_) async => list([]));
    await pumpPage(tester);

    expect(find.text('Kusuma wants to log out'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Rejected'), findsNothing);
    expect(find.text('Approved'), findsNothing);
  });
}
