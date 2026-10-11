/// What a tapped push says about *which child* it is for.
///
/// The identity comes only from the payload's `child_id` / `childId` — never
/// from the child currently selected, a child name, or the title/body text.
class ChildNotificationIntent {
  final String childId;
  final String type;

  /// Request / trip / event id when the payload has one; used for dedupe.
  final String? eventId;

  /// Push message id when known (absent for taps relayed via local
  /// notifications, whose payload is the data map only).
  final String? messageId;

  /// Event time or other discriminator so two different events of one type for
  /// one child are not mistaken for a duplicate tap.
  final String? discriminator;

  const ChildNotificationIntent({
    required this.childId,
    required this.type,
    this.eventId,
    this.messageId,
    this.discriminator,
  });

  /// Event types whose destination is "that child's Home/map". Compared
  /// case-insensitively: the server sends upper-case, the app's own display
  /// code historically lower-case.
  static const selectionTypes = {
    'SAFE_PLACE_ARRIVAL',
    'SAFE_PLACE_DEPARTURE',
    'TRIP_STARTED',
    'TRIP_ENDED',
    'LOW_BATTERY',
    'DEVICE_OFFLINE',
    'SOS',
    'GEOFENCE_ALERT',
    'TIME_LIMIT_REACHED',
  };

  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static String normalizeType(Object? raw) =>
      (raw?.toString() ?? '').trim().toUpperCase();

  /// True when a tap on this payload should select a child.
  static bool isSelectionType(Map<String, dynamic> data) =>
      selectionTypes.contains(normalizeType(data['type']));

  /// The target child id in the payload, or null when absent / malformed.
  static String? childIdOf(Map<String, dynamic> data) {
    final raw = (data['child_id'] ?? data['childId'])?.toString().trim();
    return raw != null && _validId.hasMatch(raw) ? raw : null;
  }

  /// Null when [data] is not a child-selecting notification or names no valid
  /// child.
  static ChildNotificationIntent? fromData(
    Map<String, dynamic> data, {
    String? messageId,
  }) {
    if (!isSelectionType(data)) return null;
    final childId = childIdOf(data);
    if (childId == null) return null;
    return ChildNotificationIntent(
      childId: childId,
      type: normalizeType(data['type']),
      eventId: (data['event_id'] ?? data['trip_id'] ?? data['request_id'])
          ?.toString(),
      messageId: messageId,
      discriminator: (data['event_timestamp'] ?? data['place_id'])?.toString(),
    );
  }

  /// Dedupe key for the same tap arriving through several callbacks
  /// (getInitialMessage + onMessageOpenedApp, local + remote).
  String get dedupeKey => messageId != null && messageId!.isNotEmpty
      ? 'm:$messageId'
      : 'c:$childId|$type|${eventId ?? ''}|${discriminator ?? ''}';
}
