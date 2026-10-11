import 'dart:convert';
import 'package:child_track/core/utils/parser_utils.dart';

class ChildProfile {
  final String childId;
  final String childName;
  final String authToken;
  final String? avatar;
  final DateTime lastActiveAt;
  final String childCode;
  final int? age;

  /// Tracker serial (IMEI) of a GPS device linked to this child, if any.
  final String? deviceImei;

  /// True when the child is tracked by a hardware device only — no phone has
  /// logged in, so app features (Scroll, ...) have nothing to control.
  final bool isDeviceOnly;

  /// Whether the child's device is currently online and tracking location
  /// (recent heartbeat), as reported by the server — not a local UI selection.
  final bool isActive;
  final int screenTimeTodayMinutes;
  final String formattedScreenTimeToday;
  final double todayRouteKm;
  final double todayMaxSpeedKmph;

  ChildProfile({
    required this.childId,
    required this.childCode,
    required this.childName,
    required this.authToken,
    this.avatar,
    required this.lastActiveAt,
    this.age,
    this.deviceImei,
    this.isDeviceOnly = false,
    this.isActive = false,
    this.screenTimeTodayMinutes = 0,
    this.formattedScreenTimeToday = '0.0 hrs',
    this.todayRouteKm = 0.0,
    this.todayMaxSpeedKmph = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'child_id': childId,
      'child_name': childName,
      'child_code': childCode,
      'auth_token': authToken,
      'avatar': avatar,
      'last_active_at': lastActiveAt.toIso8601String(),
      'age': age,
      'device_imei': deviceImei,
      'is_device_only': isDeviceOnly,
      'is_active': isActive,
      'screentime_today': {
        'total_minutes': screenTimeTodayMinutes,
        'formatted_total_time': formattedScreenTimeToday,
      },
      'today_route': {
        'total_distance_km': todayRouteKm,
        'max_speed_kmph': todayMaxSpeedKmph,
      },
    };
  }

  factory ChildProfile.fromMap(Map<String, dynamic> map) {
    final screentimeToday =
        map['screentime_today'] as Map<String, dynamic>? ?? const {};
    final todayRoute = map['today_route'] as Map<String, dynamic>? ?? const {};

    return ChildProfile(
      childCode: map['child_code'] ?? '',
      childId: map['child_id'] ?? '',
      childName: map['child_name'] ?? '',
      authToken: map['auth_token'] ?? '',
      avatar: map['avatar'],
      lastActiveAt: DateTime.parse(
        map['last_active_at'] ?? DateTime.now().toIso8601String(),
      ),
      age: map['age'] != null ? int.tryParse(map['age'].toString()) : null,
      deviceImei: map['device_imei'] as String?,
      isDeviceOnly: map['is_device_only'] == true,
      isActive: map['is_active'] == true,
      screenTimeTodayMinutes: safeToInt(screentimeToday['total_minutes']),
      formattedScreenTimeToday:
          (screentimeToday['formatted_total_time'] as String?) ?? '0.0 hrs',
      todayRouteKm: safeToDouble(todayRoute['total_distance_km']),
      todayMaxSpeedKmph: safeToDouble(todayRoute['max_speed_kmph']),
    );
  }

  String toJson() => json.encode(toMap());

  factory ChildProfile.fromJson(String source) =>
      ChildProfile.fromMap(json.decode(source));

  ChildProfile copyWith({
    String? childId,
    String? childName,
    String? authToken,
    String? avatar,
    String? childCode,
    DateTime? lastActiveAt,
    int? age,
    String? deviceImei,
    bool? isDeviceOnly,
    bool? isActive,
    int? screenTimeTodayMinutes,
    String? formattedScreenTimeToday,
    double? todayRouteKm,
    double? todayMaxSpeedKmph,
  }) {
    return ChildProfile(
      childCode: childCode ?? this.childCode,
      childId: childId ?? this.childId,
      childName: childName ?? this.childName,
      authToken: authToken ?? this.authToken,
      avatar: avatar ?? this.avatar,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      age: age ?? this.age,
      deviceImei: deviceImei ?? this.deviceImei,
      isDeviceOnly: isDeviceOnly ?? this.isDeviceOnly,
      isActive: isActive ?? this.isActive,
      screenTimeTodayMinutes:
          screenTimeTodayMinutes ?? this.screenTimeTodayMinutes,
      formattedScreenTimeToday:
          formattedScreenTimeToday ?? this.formattedScreenTimeToday,
      todayRouteKm: todayRouteKm ?? this.todayRouteKm,
      todayMaxSpeedKmph: todayMaxSpeedKmph ?? this.todayMaxSpeedKmph,
    );
  }
}
