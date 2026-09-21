class AppUsageResponse {
  final String userId;
  final int totalUsageTime;
  final String totalUsageTimeFormatted;
  final int totalApps;
  final Map<String, List<AppUsageItem>> dailyUsage;
  final List<AppUsageItem> summaryApps; // Added for the summary endpoint
  // Only populated by the summary endpoint (Week tab) — total usage for the
  // period immediately preceding the requested startDate/endDate range, of
  // the same length, so the UI can show a real "vs last week" comparison.
  final int? previousPeriodUsageTime;

  AppUsageResponse({
    required this.userId,
    required this.totalUsageTime,
    required this.totalUsageTimeFormatted,
    required this.totalApps,
    required this.dailyUsage,
    this.summaryApps = const [],
    this.previousPeriodUsageTime,
  });

  /// Helper to format seconds into "Xh Ym Zs"
  static String _formatSecs(int totalSeconds) {
    if (totalSeconds <= 0) return '0s';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  factory AppUsageResponse.fromJson(Map<String, dynamic> json) {
    Map<String, List<AppUsageItem>> dailyUsageMap = {};
    List<AppUsageItem> summaryList = [];
    int totalTime = 0;

    // Timeline format has "data": {"2026-03-06": [...]}
    if (json.containsKey('data') && json['data'] is Map) {
      final mapData = json['data'] as Map;
      mapData.forEach((key, value) {
        if (value is List) {
          dailyUsageMap[key.toString()] = value
              .map((e) => AppUsageItem.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      });
    }

    // Summary format has "apps": [...]
    if (json.containsKey('apps') && json['apps'] is List) {
      summaryList = (json['apps'] as List)
          .map((e) => AppUsageItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    totalTime = json['totalUsageTime'] ?? json['totalSeconds'] ?? 0;

    return AppUsageResponse(
      userId: json['userId'] ?? json['child_id'] ?? '',
      totalUsageTime: totalTime,
      totalUsageTimeFormatted:
          json['totalUsageTimeFormatted'] ?? _formatSecs(totalTime),
      totalApps: json['totalApps'] ?? 0,
      dailyUsage: dailyUsageMap,
      summaryApps: summaryList,
      previousPeriodUsageTime: json['previousPeriodUsageTime'] as int?,
    );
  }
}

class AppUsageItem {
  final String date;
  final String appName;
  final String packageName;
  final int usageTime;
  final String usageTimeFormatted;
  final String platform;
  final int openCount;
  final String? iconBase64;
  final String? iconUrl;
  final bool isLocked;

  AppUsageItem({
    required this.date,
    required this.appName,
    required this.packageName,
    required this.usageTime,
    required this.usageTimeFormatted,
    required this.platform,
    required this.openCount,
    this.iconBase64,
    this.iconUrl,
    this.isLocked = false,
  });

  factory AppUsageItem.fromJson(Map<String, dynamic> json) {
    final seconds =
        json['usageTime'] ?? json['totalUsageTime'] ?? json['seconds'] ?? 0;
    return AppUsageItem(
      date: json['date'] ?? '',
      appName: json['appName'] ?? json['packageName'] ?? '',
      packageName: json['packageName'] ?? '',
      usageTime: seconds,
      usageTimeFormatted:
          json['usageTimeFormatted'] ??
          json['totalUsageTimeFormatted'] ??
          AppUsageResponse._formatSecs(seconds),
      platform: json['platform'] ?? 'android',
      openCount: json['openCount'] ?? json['totalOpenCount'] ?? 0,
      iconUrl: json['icon'],
      isLocked: json['is_locked'] ?? false,
    );
  }
}
