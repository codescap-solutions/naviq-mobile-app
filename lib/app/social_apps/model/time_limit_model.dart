// Models for the daily app time-limit and ask-for-more-time APIs.

class AppTimeLimitItem {
  final String packageName;
  final String appName;
  final int dailyLimitMinutes;
  final DateTime? graceUntil;

  AppTimeLimitItem({
    required this.packageName,
    required this.appName,
    required this.dailyLimitMinutes,
    this.graceUntil,
  });

  factory AppTimeLimitItem.fromJson(Map<String, dynamic> json) {
    return AppTimeLimitItem(
      packageName: json['package_name'] ?? '',
      appName: json['app_name'] ?? json['package_name'] ?? '',
      dailyLimitMinutes: json['daily_limit_minutes'] ?? 0,
      graceUntil: json['grace_until'] != null
          ? DateTime.tryParse(json['grace_until'])
          : null,
    );
  }
}

class TimeExtensionRequestItem {
  final String id;
  final String childId;
  final String packageName;
  final String appName;
  final int requestedMinutes;
  final String status;
  final DateTime createdAt;

  /// 'locked' (parent locked the app outright) or 'time_limit'.
  final String reason;

  TimeExtensionRequestItem({
    required this.id,
    required this.childId,
    required this.packageName,
    required this.appName,
    required this.requestedMinutes,
    required this.status,
    required this.createdAt,
    this.reason = 'time_limit',
  });

  factory TimeExtensionRequestItem.fromJson(Map<String, dynamic> json) {
    return TimeExtensionRequestItem(
      id: json['_id'] ?? '',
      childId: json['child_id'] ?? '',
      packageName: json['package_name'] ?? '',
      appName: json['app_name'] ?? json['package_name'] ?? '',
      requestedMinutes: json['requested_minutes'] ?? 15,
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
      reason: json['reason'] ?? 'time_limit',
    );
  }
}
