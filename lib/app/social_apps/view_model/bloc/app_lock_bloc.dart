import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/app/social_apps/model/locked_app_model.dart';
import 'package:child_track/app/social_apps/view_model/app_lock_repository.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/services/lock_sync_service.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'app_lock_event.dart';
import 'app_lock_state.dart';

class AppLockBloc extends Bloc<AppLockEvent, AppLockState> {
  final LockSyncService _lockSyncService;
  final AppLockRepository _repository;
  final SharedPrefsService _prefs;

  /// Keeps the full model list for parent-side PUT requests.
  List<LockedPackageItem> _lockedItems = [];

  bool get _isParent => _prefs.getString('parent_id') != null;

  AppLockBloc({
    required LockSyncService lockSyncService,
    required AppLockRepository repository,
    required SharedPrefsService sharedPrefsService,
  }) : _lockSyncService = lockSyncService,
       _repository = repository,
       _prefs = sharedPrefsService,
       super(AppLockInitial()) {
    on<CheckAccessibilityPermission>(_onCheckAccessibilityPermission);
    on<OpenAccessibilitySettings>(_onOpenAccessibilitySettings);
    on<FetchLockedApps>(_onFetchLockedApps);
    on<SyncLockedAppsFromServer>(_onSyncLockedAppsFromServer);
    on<ToggleAppLock>(_onToggleAppLock);
    on<UpdateLockedApps>(_onUpdateLockedApps);
    on<BlockAllApps>(_onBlockAllApps);
  }

  // ─── Permission Handlers ───

  Future<void> _onCheckAccessibilityPermission(
    CheckAccessibilityPermission event,
    Emitter<AppLockState> emit,
  ) async {
    final hasPermission = await _lockSyncService.checkAccessibilityPermission();
    if (state is AppLockLoaded) {
      emit(
        (state as AppLockLoaded).copyWith(
          hasAccessibilityPermission: hasPermission,
        ),
      );
    } else {
      emit(AppLockLoaded(hasAccessibilityPermission: hasPermission));
    }
  }

  Future<void> _onOpenAccessibilitySettings(
    OpenAccessibilitySettings event,
    Emitter<AppLockState> emit,
  ) async {
    await _lockSyncService.openAccessibilitySettings();
  }

  // ─── Fetch Locked Apps (initial load) ───

  Future<void> _onFetchLockedApps(
    FetchLockedApps event,
    Emitter<AppLockState> emit,
  ) async {
    emit(AppLockLoading());
    try {
      if (_isParent) {
        await _fetchParentLockedApps(emit);
      } else {
        await _fetchChildLockedApps(emit);
      }
    } catch (e) {
      AppLogger.error('FetchLockedApps error: $e');
      emit(AppLockError('Failed to fetch locked apps: $e'));
    }
  }

  Future<void> _fetchParentLockedApps(Emitter<AppLockState> emit) async {
    final childId =
        _prefs.getString('selected_child_id') ??
        _prefs.getString('child_id') ??
        '';
    if (childId.isEmpty) {
      emit(const AppLockLoaded());
      return;
    }

    final response = await _repository.getLockedApps(childId: childId);
    if (response.isSuccess && response.data != null) {
      _lockedItems = response.data!.lockedPackages;
      final packageSet = _lockedItems.map((e) => e.packageName).toSet();
      emit(AppLockLoaded(lockedPackages: packageSet));
    } else {
      emit(AppLockError(response.message));
    }
  }

  Future<void> _fetchChildLockedApps(Emitter<AppLockState> emit) async {
    final response = await _repository.getChildLockedApps();
    if (response.isSuccess && response.data != null) {
      _lockedItems = response.data!.lockedPackages;
      final packageSet = _lockedItems.map((e) => e.packageName).toSet();

      emit(AppLockLoaded(lockedPackages: packageSet));

      // On the child device, sync to native AccessibilityService
      await _lockSyncService.syncLockedAppsToNative(packageSet.toList());
    } else {
      emit(AppLockError(response.message));
    }
  }

  // ─── FCM-triggered Sync (child only) ───

  Future<void> _onSyncLockedAppsFromServer(
    SyncLockedAppsFromServer event,
    Emitter<AppLockState> emit,
  ) async {
    // Re-fetch from child endpoint and sync to native
    await _fetchChildLockedApps(emit);
  }

  // ─── Toggle App Lock (parent side — calls POST lock-apps / unlock-apps) ───

  Future<void> _onToggleAppLock(
    ToggleAppLock event,
    Emitter<AppLockState> emit,
  ) async {
    final currentState = state is AppLockLoaded
        ? state as AppLockLoaded
        : const AppLockLoaded();

    final newLockedPackages = Set<String>.from(currentState.lockedPackages);

    // Optimistic UI update
    if (event.isLocked) {
      newLockedPackages.add(event.packageName);
    } else {
      newLockedPackages.remove(event.packageName);
    }

    emit(currentState.copyWith(lockedPackages: newLockedPackages));

    if (_isParent) {
      final childId =
          _prefs.getString('selected_child_id') ??
          _prefs.getString('child_id') ??
          '';
      if (childId.isEmpty) return;

      // Determine platform from the package name pattern
      final platform =
          event.packageName.startsWith('usage_cat_') ||
              event.packageName.startsWith('usage_app_')
          ? 'ios'
          : 'android';

      BaseResponse response;
      if (event.isLocked) {
        response = await _repository.lockApps(
          childId: childId,
          tokens: [event.packageName],
          platform: platform,
          durationMinutes: event.durationMinutes,
        );
      } else {
        response = await _repository.unlockApps(
          childId: childId,
          tokens: [event.packageName],
          platform: platform,
        );
      }

      if (response.isSuccess) {
        AppLogger.info('${event.isLocked ? "Lock" : "Unlock"} API success');
        // Re-fetch to get server-canonical state
        await _fetchParentLockedApps(emit);
      } else {
        // Revert optimistic update
        AppLogger.error(
          'Failed to ${event.isLocked ? "lock" : "unlock"} apps: ${response.message}',
        );
        if (event.isLocked) {
          newLockedPackages.remove(event.packageName);
        } else {
          newLockedPackages.add(event.packageName);
        }
        emit(currentState.copyWith(lockedPackages: newLockedPackages));
      }
    } else {
      // Child device — sync directly to native (local toggle, e.g., testing)
      await _lockSyncService.syncLockedAppsToNative(newLockedPackages.toList());
    }
  }

  // ─── Bulk Update (e.g., from external push) ───

  Future<void> _onUpdateLockedApps(
    UpdateLockedApps event,
    Emitter<AppLockState> emit,
  ) async {
    final newSet = event.lockedPackages.toSet();
    if (state is AppLockLoaded) {
      emit((state as AppLockLoaded).copyWith(lockedPackages: newSet));
    } else {
      emit(AppLockLoaded(lockedPackages: newSet));
    }
    await _lockSyncService.syncLockedAppsToNative(event.lockedPackages);
  }

  // ─── Block All Apps (parent side) ───

  Future<void> _onBlockAllApps(
    BlockAllApps event,
    Emitter<AppLockState> emit,
  ) async {
    if (!_isParent) return;
    final childId =
        _prefs.getString('selected_child_id') ??
        _prefs.getString('child_id') ??
        '';
    if (childId.isEmpty || event.packageNames.isEmpty) return;

    // Optimistically mark all as locked
    final currentState = state is AppLockLoaded
        ? state as AppLockLoaded
        : const AppLockLoaded();
    final optimistic = Set<String>.from(currentState.lockedPackages)
      ..addAll(event.packageNames);
    emit(currentState.copyWith(lockedPackages: optimistic));

    // Split by platform (Android vs iOS tokens)
    final androidPkgs = event.packageNames
        .where(
          (p) => !p.startsWith('usage_cat_') && !p.startsWith('usage_app_'),
        )
        .toList();
    final iosPkgs = event.packageNames
        .where((p) => p.startsWith('usage_cat_') || p.startsWith('usage_app_'))
        .toList();

    try {
      if (androidPkgs.isNotEmpty) {
        await _repository.lockApps(
          childId: childId,
          tokens: androidPkgs,
          platform: 'android',
          durationMinutes: event.durationMinutes,
        );
        AppLogger.info('BlockAll: locked ${androidPkgs.length} Android apps');
      }
      if (iosPkgs.isNotEmpty) {
        await _repository.lockApps(
          childId: childId,
          tokens: iosPkgs,
          platform: 'ios',
          durationMinutes: event.durationMinutes,
        );
        AppLogger.info('BlockAll: locked ${iosPkgs.length} iOS apps');
      }
    } catch (e) {
      AppLogger.error('BlockAll error: $e');
    }

    // Re-fetch canonical server state
    await _fetchParentLockedApps(emit);
  }
}
