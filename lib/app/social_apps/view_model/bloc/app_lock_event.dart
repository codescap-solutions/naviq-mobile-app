import 'package:equatable/equatable.dart';

abstract class AppLockEvent extends Equatable {
  const AppLockEvent();

  @override
  List<Object> get props => [];
}

class CheckAccessibilityPermission extends AppLockEvent {}

class OpenAccessibilitySettings extends AppLockEvent {}

/// Fetches locked apps from the backend (parent or child endpoint).
class FetchLockedApps extends AppLockEvent {}

/// Triggered by SYNC_LOCKED_APPS FCM push on the child device.
class SyncLockedAppsFromServer extends AppLockEvent {}

class ToggleAppLock extends AppLockEvent {
  final String packageName;
  final String appName;
  final bool isLocked;
  final int durationMinutes;

  const ToggleAppLock({
    required this.packageName,
    this.appName = '',
    required this.isLocked,
    this.durationMinutes = 0,
  });

  @override
  List<Object> get props => [packageName, appName, isLocked, durationMinutes];
}

class UpdateLockedApps extends AppLockEvent {
  final List<String> lockedPackages;

  const UpdateLockedApps(this.lockedPackages);

  @override
  List<Object> get props => [lockedPackages];
}

/// Locks every package in [packageNames] with an optional duration.
class BlockAllApps extends AppLockEvent {
  final List<String> packageNames;
  final int durationMinutes;

  const BlockAllApps({required this.packageNames, this.durationMinutes = 0});

  @override
  List<Object> get props => [packageNames, durationMinutes];
}
