import 'dart:async';
import 'dart:convert';

import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:flutter/foundation.dart';

/// Unread count for the bell on Home.
///
/// "Unread" = notifications in the server feed that arrived after the parent
/// last opened the notifications screen (and were not cleared). Opening the
/// screen marks everything seen, so the badge disappears.
class NotificationBadge {
  NotificationBadge._();
  static final NotificationBadge instance = NotificationBadge._();

  static const _deliveredStatuses = {'SENT_SUCCESS', 'SENT_PARTIAL'};
  static const _hiddenKey = 'hidden_notification_ids';

  /// Newest page of the feed that is looked at; more than this reads as "9+"
  /// anyway.
  static const _pageSize = 30;

  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  Timer? _debounce;
  bool _refreshing = false;

  SharedPrefsService get _prefs => SharedPrefsService();

  String get _seenKey => 'notif_last_seen_${_prefs.getString('parent_id')}';

  DateTime? _lastSeen() =>
      DateTime.tryParse(_prefs.getString(_seenKey) ?? '')?.toUtc();

  Set<String> _hidden() {
    try {
      final raw = _prefs.getString(_hiddenKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Arrival times of the feed rows the notifications screen would show:
  /// not silent, titled, delivered, and not cleared by the parent.
  @visibleForTesting
  static List<DateTime> visibleTimes(List logs, Set<String> hidden) {
    final times = <DateTime>[];
    for (final raw in logs) {
      final log = Map<String, dynamic>.from(raw as Map);
      final visible =
          log['is_silent'] != true &&
          (log['title'] ?? '').toString().isNotEmpty &&
          (log['status'] == null || _deliveredStatuses.contains(log['status']));
      if (!visible || hidden.contains(log['id']?.toString())) continue;
      final at = DateTime.tryParse('${log['created_at']}')?.toUtc();
      if (at != null) times.add(at);
    }
    return times;
  }

  @visibleForTesting
  static int countAfter(List<DateTime> times, DateTime seen) =>
      times.where((t) => t.isAfter(seen)).length;

  /// Re-count soon. Several pushes in a row collapse into one request, and the
  /// short delay lets the server finish writing the feed row for the push.
  void refreshSoon([Duration delay = const Duration(seconds: 1)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, refresh);
  }

  Future<void> refresh() async {
    if (_refreshing || !_prefs.isParent || !_prefs.isLoggedIn()) return;
    _refreshing = true;
    try {
      final response = await injector<HomeRepository>().getNotificationFeed(
        page: 1,
        pageSize: _pageSize,
      );
      if (!response.isSuccess || response.data == null) return;

      final times = visibleTimes(
        response.data!['logs'] as List? ?? const [],
        _hidden(),
      );

      var seen = _lastSeen();
      if (seen == null) {
        // First run for this parent: start from zero instead of reporting the
        // whole history as new.
        seen = times.isEmpty
            ? DateTime.now().toUtc()
            : times.reduce((a, b) => a.isAfter(b) ? a : b);
        await _prefs.setString(_seenKey, seen.toIso8601String());
      }
      unread.value = countAfter(times, seen);
    } catch (_) {
      // Keep whatever count is showing.
    } finally {
      _refreshing = false;
    }
  }

  /// The parent has looked at the list: everything so far counts as read.
  Future<void> markAllSeen() async {
    _debounce?.cancel();
    unread.value = 0;
    await _prefs.setString(_seenKey, DateTime.now().toUtc().toIso8601String());
  }
}
