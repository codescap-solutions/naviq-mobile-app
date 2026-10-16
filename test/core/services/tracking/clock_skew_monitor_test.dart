import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/tracking/clock_skew_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

BaseResponse skew({num offset = 1200}) => BaseResponse.error(
  message: 'Location timestamp is too far from server time',
  statusCode: 400,
  errorCode: 'CLOCK_SKEW',
  errorData: {'server_time': '2026-10-10T10:00:00.000Z', 'clock_offset_seconds': offset},
);

void main() {
  late DateTime now;
  late ClockSkewMonitor monitor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 10, 10, 0);
    monitor = ClockSkewMonitor(now: () => now);
  });

  test('nothing recorded → no warning', () async {
    expect(await monitor.read(), isNull);
  });

  test('a CLOCK_SKEW refusal raises the warning with the reported offset', () async {
    await monitor.observe(skew(offset: 1200));
    final s = await monitor.read();
    expect(s, isNotNull);
    expect(s!.offsetSeconds, 1200);
    expect(s.detectedAt, now);
  });

  test('a phone that is AHEAD reports a negative offset and is warned the same way', () async {
    await monitor.observe(skew(offset: -1500));
    expect((await monitor.read())!.offsetSeconds, -1500);
  });

  test('an unrelated failure (offline, 500, other 400) neither raises nor clears the warning', () async {
    await monitor.observe(BaseResponse.error(message: 'Internet not available.'));
    expect(await monitor.read(), isNull);
    await monitor.observe(skew());
    await monitor.observe(BaseResponse.error(message: 'boom', statusCode: 500));
    await monitor.observe(BaseResponse.error(message: 'bad', statusCode: 400, errorCode: 'TOO_OLD'));
    expect(await monitor.read(), isNotNull);
  });

  test('a normal delayed offline-queue replay (200 history_only) NEVER raises the warning', () async {
    await monitor.observe(BaseResponse.success(data: {'history_only': true, 'reason': 'DELAYED'}));
    expect(await monitor.read(), isNull);
  });

  test('...and does not clear an active one either: history is not proof the clock is fixed', () async {
    await monitor.observe(skew());
    await monitor.observe(BaseResponse.success(data: {'history_only': true, 'reason': 'DELAYED'}));
    await monitor.observe(BaseResponse.success(data: {'duplicate': true}));
    expect(await monitor.read(), isNotNull);
  });

  test('the server accepting a live point clears it (the condition the backend clears its own flag on)', () async {
    await monitor.observe(skew());
    await monitor.observe(BaseResponse.success(data: {}));
    expect(await monitor.read(), isNull);
  });

  test('without further posts the prompt expires after 30 minutes', () async {
    await monitor.observe(skew());
    now = now.add(const Duration(minutes: 29));
    expect(await monitor.read(), isNotNull);
    now = now.add(const Duration(minutes: 2));
    expect(await monitor.read(), isNull);
  });

  test('a clock that moved BACKWARDS since detection (the user fixed it) no longer shows the old verdict', () async {
    await monitor.observe(skew());
    now = now.subtract(const Duration(hours: 5));
    expect(await monitor.read(), isNull);
  });

  test('a second detection refreshes the timestamp (still skewed → keeps showing)', () async {
    await monitor.observe(skew());
    now = now.add(const Duration(minutes: 25));
    await monitor.observe(skew(offset: 1300));
    now = now.add(const Duration(minutes: 25));
    final s = await monitor.read();
    expect(s, isNotNull);
    expect(s!.offsetSeconds, 1300);
  });

  test('state survives a different ClockSkewMonitor instance (another isolate reads what the service wrote)', () async {
    await monitor.observe(skew());
    expect(await ClockSkewMonitor(now: () => now).read(), isNotNull);
  });

  group('values written by the native Android layer (NativeClockSkew.kt)', () {
    // Native code writes `flutter.clock_skew_detected_at_ms` / `flutter.clock_skew_offset_s`
    // as Longs; shared_preferences adds the `flutter.` prefix itself, so these are the
    // plain keys on the Dart side. This is the other half of the Kotlin key-name test.
    test('are read back as the active warning', () async {
      final detected = DateTime(2026, 10, 10, 9, 50);
      SharedPreferences.setMockInitialValues({
        'clock_skew_detected_at_ms': detected.millisecondsSinceEpoch,
        'clock_skew_offset_s': 1200,
      });
      final s = await monitor.read();
      expect(s, isNotNull);
      expect(s!.detectedAt, detected);
      expect(s.offsetSeconds, 1200);
    });

    test('a native verdict with no offset reads as unknown offset', () async {
      SharedPreferences.setMockInitialValues({'clock_skew_detected_at_ms': now.millisecondsSinceEpoch});
      final s = await monitor.read();
      expect(s, isNotNull);
      expect(s!.offsetSeconds, isNull);
    });

    test('the native layer clearing the keys clears the warning', () async {
      SharedPreferences.setMockInitialValues({'clock_skew_detected_at_ms': now.millisecondsSinceEpoch});
      expect(await monitor.read(), isNotNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('clock_skew_detected_at_ms');
      expect(await monitor.read(), isNull);
    });
  });
}
