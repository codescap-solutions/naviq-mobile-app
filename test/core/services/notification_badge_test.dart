import 'package:child_track/core/services/notification_badge.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> log(
  String id,
  String at, {
  String title = 'Hi',
  bool silent = false,
  String? status,
}) => {
  'id': id,
  'created_at': at,
  'title': title,
  'is_silent': silent,
  'status': ?status,
};

void main() {
  final seen = DateTime.utc(2026, 10, 18, 10);

  test('only notifications after the last visit count', () {
    final times = NotificationBadge.visibleTimes([
      log('1', '2026-10-18T09:00:00Z'),
      log('2', '2026-10-18T10:30:00Z'),
      log('3', '2026-10-18T11:00:00Z'),
    ], {});
    expect(NotificationBadge.countAfter(times, seen), 2);
  });

  test('silent, untitled, failed and cleared rows never count', () {
    final times = NotificationBadge.visibleTimes(
      [
        log('a', '2026-10-18T11:00:00Z', silent: true),
        log('b', '2026-10-18T11:00:00Z', title: ''),
        log('c', '2026-10-18T11:00:00Z', status: 'FAILED'),
        log('d', '2026-10-18T11:00:00Z'),
        log('e', '2026-10-18T11:00:00Z', status: 'SENT_SUCCESS'),
      ],
      {'d'},
    );
    expect(NotificationBadge.countAfter(times, seen), 1);
  });

  test('a row exactly at the last-seen time is already read', () {
    final times = NotificationBadge.visibleTimes([
      log('1', '2026-10-18T10:00:00Z'),
    ], {});
    expect(NotificationBadge.countAfter(times, seen), 0);
  });
}
