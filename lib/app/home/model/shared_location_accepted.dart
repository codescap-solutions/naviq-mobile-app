/// What a `location_share_accepted` push actually says.
///
/// The backend sends it as a silent data-only message carrying only `share_id`
/// and `child_name` (utils/fcm.util.js sendLocationShareAccepted) — no child id,
/// no coordinates, no expiry. Anything the push does not say stays null instead
/// of being replaced by a placeholder, so the app can never put an invented
/// child at an invented position on a parent's map. The real, current location
/// comes from the shared-children list in the home data.
class SharedLocationAccepted {
  final String childName;
  final String? childId;
  final double? lat;
  final double? lng;
  final DateTime? expiresAt;
  final String? avatar;

  const SharedLocationAccepted({
    required this.childName,
    this.childId,
    this.lat,
    this.lng,
    this.expiresAt,
    this.avatar,
  });

  factory SharedLocationAccepted.fromPush(Map<String, dynamic> data) {
    final id = data['child_id']?.toString().trim();
    final name = data['child_name']?.toString().trim();
    final avatar = data['avatar']?.toString();
    return SharedLocationAccepted(
      childName: name == null || name.isEmpty ? 'Child' : name,
      childId: id == null || id.isEmpty ? null : id,
      lat: double.tryParse(data['lat']?.toString() ?? ''),
      lng: double.tryParse(data['lng']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(data['expires_at']?.toString() ?? ''),
      avatar: avatar == null || avatar.isEmpty ? null : avatar,
    );
  }

  /// Only a push that really names the child AND its position may be drawn on
  /// the map directly; otherwise the screen must refresh the shared-children list.
  bool get canShowOnMap => childId != null && lat != null && lng != null;
}
