import 'package:child_track/app/home/model/shared_location_accepted.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the backend's real location_share_accepted payload (share_id + child_name only) invents nothing", () {
    final a = SharedLocationAccepted.fromPush({
      'type': 'location_share_accepted',
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'share_id': '65f000000000000000000001',
      'child_name': 'Aneesh',
    });
    expect(a.childName, 'Aneesh');
    expect(a.childId, isNull, reason: "no 'mock_rohan' placeholder id");
    expect(a.lat, isNull, reason: 'no hard-coded Bangalore latitude');
    expect(a.lng, isNull);
    expect(a.expiresAt, isNull, reason: 'no invented 30-minute expiry');
    expect(a.canShowOnMap, isFalse, reason: 'the screen must refresh the shared-children list instead');
  });

  test('a missing or blank child name falls back to a neutral label, never to a real-looking name', () {
    expect(SharedLocationAccepted.fromPush({}).childName, 'Child');
    expect(SharedLocationAccepted.fromPush({'child_name': '  '}).childName, 'Child');
  });

  test('a push that really names the child and its position can be drawn directly', () {
    final a = SharedLocationAccepted.fromPush({
      'child_id': 'c9',
      'child_name': 'Mia',
      'lat': '11.25',
      'lng': 75.78,
      'expires_at': '2026-10-11T12:00:00.000Z',
      'avatar': 'Girl 02.png',
    });
    expect(a.canShowOnMap, isTrue);
    expect(a.lat, 11.25);
    expect(a.lng, 75.78);
    expect(a.expiresAt, DateTime.utc(2026, 10, 11, 12));
    expect(a.avatar, 'Girl 02.png');
  });

  test('half a position (lat without lng, or no child id) is not enough to draw', () {
    expect(SharedLocationAccepted.fromPush({'child_id': 'c9', 'lat': '1'}).canShowOnMap, isFalse);
    expect(SharedLocationAccepted.fromPush({'lat': '1', 'lng': '2'}).canShowOnMap, isFalse);
    expect(SharedLocationAccepted.fromPush({'child_id': 'c9', 'lat': 'abc', 'lng': 'def'}).canShowOnMap, isFalse);
  });
}
