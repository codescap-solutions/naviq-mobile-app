import 'dart:async';

import 'package:child_track/core/services/notifications/child_notification_intent.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_logger.dart';

enum ChildRouteOutcome {
  /// Not a child-selecting notification (or it names no valid child): the
  /// existing behaviour — open the app where it is — is left untouched.
  ignored,

  /// Same tap already handled moments ago.
  duplicate,

  /// Session / child list not ready (cold start, logged out): kept as the one
  /// pending intent and applied by [ChildNotificationRouter.flushPending].
  deferred,

  /// A newer tap replaced this one before it was applied.
  superseded,

  /// The child is not in the signed-in parent's accessible list.
  inaccessible,

  /// The target was already the selected child; only the destination is shown.
  alreadySelected,

  /// Selection switched to the target child.
  switched,

  /// Selecting the child threw; [ChildNotificationRouter.onFailure] was told.
  /// The app may still show the previously selected child — the user is told
  /// the notification could not be opened.
  failed,
}

/// Turns a tapped child-specific push into "select that child, show Home".
///
/// All app-specific work is injected, so the real routing/state transitions
/// can be driven in tests without Firebase, Navigator or HTTP.
class ChildNotificationRouter {
  ChildNotificationRouter({
    required this.isReady,
    required this.accessibleChildIds,
    required this.currentChildId,
    required this.selectChild,
    required this.showHome,
    this.refreshAccessibleChildIds,
    this.onInaccessible,
    this.onFailure,
    DateTime Function()? now,
    this.pendingTtl = const Duration(minutes: 5),
    this.duplicateWindow = const Duration(seconds: 3),
  }) : _now = now ?? DateTime.now;

  /// The app's real selection model: the `child_id` pref, switched with
  /// [SharedPrefsService.switchChild], followed by [reloadHome] so Home
  /// refetches for the new child (HomepageBloc drops responses for any other
  /// child than the one in that pref).
  factory ChildNotificationRouter.withPrefs({
    required SharedPrefsService prefs,
    required void Function() reloadHome,
    required void Function(ChildNotificationIntent intent) showHome,
    Future<List<String>> Function()? refreshAccessibleChildIds,
    void Function(ChildNotificationIntent intent)? onInaccessible,
    void Function(ChildNotificationIntent intent, Object error)? onFailure,
    DateTime Function()? now,
  }) => ChildNotificationRouter(
    isReady: () =>
        prefs.isLoggedIn() && prefs.isParent && prefs.getChildren().isNotEmpty,
    accessibleChildIds: () =>
        prefs.getChildren().map((c) => c.childId).toList(),
    currentChildId: () => prefs.getString('child_id'),
    selectChild: (childId) async {
      await prefs.switchChild(childId);
      reloadHome();
    },
    showHome: showHome,
    refreshAccessibleChildIds: refreshAccessibleChildIds,
    onInaccessible: onInaccessible,
    onFailure: onFailure,
    now: now,
  );

  /// Parent session restored and child list loaded.
  final bool Function() isReady;
  final List<String> Function() accessibleChildIds;
  final String? Function() currentChildId;

  /// Persist the selection and reload child-specific data for it.
  final Future<void> Function(String childId) selectChild;

  /// Bring the user to the child's Home/map (called for `switched` and
  /// `alreadySelected`).
  final void Function(ChildNotificationIntent intent) showHome;

  /// One chance to re-fetch the child list when the id is not in the cached
  /// list (e.g. a child added on another device).
  final Future<List<String>> Function()? refreshAccessibleChildIds;
  final void Function(ChildNotificationIntent intent)? onInaccessible;
  final void Function(ChildNotificationIntent intent, Object error)? onFailure;

  final Duration pendingTtl;
  final Duration duplicateWindow;
  final DateTime Function() _now;

  final _resolved = StreamController<ChildNotificationIntent>.broadcast();

  /// Emits after the target child was selected and Home requested.
  Stream<ChildNotificationIntent> get resolved => _resolved.stream;

  final Map<String, DateTime> _recent = {};
  ({ChildNotificationIntent intent, DateTime at})? _pending;
  int _latest = 0;
  Future<void> _queue = Future.value();

  /// Entry point for every tap callback.
  Future<ChildRouteOutcome> handleTap(
    Map<String, dynamic> data, {
    String? messageId,
  }) async {
    final intent = ChildNotificationIntent.fromData(data, messageId: messageId);
    if (intent == null) {
      if (ChildNotificationIntent.isSelectionType(data)) {
        AppLogger.warning(
          '[ChildNotificationRouter] ${data['type']} tap has no valid '
          'child_id — leaving the selection unchanged',
        );
      }
      return ChildRouteOutcome.ignored;
    }
    if (_isDuplicate(intent)) return ChildRouteOutcome.duplicate;

    final ticket = ++_latest;
    if (!isReady()) {
      _pending = (intent: intent, at: _now());
      return ChildRouteOutcome.deferred;
    }
    _pending = null;
    return _enqueue(intent, ticket);
  }

  /// Applies the intent stored while the session was not ready. Safe to call
  /// from Home's init / resume; a no-op without a fresh pending intent.
  Future<ChildRouteOutcome?> flushPending() async {
    final pending = _pending;
    if (pending == null || !isReady()) return null;
    _pending = null;
    if (_now().difference(pending.at) > pendingTtl) return null;
    return _enqueue(pending.intent, ++_latest);
  }

  /// Serialised so selections are applied strictly in tap order; a tap that
  /// was overtaken before it started never touches the selection.
  Future<ChildRouteOutcome> _enqueue(
    ChildNotificationIntent intent,
    int ticket,
  ) {
    final result = Completer<ChildRouteOutcome>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await _apply(intent, ticket));
      } catch (e) {
        // Never throw out of a tap callback, and never leave the user
        // guessing: report it so the UI can say the notification could not be
        // opened.
        AppLogger.error('[ChildNotificationRouter] ${intent.type} failed: $e');
        onFailure?.call(intent, e);
        result.complete(ChildRouteOutcome.failed);
      }
    });
    return result.future;
  }

  Future<ChildRouteOutcome> _apply(
    ChildNotificationIntent intent,
    int ticket,
  ) async {
    if (ticket != _latest) return ChildRouteOutcome.superseded;

    var ids = accessibleChildIds();
    if (!ids.contains(intent.childId) && refreshAccessibleChildIds != null) {
      ids = await refreshAccessibleChildIds!();
      if (ticket != _latest) return ChildRouteOutcome.superseded;
    }
    if (!ids.contains(intent.childId)) {
      AppLogger.warning(
        '[ChildNotificationRouter] ${intent.type} for a child this parent '
        'cannot access — not switching',
      );
      onInaccessible?.call(intent);
      return ChildRouteOutcome.inaccessible;
    }

    final alreadySelected = currentChildId() == intent.childId;
    if (!alreadySelected) {
      await selectChild(intent.childId);
      if (ticket != _latest) return ChildRouteOutcome.superseded;
    }
    showHome(intent);
    _resolved.add(intent);
    return alreadySelected
        ? ChildRouteOutcome.alreadySelected
        : ChildRouteOutcome.switched;
  }

  bool _isDuplicate(ChildNotificationIntent intent) {
    final now = _now();
    _recent.removeWhere((_, at) => now.difference(at) > duplicateWindow);
    final key = intent.dedupeKey;
    if (_recent.containsKey(key)) return true;
    _recent[key] = now;
    return false;
  }

  void dispose() => _resolved.close();
}
