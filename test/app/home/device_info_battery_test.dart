import 'package:child_track/app/home/model/device_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no battery from the server is "unknown", not a real 0%', () {
    final info = DeviceInfo.fromJson({'is_online': true, 'device_imei': '1'});
    expect(info.batteryKnown, isFalse);
  });

  test('a reported battery (even 0) is known', () {
    expect(DeviceInfo.fromJson({'battery_percentage': 61}).batteryKnown, isTrue);
    expect(DeviceInfo.fromJson({'battery_percentage': 0}).batteryKnown, isTrue);
  });

  test('a live status_update that carries a battery makes it known', () {
    final unknown = DeviceInfo.fromJson({});
    expect(unknown.copyWith(isOnline: true).batteryKnown, isFalse);
    final updated = unknown.copyWith(batteryPercentage: 61);
    expect(updated.batteryKnown, isTrue);
    expect(updated.batteryPercentage, 61);
  });
}
