import 'package:child_track/app/childapp/view/widgets/clock_skew_banner.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/tracking/clock_skew_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

BaseResponse skew() => BaseResponse.error(
  message: 'too far',
  statusCode: 400,
  errorCode: 'CLOCK_SKEW',
  errorData: {'clock_offset_seconds': 1200},
);

void main() {
  late ClockSkewMonitor monitor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    monitor = ClockSkewMonitor();
  });

  Future<void> pumpBanner(WidgetTester tester, {bool isIOS = false, Future<void> Function()? onOpen}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ClockSkewBanner(
                monitor: monitor,
                pollEvery: const Duration(milliseconds: 100),
                isIOS: isIOS,
                onOpenSettings: onOpen,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets('no CLOCK_SKEW verdict → nothing is shown', (tester) async {
    await pumpBanner(tester);
    expect(find.byKey(const Key('clock_skew_message')), findsNothing);
    expect(find.text('Fix'), findsNothing);
  });

  testWidgets('a confirmed CLOCK_SKEW shows a clear prompt to turn on automatic date & time, with a Fix action', (tester) async {
    await tester.runAsync(() => monitor.observe(skew()));
    var opened = 0;
    await pumpBanner(tester, onOpen: () async => opened++);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(const Key('clock_skew_message')), findsOneWidget);
    expect(find.textContaining('date & time'), findsOneWidget);
    expect(find.textContaining('automatic'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clock_skew_fix')));
    expect(opened, 1);
  });

  testWidgets('it disappears by itself once the server accepts a live point (recovery)', (tester) async {
    await tester.runAsync(() => monitor.observe(skew()));
    await pumpBanner(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('clock_skew_message')), findsOneWidget);

    await tester.runAsync(() => monitor.observe(BaseResponse.success(data: {})));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('clock_skew_message')), findsNothing);
  });

  testWidgets('a normal delayed queue replay does not make the prompt appear', (tester) async {
    await tester.runAsync(() => monitor.observe(BaseResponse.success(data: {'history_only': true, 'reason': 'DELAYED'})));
    await pumpBanner(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('clock_skew_message')), findsNothing);
  });

  testWidgets('iOS has no deep link to Date & Time: it shows the exact path instead of a Fix button', (tester) async {
    await tester.runAsync(() => monitor.observe(skew()));
    await pumpBanner(tester, isIOS: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('Set Automatically'), findsOneWidget);
    expect(find.byKey(const Key('clock_skew_fix')), findsNothing);
  });
}
