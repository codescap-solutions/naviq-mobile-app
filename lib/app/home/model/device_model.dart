class DeviceInfo {
  final int batteryPercentage;

  /// False when the server sent no battery reading (a tracker that has not
  /// reported one yet) — shown as "--", never as a real 0%.
  final bool batteryKnown;
  final String networkStatus;
  final String networkType;
  final String soundProfile;
  final bool isOnline;
  final String onlineSince;
  final bool isCharging;
  final bool gpsEnabled;
  final String locationPermissionStatus;
  // Only ever populated for a physical JT808 GPS tracker (not a phone) —
  // see naviQ-server's tcp/server.js and tcp/jt808.js. null for a
  // phone-only child, which is correct: a phone doesn't report altitude or
  // fence-alarm events the way a tracker does.
  final double? altitude;
  final String? lastAlarmType;
  final DateTime? lastAlarmAt;
  final String? deviceImei;

  /// Child is tracked by a hardware device only (no phone ever logged in).
  final bool isDeviceOnly;

  DeviceInfo({
    required this.batteryPercentage,
    this.batteryKnown = true,
    required this.networkStatus,
    required this.networkType,
    required this.soundProfile,
    required this.isOnline,
    required this.onlineSince,
    required this.isCharging,
    this.gpsEnabled = true,
    this.locationPermissionStatus = 'unknown',
    this.altitude,
    this.lastAlarmType,
    this.lastAlarmAt,
    this.deviceImei,
    this.isDeviceOnly = false,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      batteryPercentage: json['battery_percentage'] ?? 0,
      batteryKnown: json['battery_percentage'] != null,
      networkStatus: json['network_status'] ?? '',
      networkType: json['network_type'] ?? '',
      soundProfile: json['sound_profile'] ?? '',
      isOnline: json['is_online'] ?? false,
      onlineSince: json['last_update'] ?? '',
      isCharging: json['is_charging'] ?? false,
      gpsEnabled: json['gps_enabled'] ?? true,
      locationPermissionStatus: json['location_permission'] ?? 'unknown',
      altitude: (json['altitude'] as num?)?.toDouble(),
      lastAlarmType: json['last_alarm_type'] as String?,
      lastAlarmAt: json['last_alarm_at'] != null
          ? DateTime.tryParse(json['last_alarm_at'] as String)
          : null,
      deviceImei: json['device_imei'] as String?,
      isDeviceOnly: json['is_device_only'] == true,
    );
  }

  DeviceInfo copyWith({
    int? batteryPercentage,
    String? networkStatus,
    String? networkType,
    String? soundProfile,
    bool? isOnline,
    String? onlineSince,
    bool? isCharging,
    bool? gpsEnabled,
    String? locationPermissionStatus,
    double? altitude,
    String? lastAlarmType,
    DateTime? lastAlarmAt,
  }) {
    return DeviceInfo(
      batteryPercentage: batteryPercentage ?? this.batteryPercentage,
      batteryKnown: batteryPercentage != null ? true : batteryKnown,
      networkStatus: networkStatus ?? this.networkStatus,
      networkType: networkType ?? this.networkType,
      soundProfile: soundProfile ?? this.soundProfile,
      isOnline: isOnline ?? this.isOnline,
      onlineSince: onlineSince ?? this.onlineSince,
      isCharging: isCharging ?? this.isCharging,
      gpsEnabled: gpsEnabled ?? this.gpsEnabled,
      locationPermissionStatus:
          locationPermissionStatus ?? this.locationPermissionStatus,
      altitude: altitude ?? this.altitude,
      lastAlarmType: lastAlarmType ?? this.lastAlarmType,
      lastAlarmAt: lastAlarmAt ?? this.lastAlarmAt,
      deviceImei: deviceImei,
      isDeviceOnly: isDeviceOnly,
    );
  }
}
