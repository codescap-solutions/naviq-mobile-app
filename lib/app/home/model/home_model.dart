import 'package:child_track/app/home/model/device_model.dart';
import 'package:child_track/app/home/model/location_info_model.dart';
import 'package:child_track/app/home/model/last_trip_model.dart';
import 'package:child_track/app/home/model/yesterday_trip_summary_model.dart';
import 'package:child_track/app/home/model/cards_model.dart';
import 'package:child_track/core/utils/parser_utils.dart';

// ─── Active Trip ─────────────────────────────────────────────────────────────
class ActiveTrip {
  final bool isActive;
  final String? tripId;
  final String? tripStatus;
  final String? activity;
  final DateTime? startedAt;
  final int durationSeconds;
  final double distanceMeters;

  const ActiveTrip({
    required this.isActive,
    this.tripId,
    this.tripStatus,
    this.activity,
    this.startedAt,
    this.durationSeconds = 0,
    this.distanceMeters = 0.0,
  });

  factory ActiveTrip.fromJson(Map<String, dynamic> json) {
    return ActiveTrip(
      isActive: json['is_active'] as bool? ?? false,
      tripId: json['trip_id'] as String?,
      tripStatus: json['trip_status'] as String?,
      activity: json['activity'] as String?,
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String)
          : null,
      durationSeconds: safeToInt(json['duration_seconds']),
      distanceMeters: safeToDouble(json['distance_m']),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────

class FeatureSummary {
  final int lockedAppsCount;
  final String scrollStatusText;
  final int activeFencesCount;
  final String geoGuardStatusText;

  FeatureSummary({
    required this.lockedAppsCount,
    required this.scrollStatusText,
    required this.activeFencesCount,
    required this.geoGuardStatusText,
  });

  factory FeatureSummary.fromJson(Map<String, dynamic> json) {
    final scrollJson = json['scroll'] ?? {};
    final geoJson = json['geo_guard'] ?? {};
    return FeatureSummary(
      lockedAppsCount: safeToInt(scrollJson['locked_apps_count']),
      scrollStatusText: scrollJson['status_text'] ?? '',
      activeFencesCount: safeToInt(geoJson['active_fences_count']),
      geoGuardStatusText: geoJson['status_text'] ?? '',
    );
  }
}

class TimelineNode {
  final String label;
  final String time;
  final bool isActive;

  /// Coordinates of the stop (null on older servers). Used to resolve a name
  /// on-device when [label] is the server's "Unknown Location" placeholder.
  final double? lat;
  final double? lng;

  TimelineNode({
    required this.label,
    required this.time,
    required this.isActive,
    this.lat,
    this.lng,
  });

  factory TimelineNode.fromJson(Map<String, dynamic> json) {
    return TimelineNode(
      label: json['label'] ?? '',
      time: json['time'] ?? '',
      isActive: json['is_active'] ?? false,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }
}

class RouteMapSummary {
  final double totalDistanceKm;
  final int newLocationsCount;
  final List<TimelineNode> timeline;

  RouteMapSummary({
    required this.totalDistanceKm,
    required this.newLocationsCount,
    required this.timeline,
  });

  factory RouteMapSummary.fromJson(Map<String, dynamic> json) {
    final list = json['timeline'] as List<dynamic>? ?? [];
    return RouteMapSummary(
      totalDistanceKm: safeToDouble(json['total_distance_km']),
      newLocationsCount: safeToInt(json['new_locations_count']),
      timeline: list
          .map((e) => TimelineNode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AppUsage {
  final String appName;
  final String appIcon;
  final String usageDuration;
  final int usageMinutes;
  final String brandColor;

  AppUsage({
    required this.appName,
    required this.appIcon,
    required this.usageDuration,
    required this.usageMinutes,
    required this.brandColor,
  });

  factory AppUsage.fromJson(Map<String, dynamic> json) {
    return AppUsage(
      appName: json['app_name'] ?? '',
      appIcon: json['appIcon'] ?? '',
      usageDuration: json['usage_duration'] ?? '',
      usageMinutes: safeToInt(json['usage_minutes']),
      brandColor: json['brand_color'] ?? '',
    );
  }
}

class ScreentimeTodaySummary {
  final int totalMinutes;
  final String formattedTotalTime;
  final int dailyLimitMinutes;
  final bool limitExceeded;
  final String limitMessage;
  final List<AppUsage> appUsages;

  ScreentimeTodaySummary({
    required this.totalMinutes,
    required this.formattedTotalTime,
    required this.dailyLimitMinutes,
    required this.limitExceeded,
    required this.limitMessage,
    required this.appUsages,
  });

  factory ScreentimeTodaySummary.fromJson(Map<String, dynamic> json) {
    final list = json['app_usages'] as List<dynamic>? ?? [];
    return ScreentimeTodaySummary(
      totalMinutes: safeToInt(json['total_minutes']),
      formattedTotalTime: json['formatted_total_time'] ?? '',
      dailyLimitMinutes: safeToInt(json['daily_limit_minutes']),
      limitExceeded: json['limit_exceeded'] ?? false,
      limitMessage: json['limit_message'] ?? '',
      appUsages: list
          .map((e) => AppUsage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class HomeResponse {
  final String? childName;
  final String? childCode;
  final String? childAvatar;
  final bool webFilteringEnabled;
  final DeviceInfo deviceInfo;
  final LocationInfo currentLocation;
  final YesterdayTripSummary? yesterdayTripSummary;
  final Cards? cards;
  final List<TripSegment> yesterdayTrips;

  final FeatureSummary? features;
  final RouteMapSummary? todayRoute;
  final ScreentimeTodaySummary? screentimeToday;

  final List<SharedChild>? sharedChildren;

  // Live trip currently in progress
  final ActiveTrip? activeTrip;

  HomeResponse({
    this.childName,
    this.childCode,
    this.childAvatar,
    this.webFilteringEnabled = false,
    required this.deviceInfo,
    required this.currentLocation,
    this.yesterdayTripSummary,
    this.cards,
    this.yesterdayTrips = const [],
    this.features,
    this.todayRoute,
    this.screentimeToday,
    this.sharedChildren,
    this.activeTrip,
  });

  factory HomeResponse.fromJson(Map<String, dynamic> json) {
    final sharedList = json['shared_children'] as List<dynamic>? ?? [];
    return HomeResponse(
      childName: json['child_name'] as String?,
      childCode: json['child_code'] as String?,
      childAvatar: (json['child_avatar'] ?? json['avatar']) as String?,
      webFilteringEnabled: json['web_filtering_enabled'] ?? false,
      deviceInfo: DeviceInfo.fromJson(json['device_info'] ?? {}),
      currentLocation: LocationInfo.fromJson(
        json['current_location'] ?? json['location'] ?? {},
      ),
      yesterdayTripSummary: json['yesterday_trip_summary'] != null
          ? YesterdayTripSummary.fromJson(
              json['yesterday_trip_summary'] as Map<String, dynamic>,
            )
          : null,
      cards: json['cards'] != null
          ? Cards.fromJson(json['cards'] as Map<String, dynamic>)
          : null,
      yesterdayTrips:
          json['yesterday_trip_summary'] != null &&
              json['yesterday_trip_summary'] is List
          ? (json['yesterday_trip_summary'] as List<dynamic>)
                .map(
                  (trip) => TripSegment.fromJson(trip as Map<String, dynamic>),
                )
                .toList()
          : [],
      features: json['features'] != null
          ? FeatureSummary.fromJson(json['features'] as Map<String, dynamic>)
          : null,
      todayRoute: json['today_route'] != null
          ? RouteMapSummary.fromJson(
              json['today_route'] as Map<String, dynamic>,
            )
          : null,
      screentimeToday: json['screentime_today'] != null
          ? ScreentimeTodaySummary.fromJson(
              json['screentime_today'] as Map<String, dynamic>,
            )
          : null,
      sharedChildren: sharedList
          .map((e) => SharedChild.fromJson(e as Map<String, dynamic>))
          .toList(),
      activeTrip: json['active_trip'] != null
          ? ActiveTrip.fromJson(json['active_trip'] as Map<String, dynamic>)
          : null,
    );
  }
}

class SharedChild {
  final String shareId;
  final String childId;
  final String childName;
  final double latitude;
  final double longitude;
  final int batteryPercentage;
  final DateTime? lastSyncAt;
  final String? avatar;
  final DateTime? expiresAt;

  SharedChild({
    required this.shareId,
    required this.childId,
    required this.childName,
    required this.latitude,
    required this.longitude,
    required this.batteryPercentage,
    this.lastSyncAt,
    this.avatar,
    this.expiresAt,
  });

  factory SharedChild.fromJson(Map<String, dynamic> json) {
    return SharedChild(
      shareId: json['share_id']?.toString() ?? json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name']?.toString() ?? '',
      latitude: safeToDouble(json['latitude'] ?? json['lat']),
      longitude: safeToDouble(json['longitude'] ?? json['lng']),
      batteryPercentage: safeToInt(
        json['battery_percentage'] ?? json['battery'],
      ),
      lastSyncAt: json['last_sync_at'] != null
          ? DateTime.tryParse(json['last_sync_at'])
          : null,
      avatar: (json['avatar'] ?? json['child_avatar'])?.toString(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'])
          : null,
    );
  }
}
