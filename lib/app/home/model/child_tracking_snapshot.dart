class ChildTrackingSnapshot {
  final String snapshotId;
  final DateTime serverTime;
  final String deviceStatus;
  final String gpsStatus;
  final String permissionStatus;
  final LatestLocation? latestLocation;
  final UiDirective uiDirective;

  /// Present only while the backend has a specific, evidenced problem to report
  /// about the child's phone (today: its clock is wrong). Null otherwise.
  final TrackingWarning? trackingWarning;

  ChildTrackingSnapshot({
    required this.snapshotId,
    required this.serverTime,
    required this.deviceStatus,
    required this.gpsStatus,
    required this.permissionStatus,
    this.latestLocation,
    required this.uiDirective,
    this.trackingWarning,
  });

  factory ChildTrackingSnapshot.fromJson(Map<String, dynamic> json) {
    return ChildTrackingSnapshot(
      snapshotId: json['snapshot_id'] ?? '',
      serverTime: DateTime.parse(json['server_time'] ?? DateTime.now().toIso8601String()),
      deviceStatus: json['device_status'] ?? 'UNKNOWN',
      gpsStatus: json['gps_status'] ?? 'UNKNOWN',
      permissionStatus: json['permission_status'] ?? 'UNKNOWN',
      latestLocation: json['latest_location'] != null
          ? LatestLocation.fromJson(json['latest_location'])
          : null,
      uiDirective: UiDirective.fromJson(json['ui_directive'] ?? {}),
      trackingWarning: json['tracking_warning'] is Map
          ? TrackingWarning.fromJson(Map<String, dynamic>.from(json['tracking_warning'] as Map))
          : null,
    );
  }
}

class TrackingWarning {
  /// e.g. `CLOCK_SKEW`.
  final String code;

  /// Seconds the child's phone is behind the server (negative = ahead).
  final int? offsetSeconds;
  final DateTime? detectedAt;

  const TrackingWarning({required this.code, this.offsetSeconds, this.detectedAt});

  bool get isClockSkew => code == 'CLOCK_SKEW';

  factory TrackingWarning.fromJson(Map<String, dynamic> json) {
    return TrackingWarning(
      code: (json['code'] ?? '').toString(),
      offsetSeconds: (json['offset_seconds'] as num?)?.round(),
      detectedAt: json['detected_at'] != null ? DateTime.tryParse(json['detected_at'].toString()) : null,
    );
  }
}

class LatestLocation {
  final double lat;
  final double lng;
  final double accuracyM;
  final double qualityScore;
  final String provider;
  final DateTime deviceTimestamp;
  final DateTime receivedTimestamp;
  // How long the child has actually been at this spot — distinct from
  // deviceTimestamp above (last GPS ping time). Backend-computed from
  // location history; null when the fix is live (not worth computing) or
  // there isn't enough history to place a confident boundary. See
  // location.controller.js getStationarySince.
  final DateTime? stationarySince;
  // False means the history scan hit its cap before finding where the
  // dwell actually started — stationarySince is a lower bound, not exact
  // (UI should show it as "Xd+").
  final bool? stationarySinceUncapped;

  LatestLocation({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.qualityScore,
    required this.provider,
    required this.deviceTimestamp,
    required this.receivedTimestamp,
    this.stationarySince,
    this.stationarySinceUncapped,
  });

  factory LatestLocation.fromJson(Map<String, dynamic> json) {
    return LatestLocation(
      lat: (json['lat'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? 0.0).toDouble(),
      accuracyM: (json['accuracy_m'] ?? 0.0).toDouble(),
      qualityScore: (json['quality_score'] ?? 0.0).toDouble(),
      provider: json['provider'] ?? '',
      deviceTimestamp: DateTime.parse(json['device_timestamp'] ?? DateTime.now().toIso8601String()),
      receivedTimestamp: DateTime.parse(json['received_timestamp'] ?? DateTime.now().toIso8601String()),
      stationarySince: json['stationary_since'] != null
          ? DateTime.tryParse(json['stationary_since'].toString())
          : null,
      stationarySinceUncapped: json['stationary_since_uncapped'] as bool?,
    );
  }
}

class UiDirective {
  final String displayState;
  final bool showLiveMarker;
  final bool showStaleMarker;
  final String bannerMessage;
  final String actionRequired;

  UiDirective({
    required this.displayState,
    required this.showLiveMarker,
    required this.showStaleMarker,
    required this.bannerMessage,
    required this.actionRequired,
  });

  factory UiDirective.fromJson(Map<String, dynamic> json) {
    return UiDirective(
      displayState: json['display_state'] ?? 'LIVE',
      showLiveMarker: json['show_live_marker'] ?? true,
      showStaleMarker: json['show_stale_marker'] ?? false,
      bannerMessage: json['banner_message'] ?? '',
      actionRequired: json['action_required'] ?? '',
    );
  }
}
