import 'dart:io' show Platform;

import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';

enum RecoveryDecision {
  /// All preconditions hold — start the service.
  start,
  notAndroid,
  notChildDevice,
  noLocationPermission,

  /// Android 10+ without "Allow all the time": a background-started location
  /// service would not be allowed to read location, so don't pretend to recover.
  noBackgroundLocation,
  alreadyRunning,

  /// An attempt was made moments ago — avoids repeated starts / duplicate
  /// service notifications.
  recentAttempt,

  /// The start was requested but the OS refused (recorded, fallback remains).
  startFailed,
}

/// Pure decision for "should the high-accuracy foreground service be restarted
/// now?" from a context where Android permits starting it (high-priority FCM).
/// Mirrors android/.../TrackingRecovery.kt for the native triggers.
class TrackingRecoveryPolicy {
  const TrackingRecoveryPolicy._();

  /// Key in SharedPreferences written by the tracking isolate; the native layer
  /// reads it as `flutter.bg_alive_at`.
  static const aliveMarkerKey = 'bg_alive_at';
  static const aliveMarkerInterval = Duration(seconds: 45);
  static const minGapBetweenAttempts = Duration(seconds: 60);

  static RecoveryDecision decide({
    required bool isAndroid,
    required bool isChildDevice,
    required bool hasLocationPermission,
    required bool hasBackgroundLocation,
    required bool serviceRunning,
    required Duration? sinceLastAttempt,
  }) {
    if (!isAndroid) return RecoveryDecision.notAndroid;
    if (!isChildDevice) return RecoveryDecision.notChildDevice;
    if (!hasLocationPermission) return RecoveryDecision.noLocationPermission;
    if (!hasBackgroundLocation) return RecoveryDecision.noBackgroundLocation;
    if (serviceRunning) return RecoveryDecision.alreadyRunning;
    if (sinceLastAttempt != null && sinceLastAttempt < minGapBetweenAttempts) {
      return RecoveryDecision.recentAttempt;
    }
    return RecoveryDecision.start;
  }
}

/// Side-effecting inputs for [TrackingRecoveryPolicy], injectable for tests.
class TrackingRecoveryProbe {
  final bool isAndroid;
  final Future<bool> Function() isChildDevice;
  final Future<bool> Function() hasLocationPermission;
  final Future<bool> Function() hasBackgroundLocation;
  final Future<bool> Function() serviceRunning;
  final Future<void> Function() startService;

  const TrackingRecoveryProbe({
    required this.isAndroid,
    required this.isChildDevice,
    required this.hasLocationPermission,
    required this.hasBackgroundLocation,
    required this.serviceRunning,
    required this.startService,
  });

  factory TrackingRecoveryProbe.real() => TrackingRecoveryProbe(
    isAndroid: Platform.isAndroid,
    isChildDevice: () async {
      await SharedPrefsService.init();
      final prefs = SharedPrefsService();
      final childId = prefs.getString('child_id');
      return !prefs.isParent && childId != null && childId.isNotEmpty;
    },
    hasLocationPermission: () async =>
        await Permission.locationWhenInUse.isGranted ||
        await Permission.locationAlways.isGranted,
    hasBackgroundLocation: () async =>
        await Permission.locationAlways.isGranted,
    serviceRunning: () => FlutterBackgroundService().isRunning(),
    startService: () async {
      await FlutterBackgroundService().startService();
    },
  );
}
