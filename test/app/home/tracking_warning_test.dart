import 'package:child_track/app/home/model/child_tracking_snapshot.dart';
import 'package:child_track/app/home/view/widget/tracking_warning_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> json({Map<String, dynamic>? warning, Map<String, dynamic>? directive}) => {
  'snapshot_id': 's1',
  'server_time': '2026-10-10T10:00:00.000Z',
  'device_status': 'UNREACHABLE',
  'gps_status': 'ON',
  'permission_status': 'granted',
  'ui_directive': directive ??
      {
        'display_state': 'STALE',
        'show_live_marker': false,
        'show_stale_marker': true,
        'banner_message': "Child's phone clock is wrong, so its location can't be shown live. Ask them to turn on automatic date & time.",
        'action_required': 'fix_child_device_clock',
      },
  if (warning != null) 'tracking_warning': warning,
};

void main() {
  group('ChildTrackingSnapshot.tracking_warning', () {
    test('absent for a healthy snapshot (additive field — old servers never send it)', () {
      final s = ChildTrackingSnapshot.fromJson(json(directive: {'display_state': 'LIVE'}));
      expect(s.trackingWarning, isNull);
      expect(TrackingWarningBanner.messageFor(s), isNull);
    });

    test('CLOCK_SKEW is parsed with offset and detection time', () {
      final s = ChildTrackingSnapshot.fromJson(json(warning: {'code': 'CLOCK_SKEW', 'offset_seconds': 1200, 'detected_at': '2026-10-10T09:59:00.000Z', 'basis': 'device_time'}));
      expect(s.trackingWarning!.isClockSkew, isTrue);
      expect(s.trackingWarning!.offsetSeconds, 1200);
      expect(s.trackingWarning!.detectedAt, DateTime.utc(2026, 10, 10, 9, 59));
      expect(s.uiDirective.actionRequired, 'fix_child_device_clock');
    });

    test('an unknown warning code is parsed but never rendered (no unsupported warnings)', () {
      final s = ChildTrackingSnapshot.fromJson(json(warning: {'code': 'SOMETHING_NEW'}));
      expect(s.trackingWarning!.code, 'SOMETHING_NEW');
      expect(TrackingWarningBanner.messageFor(s), isNull);
    });
  });

  group('TrackingWarningBanner', () {
    Future<void> pump(WidgetTester tester, ChildTrackingSnapshot s) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TrackingWarningBanner(snapshot: s))),
    );

    testWidgets("shows the server's own banner_message when it is tagged fix_child_device_clock", (tester) async {
      final s = ChildTrackingSnapshot.fromJson(json(warning: {'code': 'CLOCK_SKEW', 'offset_seconds': 900}));
      await pump(tester, s);
      expect(find.byKey(const Key('tracking_warning_banner')), findsOneWidget);
      expect(find.textContaining('phone clock is wrong'), findsOneWidget);
      expect(find.textContaining('automatic date & time'), findsOneWidget);
    });

    testWidgets('falls back to an equivalent message when the location is not (yet) stale and the directive has none', (tester) async {
      final s = ChildTrackingSnapshot.fromJson(
        json(warning: {'code': 'CLOCK_SKEW'}, directive: {'display_state': 'LIVE', 'banner_message': '', 'action_required': ''}),
      );
      await pump(tester, s);
      expect(find.textContaining('automatic date & time'), findsOneWidget);
    });

    testWidgets('renders nothing without a warning (a stale-but-healthy child is not told anything extra)', (tester) async {
      final s = ChildTrackingSnapshot.fromJson(json(directive: {'display_state': 'STALE', 'banner_message': 'Location hasn\'t been updated recently.', 'action_required': ''}));
      await pump(tester, s);
      expect(find.byKey(const Key('tracking_warning_banner')), findsNothing);
    });
  });
}
