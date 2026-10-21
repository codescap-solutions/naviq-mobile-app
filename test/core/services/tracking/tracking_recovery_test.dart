import 'package:child_track/core/services/background_location_service.dart';
import 'package:child_track/core/services/tracking/tracking_recovery_policy.dart';
import 'package:flutter_test/flutter_test.dart';

RecoveryDecision decide({
  bool android = true,
  bool child = true,
  bool perm = true,
  bool bg = true,
  bool running = false,
  Duration? since,
}) => TrackingRecoveryPolicy.decide(
  isAndroid: android,
  isChildDevice: child,
  hasLocationPermission: perm,
  hasBackgroundLocation: bg,
  serviceRunning: running,
  sinceLastAttempt: since,
);

class FakeProbe {
  int starts = 0;
  bool running = false;
  bool failStart = false;
  bool child = true;
  bool perm = true;
  bool bg = true;
  bool android = true;

  TrackingRecoveryProbe get probe => TrackingRecoveryProbe(
    isAndroid: android,
    isChildDevice: () async => child,
    hasLocationPermission: () async => perm,
    hasBackgroundLocation: () async => bg,
    serviceRunning: () async => running,
    startService: () async {
      starts++;
      if (failStart) throw StateError('ForegroundServiceStartNotAllowedException');
      running = true;
    },
  );
}

void main() {
  group('TrackingRecoveryPolicy.decide', () {
    test('all preconditions → start', () => expect(decide(), RecoveryDecision.start));
    test('iOS never', () => expect(decide(android: false), RecoveryDecision.notAndroid));
    test('parent device never', () => expect(decide(child: false), RecoveryDecision.notChildDevice));
    test('no location permission', () => expect(decide(perm: false), RecoveryDecision.noLocationPermission));
    test('no "Allow all the time" → do not pretend to recover',
        () => expect(decide(bg: false), RecoveryDecision.noBackgroundLocation));
    test('already running → no duplicate start', () => expect(decide(running: true), RecoveryDecision.alreadyRunning));
    test('attempt moments ago → no repeated start', () {
      expect(decide(since: const Duration(seconds: 10)), RecoveryDecision.recentAttempt);
      expect(decide(since: const Duration(seconds: 61)), RecoveryDecision.start);
    });
  });

  group('BackgroundLocationService.recoverIfStopped', () {
    setUp(() => BackgroundLocationService.resetRecoveryThrottleForTests());

    test('eligible event on a stopped service starts it exactly once, even when called repeatedly', () async {
      final f = FakeProbe();
      expect(await BackgroundLocationService.recoverIfStopped(reason: 'fcm', probe: f.probe), RecoveryDecision.start);
      expect(await BackgroundLocationService.recoverIfStopped(reason: 'fcm', probe: f.probe), RecoveryDecision.alreadyRunning);
      f.running = false; // died again inside the throttle window
      expect(await BackgroundLocationService.recoverIfStopped(reason: 'fcm', probe: f.probe), RecoveryDecision.recentAttempt);
      expect(f.starts, 1);
    });

    test('missing permission → no start attempt (fallback untouched)', () async {
      final f = FakeProbe()..perm = false;
      expect(await BackgroundLocationService.recoverIfStopped(reason: 'fcm', probe: f.probe), RecoveryDecision.noLocationPermission);
      expect(f.starts, 0);
    });

    test('service-start failure is reported, never thrown, and is throttled', () async {
      final f = FakeProbe()..failStart = true;
      expect(await BackgroundLocationService.recoverIfStopped(reason: 'fcm', probe: f.probe), RecoveryDecision.startFailed);
      expect(await BackgroundLocationService.recoverIfStopped(reason: 'fcm', probe: f.probe), RecoveryDecision.recentAttempt);
      expect(f.starts, 1);
    });

    test('a probe that itself throws never propagates', () async {
      final probe = TrackingRecoveryProbe(
        isAndroid: true,
        isChildDevice: () async => throw StateError('prefs unavailable'),
        hasLocationPermission: () async => true,
        hasBackgroundLocation: () async => true,
        serviceRunning: () async => false,
        startService: () async {},
      );
      expect(await BackgroundLocationService.recoverIfStopped(reason: 'fcm', probe: probe), RecoveryDecision.startFailed);
    });

    test('parent device: nothing happens', () async {
      final f = FakeProbe()..child = false;
      expect(await BackgroundLocationService.recoverIfStopped(reason: 'fcm', probe: f.probe), RecoveryDecision.notChildDevice);
      expect(f.starts, 0);
    });
  });
}
