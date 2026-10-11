import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:child_track/core/services/notifications/child_notification_router.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The foreground path: FCM data -> local notification payload -> (tap, or
/// cold launch via getNotificationAppLaunchDetails) -> RemoteMessage ->
/// router. The Firebase plugin itself can't run in a unit test, so these
/// cover the pure steps the service wires together.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kidA = 'aaaaaaaaaaaaaaaaaaaaaaaa';
  const kidB = 'bbbbbbbbbbbbbbbbbbbbbbbb';
  final fcmData = {
    'type': 'SAFE_PLACE_ARRIVAL',
    'child_id': kidB,
    'childId': kidB,
    'event_timestamp': '2026-10-11T08:00:00.000Z',
  };

  test('child_id survives the local-notification payload round trip', () {
    final payload = FirebaseNotificationService.localPayload(
      fcmData,
      'SAFE_PLACE_ARRIVAL',
    );
    final message = FirebaseNotificationService.messageFromLocalPayload(
      payload,
    )!;
    expect(message.data['child_id'], kidB);
    expect(message.data['type'], 'SAFE_PLACE_ARRIVAL');
  });

  test('absent / non-JSON payloads are ignored, not thrown', () {
    expect(FirebaseNotificationService.messageFromLocalPayload(null), isNull);
    expect(
      FirebaseNotificationService.messageFromLocalPayload('not json'),
      isNull,
    );
  });

  test('a relayed local payload selects the child it names', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.init();
    final prefs = SharedPrefsService();
    await prefs.setAuthToken('t');
    await prefs.setUserId('p');
    await prefs.setString('parent_id', 'p');
    await prefs.saveChildren([
      for (final id in [kidA, kidB])
        ChildProfile(
          childId: id,
          childCode: 'c',
          childName: id,
          authToken: 't',
          lastActiveAt: DateTime(2026),
        ),
    ]);
    await prefs.setString('child_id', kidA);
    final router = ChildNotificationRouter.withPrefs(
      prefs: prefs,
      reloadHome: () {},
      showHome: (_) {},
    );

    final message = FirebaseNotificationService.messageFromLocalPayload(
      FirebaseNotificationService.localPayload(fcmData, 'SAFE_PLACE_ARRIVAL'),
    )!;
    final outcome = await router.handleTap(
      message.data,
      messageId: message.messageId,
    );

    expect(outcome, ChildRouteOutcome.switched);
    expect(prefs.getString('child_id'), kidB);
  });
}
