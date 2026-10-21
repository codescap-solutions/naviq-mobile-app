import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:child_track/core/services/tracking/enhanced_trip_point.dart';
import 'package:child_track/core/utils/structured_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The types of entries that can be queued.
enum OfflineEntryType { tripPoints, tripEnd, location, geofenceEvent }

/// Represents a strongly typed queue entry with retry and backoff properties.
class QueueEntry {
  final OfflineEntryType type;
  final String childId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int retryCount;
  DateTime? backoffUntil;

  QueueEntry({
    required this.type,
    required this.childId,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.backoffUntil,
  });

  factory QueueEntry.fromJson(Map<String, dynamic> json) => QueueEntry(
    type: OfflineEntryType.values.byName(json['type'] as String),
    childId: json['child_id'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    createdAt: DateTime.parse(json['created_at'] as String),
    retryCount: json['retry_count'] as int? ?? 0,
    backoffUntil: json['backoff_until'] != null
        ? DateTime.parse(json['backoff_until'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'child_id': childId,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
    'retry_count': retryCount,
    'backoff_until': backoffUntil?.toIso8601String(),
  };
}

/// Strongly typed persistent offline queue with exponential backoff and retry.
class OfflineTripQueue {
  static const String _prefsKey = 'naviq_offline_trip_queue';

  static final OfflineTripQueue _instance = OfflineTripQueue._();
  factory OfflineTripQueue() => _instance;
  OfflineTripQueue._();

  final List<QueueEntry> _entries = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _entries.clear();
        _entries.addAll(list.map((e) => QueueEntry.fromJson(e)));
        StructuredLogger.log(
          LogTag.TRIP,
          '[OfflineQ] Loaded ${_entries.length} queued entries',
        );
      } catch (e) {
        StructuredLogger.log(
          LogTag.TRIP,
          '[OfflineQ] Failed to load',
          error: e,
        );
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> enqueuePoints({
    required String childId,
    required List<EnhancedTripPoint> points,
  }) async {
    await load();
    // Anti-duplicate: check if the exact same timestamp is already queued
    final newTs = points.isNotEmpty ? points.first.ts : '';
    final exists = _entries.any(
      (e) =>
          e.type == OfflineEntryType.tripPoints &&
          e.childId == childId &&
          (e.payload['points'] as List?)?.firstOrNull?['ts'] == newTs,
    );

    if (exists) {
      StructuredLogger.log(LogTag.TRIP, '[OfflineQ] Duplicate points ignored');
      return;
    }

    _entries.add(
      QueueEntry(
        type: OfflineEntryType.tripPoints,
        childId: childId,
        payload: {'points': points.map((p) => p.toJson()).toList()},
        createdAt: DateTime.now(),
      ),
    );
    await _persist();
    StructuredLogger.log(
      LogTag.TRIP,
      '[OfflineQ] Queued ${points.length} trip points for $childId',
    );
  }

  Future<void> enqueueTripEnd({
    required String childId,
    required DateTime endedAt,
  }) async {
    await load();
    // Anti-duplicate
    final exists = _entries.any(
      (e) =>
          e.type == OfflineEntryType.tripEnd &&
          e.childId == childId &&
          e.payload['ended_at'] == endedAt.toIso8601String(),
    );

    if (exists) return;

    _entries.add(
      QueueEntry(
        type: OfflineEntryType.tripEnd,
        childId: childId,
        payload: {'ended_at': endedAt.toIso8601String()},
        createdAt: DateTime.now(),
      ),
    );
    await _persist();
    StructuredLogger.log(
      LogTag.TRIP,
      '[OfflineQ] Queued trip-end for $childId',
    );
  }

  Future<void> enqueueLocation({
    required String childId,
    required Map<String, dynamic> payload,
  }) async {
    await load();
    // Anti-duplicate
    final exists = _entries.any(
      (e) =>
          e.type == OfflineEntryType.location &&
          e.childId == childId &&
          e.payload['timestamp'] == payload['timestamp'],
    );

    if (exists) return;

    _entries.add(
      QueueEntry(
        type: OfflineEntryType.location,
        childId: childId,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );

    // A phone that stays offline for hours would otherwise queue one entry per
    // fix without bound, and every enqueue rewrites the whole persisted list.
    // Keep the NEWEST fixes; the oldest are the least useful once replayed.
    final locationEntries = _entries
        .where((e) => e.type == OfflineEntryType.location)
        .toList();
    final overflow = locationEntries.length - maxLocationEntries;
    if (overflow > 0) {
      locationEntries.take(overflow).forEach(_entries.remove);
      StructuredLogger.log(
        LogTag.TRIP,
        '[OfflineQ] Location queue full — dropped $overflow oldest fix(es)',
      );
    }
    await _persist();
  }

  /// Ceiling for queued location fixes (see [enqueueLocation]).
  static const int maxLocationEntries = 500;

  Future<void> enqueueGeofenceEvent({
    required String childId,
    required Map<String, dynamic> payload,
  }) async {
    await load();
    // Anti-duplicate: same geofence + event type + timestamp already queued
    final exists = _entries.any(
      (e) =>
          e.type == OfflineEntryType.geofenceEvent &&
          e.childId == childId &&
          e.payload['geofenceId'] == payload['geofenceId'] &&
          e.payload['eventType'] == payload['eventType'] &&
          e.payload['timestamp'] == payload['timestamp'],
    );

    if (exists) return;

    _entries.add(
      QueueEntry(
        type: OfflineEntryType.geofenceEvent,
        childId: childId,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
    await _persist();
    StructuredLogger.log(
      LogTag.BG,
      '[OfflineQ] Queued geofence event (${payload['eventType']}) for $childId',
    );
  }

  bool get hasPending => _entries.isNotEmpty;
  int get pendingCount => _entries.length;

  /// Max attempts before an entry is dead-lettered (dropped) instead of retried again.
  static const int _maxRetries = 10;

  /// Hard ceiling on backoff duration.
  static const int _maxBackoffSecs = 300; // 5 min

  /// Records a failed upload attempt: bumps retryCount and either schedules
  /// the next backoff window or dead-letters the entry once [_maxRetries] is
  /// exceeded. Returns true if the entry should be dropped (dead-lettered).
  bool _recordFailure(QueueEntry entry, DateTime now, {Object? error}) {
    entry.retryCount++;

    if (entry.retryCount >= _maxRetries) {
      StructuredLogger.log(
        LogTag.TRIP,
        '[OfflineQ] Entry dead-lettered after ${entry.retryCount} retries, dropping (${entry.type.name})',
        error: error,
      );
      return true;
    }

    // Exponential backoff: 2^n * 5s, capped at _maxBackoffSecs. The exponent
    // is clamped before shifting -- 2^6 * 5s (320s) already exceeds the cap,
    // and an uncapped exponent (via math.pow on a large retryCount) overflows
    // int range and silently truncates to 0, which was the original bug.
    final exponent = math.min(entry.retryCount, 6);
    final backoffSecs = math.min((1 << exponent) * 5, _maxBackoffSecs);
    entry.backoffUntil = now.add(Duration(seconds: backoffSecs));
    StructuredLogger.log(
      LogTag.TRIP,
      '[OfflineQ] Entry fail, backoff ${backoffSecs}s (retry: ${entry.retryCount})',
      error: error,
    );
    return false;
  }

  /// Drain the queue by calling the uploader function.
  /// Handles backoff updates dynamically and removes succeeded entries transactionally.
  Future<void> drain(Future<bool> Function(QueueEntry entry) uploader) async {
    await load();
    if (_entries.isEmpty) return;

    final now = DateTime.now();
    final toRemove = <QueueEntry>[];
    bool changed = false;

    for (final entry in _entries) {
      if (entry.backoffUntil != null && entry.backoffUntil!.isAfter(now)) {
        continue; // Skip due to backoff
      }

      try {
        final ok = await uploader(entry);
        if (ok) {
          toRemove.add(entry);
          changed = true;
        } else {
          if (_recordFailure(entry, now)) {
            toRemove.add(entry);
          }
          changed = true;
        }
      } catch (e) {
        if (_recordFailure(entry, now, error: e)) {
          toRemove.add(entry);
        }
        changed = true;
      }
    }

    if (toRemove.isNotEmpty) {
      _entries.removeWhere(toRemove.contains);
    }

    if (changed) {
      await _persist();
    }
  }

  Future<void> clear() async {
    _entries.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
