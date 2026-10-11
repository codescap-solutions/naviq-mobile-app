import 'dart:async';

import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/services/notifications/child_notification_intent.dart';
import 'package:child_track/core/services/notifications/child_notification_router.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kidA = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const kidB = 'bbbbbbbbbbbbbbbbbbbbbbbb';
const kidC = 'cccccccccccccccccccccccc';

ChildProfile profile(String id, String name) => ChildProfile(
  childId: id,
  childCode: 'CODE-$name',
  childName: name,
  authToken: 'parent-token',
  lastActiveAt: DateTime(2026, 10, 1),
);

/// A tapped push as the app receives it from FCM / a relayed local payload.
Map<String, dynamic> push(String type, String? childId, {String? ts}) => {
  'type': type,
  if (childId != null) 'child_id': childId,
  if (ts != null) 'event_timestamp': ts,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPrefsService prefs;
  late List<String> reloads; // child_id read at each Home reload
  late List<ChildNotificationIntent> homeShown;
  late List<ChildNotificationIntent> inaccessible;
  late List<ChildNotificationIntent> failures;
  var reloadThrows = false;
  late DateTime clock;
  Future<List<String>> Function()? refresh;

  ChildNotificationRouter makeRouter() => ChildNotificationRouter.withPrefs(
    prefs: prefs,
    reloadHome: () {
      if (reloadThrows) throw StateError('bloc unavailable');
      reloads.add(prefs.getString('child_id')!);
    },
    showHome: homeShown.add,
    refreshAccessibleChildIds: () async => refresh!(),
    onInaccessible: inaccessible.add,
    onFailure: (intent, _) => failures.add(intent),
    now: () => clock,
  );

  Future<void> signIn({List<String> ids = const [kidA, kidB, kidC]}) async {
    await prefs.setAuthToken('parent-token');
    await prefs.setUserId('parent-1');
    await prefs.setString('parent_id', 'parent-1');
    await prefs.saveChildren([for (final id in ids) profile(id, 'Kid-$id')]);
    await prefs.setString('child_id', kidA);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.init();
    prefs = SharedPrefsService();
    reloads = [];
    homeShown = [];
    inaccessible = [];
    failures = [];
    reloadThrows = false;
    clock = DateTime(2026, 10, 11, 9);
    refresh = () async => prefs.getChildren().map((c) => c.childId).toList();
    await signIn();
  });

  group(
    'universal child identity (Kid A selected, Kid B notification tapped)',
    () {
      for (final type in ChildNotificationIntent.selectionTypes) {
        test('$type opens Kid B and reloads Home for Kid B', () async {
          final router = makeRouter();
          final outcome = await router.handleTap(push(type, kidB));

          expect(outcome, ChildRouteOutcome.switched);
          expect(prefs.getString('child_id'), kidB);
          expect(reloads, [kidB], reason: 'reload must see the new child');
          expect(homeShown.single.childId, kidB);
          expect(homeShown.single.type, type);
        });
      }

      test('lower-case legacy type names resolve the same way', () async {
        final outcome = await makeRouter().handleTap(push('sos', kidB));
        expect(outcome, ChildRouteOutcome.switched);
        expect(prefs.getString('child_id'), kidB);
      });

      test('camelCase childId key is accepted', () async {
        await makeRouter().handleTap({'type': 'SOS', 'childId': kidB});
        expect(prefs.getString('child_id'), kidB);
      });

      test('a push for the already-selected child only shows Home', () async {
        final outcome = await makeRouter().handleTap(push('SOS', kidA));
        expect(outcome, ChildRouteOutcome.alreadySelected);
        expect(reloads, isEmpty);
        expect(homeShown, hasLength(1));
      });

      test('event id / discriminator survive into the intent', () async {
        final router = makeRouter();
        final seen = <ChildNotificationIntent>[];
        router.resolved.listen(seen.add);
        await router.handleTap({
          'type': 'TRIP_ENDED',
          'child_id': kidB,
          'trip_id': 'trip-9',
          'event_timestamp': '2026-10-11T08:00:00Z',
        });
        await Future<void>.delayed(Duration.zero);
        expect(seen.single.eventId, 'trip-9');
        expect(seen.single.childId, kidB);
      });
    },
  );

  group('lifecycle', () {
    test('foreground tap (relayed local payload, no message id)', () async {
      final outcome = await makeRouter().handleTap(push('LOW_BATTERY', kidB));
      expect(outcome, ChildRouteOutcome.switched);
    });

    test('background tap (message id present)', () async {
      final outcome = await makeRouter().handleTap(
        push('SAFE_PLACE_ARRIVAL', kidB),
        messageId: 'm-1',
      );
      expect(outcome, ChildRouteOutcome.switched);
      expect(prefs.getString('child_id'), kidB);
    });

    test('terminated app: tap before login is held, applied after', () async {
      await prefs.clearAll();
      final router = makeRouter();

      final outcome = await router.handleTap(push('SOS', kidB));
      expect(outcome, ChildRouteOutcome.deferred);
      expect(await router.flushPending(), isNull, reason: 'still logged out');
      expect(reloads, isEmpty);

      await signIn(); // login finishes, child list loaded; login picks Kid A
      expect(prefs.getString('child_id'), kidA);

      expect(await router.flushPending(), ChildRouteOutcome.switched);
      expect(prefs.getString('child_id'), kidB);
      expect(reloads, [kidB]);
      expect(await router.flushPending(), isNull, reason: 'applied once');
    });

    test('a stale pending tap is dropped after the TTL', () async {
      await prefs.clearAll();
      final router = makeRouter();
      await router.handleTap(push('SOS', kidB));
      clock = clock.add(const Duration(minutes: 6));
      await signIn();

      expect(await router.flushPending(), isNull);
      expect(prefs.getString('child_id'), kidA);
    });

    test('a newer deferred tap replaces an older one', () async {
      await prefs.clearAll();
      final router = makeRouter();
      await router.handleTap(push('SOS', kidB));
      await router.handleTap(push('LOW_BATTERY', kidC));
      await signIn();

      await router.flushPending();
      expect(prefs.getString('child_id'), kidC);
      expect(reloads, [kidC]);
    });
  });

  group('safe resolution', () {
    test('child outside the parent\'s list is never selected', () async {
      final router = makeRouter();
      final outcome = await router.handleTap(
        push('SOS', 'dddddddddddddddddddddddd'),
      );
      expect(outcome, ChildRouteOutcome.inaccessible);
      expect(prefs.getString('child_id'), kidA);
      expect(reloads, isEmpty);
      expect(homeShown, isEmpty);
      expect(inaccessible.single.childId, 'dddddddddddddddddddddddd');
    });

    test(
      'child missing from the cached list is found by one refresh',
      () async {
        await signIn(ids: [kidA, kidC]); // cache predates Kid B
        refresh = () async {
          await prefs.saveChildren([
            profile(kidA, 'A'),
            profile(kidB, 'B'),
            profile(kidC, 'C'),
          ]);
          return [kidA, kidB, kidC];
        };
        final outcome = await makeRouter().handleTap(push('SOS', kidB));
        expect(outcome, ChildRouteOutcome.switched);
        expect(prefs.getString('child_id'), kidB);
      },
    );

    for (final bad in <String?>[null, '', '   ', 'a b', '../etc', 'x' * 80]) {
      test('missing / malformed child id ${bad == null ? 'null' : '"$bad"'} '
          'leaves the selection alone', () async {
        final outcome = await makeRouter().handleTap(push('SOS', bad));
        expect(outcome, ChildRouteOutcome.ignored);
        expect(prefs.getString('child_id'), kidA);
        expect(reloads, isEmpty);
      });
    }

    test('child name or text never decides the target', () async {
      final outcome = await makeRouter().handleTap({
        'type': 'SOS',
        'child_name': 'Kid-$kidB',
        'title': 'SOS from Kid-$kidB',
      });
      expect(outcome, ChildRouteOutcome.ignored);
      expect(prefs.getString('child_id'), kidA);
    });
  });

  group('races', () {
    test('duplicate callbacks for one message switch once', () async {
      final router = makeRouter();
      final first = router.handleTap(push('SOS', kidB), messageId: 'm-7');
      final second = router.handleTap(push('SOS', kidB), messageId: 'm-7');
      expect(await first, ChildRouteOutcome.switched);
      expect(await second, ChildRouteOutcome.duplicate);
      expect(reloads, [kidB]);
    });

    test('same payload without ids (local relay) is also deduped', () async {
      final router = makeRouter();
      await router.handleTap(push('SOS', kidB, ts: '2026-10-11T08:00:00Z'));
      final again = await router.handleTap(
        push('SOS', kidB, ts: '2026-10-11T08:00:00Z'),
      );
      expect(again, ChildRouteOutcome.duplicate);
    });

    test('a different event of the same type is not a duplicate', () async {
      final router = makeRouter();
      await router.handleTap(push('SOS', kidB, ts: '2026-10-11T08:00:00Z'));
      await prefs.setString('child_id', kidA);
      final second = await router.handleTap(
        push('SOS', kidB, ts: '2026-10-11T08:05:00Z'),
      );
      expect(second, ChildRouteOutcome.switched);
    });

    test(
      'rapid taps for different children: last tap wins, in order',
      () async {
        final router = makeRouter();
        final b = router.handleTap(push('SOS', kidB), messageId: 'm-b');
        final c = router.handleTap(push('LOW_BATTERY', kidC), messageId: 'm-c');

        expect(await b, ChildRouteOutcome.superseded);
        expect(await c, ChildRouteOutcome.switched);
        expect(prefs.getString('child_id'), kidC);
        expect(reloads, [kidC], reason: 'Kid B was never selected');
      },
    );

    test('tap overtaken while its refresh is in flight is dropped', () async {
      await signIn(ids: [kidA, kidC]);
      final gate = Completer<List<String>>();
      refresh = () => gate.future;
      final router = makeRouter();

      final b = router.handleTap(push('SOS', kidB), messageId: 'm-b');
      await Future<void>.delayed(Duration.zero);
      final c = router.handleTap(push('SOS', kidC), messageId: 'm-c');
      gate.complete([kidA, kidB, kidC]);

      expect(await b, ChildRouteOutcome.superseded);
      expect(await c, ChildRouteOutcome.switched);
      expect(prefs.getString('child_id'), kidC);
    });

    test('manual switch after a notification is never undone', () async {
      final router = makeRouter();
      await router.handleTap(push('SOS', kidB), messageId: 'm-1');
      expect(prefs.getString('child_id'), kidB);

      await prefs.switchChild(kidC); // parent picks Kid C by hand
      expect(await router.flushPending(), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(prefs.getString('child_id'), kidC);

      // …and a later notification still works normally.
      final next = await router.handleTap(
        push('LOW_BATTERY', kidA),
        messageId: 'm-2',
      );
      expect(next, ChildRouteOutcome.switched);
      expect(prefs.getString('child_id'), kidA);
    });
  });

  group('errors', () {
    test(
      'a failing selection is reported, not thrown, and the queue lives on',
      () async {
        final router = makeRouter();
        reloadThrows = true;
        final outcome = await router.handleTap(
          push('SOS', kidB),
          messageId: 'm-1',
        );

        expect(outcome, ChildRouteOutcome.failed);
        expect(failures.single.childId, kidB);
        expect(homeShown, isEmpty, reason: 'Home must not claim success');

        reloadThrows = false;
        final next = await router.handleTap(
          push('SOS', kidC),
          messageId: 'm-2',
        );
        expect(next, ChildRouteOutcome.switched);
        expect(prefs.getString('child_id'), kidC);
      },
    );
  });

  group('notifications with their own destination are left alone', () {
    for (final type in [
      'LOGOUT_REQUEST',
      'TIME_EXTENSION_REQUEST',
      'location_share_request',
      'location_share_accepted',
      'CHAT_MESSAGE',
      'SYNC_SCREEN_TIME',
      'FORCE_REFRESH_DATA',
    ]) {
      test('$type does not change the selected child', () async {
        final outcome = await makeRouter().handleTap(push(type, kidB));
        expect(outcome, ChildRouteOutcome.ignored);
        expect(prefs.getString('child_id'), kidA);
        expect(reloads, isEmpty);
      });
    }
  });
}
