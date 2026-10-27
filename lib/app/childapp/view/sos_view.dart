import 'package:child_track/app/childapp/view/widgets/clock_skew_banner.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:child_track/core/services/device_info_service.dart';
import 'package:flutter/services.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/app/childapp/view_model/repository/logout_request_repository.dart';
import 'package:child_track/app/home/model/device_model.dart';
import 'package:child_track/app/childapp/view_model/bloc/child_bloc.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:child_track/core/services/lock_sync_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/services/socket_service.dart';
import 'package:child_track/core/services/background_location_service.dart';
import 'package:child_track/core/services/csv_file_logger.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:child_track/core/utils/log_share_helper.dart';
import 'package:child_track/app/childapp/view_model/repository/device_info_service.dart'
    as child_info;
import 'package:child_track/app/childapp/view/widgets/child_app_drawer.dart';
import 'package:child_track/app/auth/view/onboarding/app_catalog_screen.dart';
import 'package:child_track/app/auth/view/onboarding/oem_battery_screen.dart';
import 'package:child_track/core/services/oem_battery_helper.dart';
import 'package:child_track/core/services/location_service.dart';

class SosView extends StatefulWidget {
  const SosView({super.key});

  @override
  State<SosView> createState() => _SosViewState();
}

class _SosViewState extends State<SosView> with WidgetsBindingObserver {
  late final ChildBloc _childBloc;
  bool _hasAccessibilityPermission = false;
  bool _hasLocationPermission = false;
  bool _hasNotificationPermission = false;
  bool _hasBackgroundPermission = false;
  OemInfo? _oemBannerInfo;
  // "Allow all the time" location — distinct from _hasBackgroundPermission
  // above (which only checks battery-optimization exemption). Native
  // geofencing needs this specifically; see LocationService
  // .getBackgroundLocationStatus for the incident this closes the loop on.
  bool _showBackgroundLocationBanner = false;
  // Standard (non-OEM) battery-optimization exemption — was only ever
  // surfaced as a checklist row deep in the permissions section
  // (_buildPermissionItem('Background Work', ...) below), never as a
  // persistent nudge like the OEM and "allow all the time" cases get,
  // despite being the actual prerequisite those two build on top of
  // (OemBatteryHelper's own doc comment: OEM managers restrict background
  // work "even after" this exemption is granted — i.e. this one has to be
  // right first). permission_sequence_screen.dart's onboarding step also
  // never checks whether the request was actually granted before advancing
  // (auto-advances either way, "non-blocking" by design), so a device that
  // denied it at onboarding had nothing catching that afterward until this.
  // Same dismiss-only-for-this-session pattern as the other banners below.
  bool _showBatteryOptimizationBanner = false;

  @override
  void initState() {
    super.initState();
    _childBloc = injector<ChildBloc>();
    WidgetsBinding.instance.addObserver(this);
    _checkAccessibilityPermission();
    _checkOtherPermissions();
    _checkOemBatteryStatus();
    _checkBackgroundLocationStatus();

    // Defer heavy initialization until after the first frame to ensure smooth navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _childBloc.onInitialize();
      // Start background location service
      BackgroundLocationService().start();
      // Fetch and sync locked apps from server to native AppLockService
      injector<LockSyncService>().fetchAndSyncLockedApps();

      // PROMINENT DISCLOSURE (Google Play Accessibility API Policy)
      // Automatically show disclosure on first launch if Accessibility is not yet enabled.
      // This ensures reviewers see it without needing to tap "Enable" themselves.
      _showAccessibilityDisclosureIfNeeded().then(
        (_) => _showLocationPermissionDialogIfNeeded(),
      );
    });
  }

  /// Location is no longer an onboarding step; ask for "Always" here instead.
  Future<void> _showLocationPermissionDialogIfNeeded() async {
    if (!mounted) return;
    final service = LocationService();
    if (await service.getBackgroundLocationStatus() != 'denied') return;
    if (!mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location access needed'),
        content: const Text(
          'Allow location "Always" so your parents can see you are safe, '
          'even when the app is closed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow != true) return;
    final result = await service.requestAlwaysAllowPermission();
    if (result['granted'] != true) await service.openLocationSettings();
    _checkOtherPermissions();
    _checkBackgroundLocationStatus();
  }

  /// Show the Accessibility Service prominent disclosure automatically
  /// on first load if the permission is not yet granted.
  Future<void> _showAccessibilityDisclosureIfNeeded() async {
    if (Platform.isIOS) {
      // iOS FamilyControls' AuthorizationCenter.shared.authorizationStatus
      // can read back stale (.notDetermined/.denied) for a moment right
      // after a cold launch, before the framework finishes syncing with the
      // system Screen Time daemon — even when the child already granted
      // access. Reported live: the disclosure re-appeared on every app
      // open despite Screen Time being enabled. Give it a moment, then
      // confirm with a second read before disturbing the user, instead of
      // trusting a single check taken right on process start.
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
    }

    var hasPermission = await injector<LockSyncService>()
        .checkAccessibilityPermission();
    if (!hasPermission && Platform.isIOS) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      hasPermission = await injector<LockSyncService>()
          .checkAccessibilityPermission();
    }

    if (!hasPermission && mounted) {
      // Small delay so the screen settles before the dialog appears
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        await showAccessibilityDisclosure(context);
        // Re-check permission state after dialog is dismissed
        _checkAccessibilityPermission();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.info('SosView: Lifecycle state changed to $state');
    if (state == AppLifecycleState.resumed) {
      AppLogger.info('SosView: App resumed, checking permission status...');
      // Re-sync locked apps from server. This is critical because:
      // - The FCM background handler runs in a separate Dart isolate
      //   where MethodChannel to AppLockService doesn't work.
      // - So if the parent unlocked an app while we were in background,
      //   the lock list was fetched but couldn't be sent to native.
      // - This call runs in the main isolate where the channel works.
      injector<LockSyncService>().fetchAndSyncLockedApps();
      // Check permission once with a small delay instead of polling 5 times
      // This significantly reduces the number of expensive native calls
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          AppLogger.info('SosView: Checking usage permission');
          _childBloc.add(CheckUsagePermission());
          _checkAccessibilityPermission();
          _checkOtherPermissions();
          _checkOemBatteryStatus();
          _checkBackgroundLocationStatus();
        }
      });
    }
  }

  Future<void> _checkAccessibilityPermission() async {
    final hasPermission = await injector<LockSyncService>()
        .checkAccessibilityPermission();
    if (mounted) {
      setState(() {
        _hasAccessibilityPermission = hasPermission;
      });
    }
  }

  Future<void> _checkOtherPermissions() async {
    final locStatus = await Geolocator.checkPermission();
    // Permission grant alone doesn't mean location actually works — the child
    // can grant permission once and later flip the OS-level location-services
    // toggle off without ever touching the permission itself. Both must hold
    // for this status to honestly read as "enabled".
    final locServiceEnabled = await Geolocator.isLocationServiceEnabled();
    final notifStatus = await Permission.notification.status;
    final bgStatus = Platform.isAndroid
        ? await Permission.ignoreBatteryOptimizations.status
        : PermissionStatus.granted;

    if (mounted) {
      setState(() {
        _hasLocationPermission =
            (locStatus == LocationPermission.always ||
                locStatus == LocationPermission.whileInUse) &&
            locServiceEnabled;
        _hasNotificationPermission =
            notifStatus.isGranted ||
            (Platform.isIOS && notifStatus.isProvisional);
        _hasBackgroundPermission = Platform.isAndroid
            ? bgStatus.isGranted
            : true;
        // Same recompute-on-every-check pattern as the other banners — a
        // dismiss only lasts until the next resume/recheck, not persisted.
        _showBatteryOptimizationBanner =
            Platform.isAndroid && !_hasBackgroundPermission;
      });
    }
  }

  // Non-blocking nudge, not a permission gate — re-checked on every cold
  // start and app resume so a skipped/not-yet-done OEM whitelist step
  // keeps surfacing instead of being silently forgotten, without ever
  // blocking use of the app. Not shown at all once the onboarding step (or
  // this same banner) has been explicitly acknowledged as done.
  Future<void> _checkOemBatteryStatus() async {
    final helper = OemBatteryHelper();
    if (helper.isAcknowledged) {
      if (mounted && _oemBannerInfo != null)
        setState(() => _oemBannerInfo = null);
      return;
    }
    final oem = await helper.detectOem();
    if (mounted) setState(() => _oemBannerInfo = oem);
  }

  // Non-blocking nudge for "Allow all the time" / "Always Allow" location —
  // same re-check-on-resume, never-block pattern as the OEM banner above.
  // Used to skip iOS entirely on the assumption that
  // permission_sequence_screen's onboarding flow already drove the child to
  // LocationPermission.always there, making a repeat nudge unnecessary
  // noise over Apple's own one-time dialog. Confirmed wrong two ways: that
  // onboarding step's own silent recheck used to accept 'While Using' as
  // good enough (see its fix), so a child could reach this screen without
  // Always at all — and even with the onboarding gap closed, nothing
  // stopped the child from later downgrading it back to While Using (or
  // denying it) from iOS Settings, with no in-app screen ever catching
  // that regression. getBackgroundLocationStatus() already had a correct
  // iOS branch (LocationPermission.always check) from the start; only this
  // early-return kept it from ever running.
  Future<void> _checkBackgroundLocationStatus() async {
    final status = await LocationService().getBackgroundLocationStatus();
    if (mounted) {
      setState(() => _showBackgroundLocationBanner = status == 'denied');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _childBloc,
      child: Stack(
        children: [
          _SosViewContent(
            hasAccessibilityPermission: _hasAccessibilityPermission,
            hasLocationPermission: _hasLocationPermission,
            hasNotificationPermission: _hasNotificationPermission,
            hasBackgroundPermission: _hasBackgroundPermission,
            onPermissionUpdated: () {
              _checkAccessibilityPermission();
              _checkOtherPermissions();
            },
          ),
          if (_oemBannerInfo != null)
            _OemBatteryBanner(
              oem: _oemBannerInfo!,
              // Dismissing only hides it for this app session — deliberately
              // NOT the same as markAcknowledged(), so it comes back on the
              // next cold start until the user actually resolves it (or the
              // onboarding screen's "I've done this" explicitly clears it).
              onDismiss: () => setState(() => _oemBannerInfo = null),
            ),
          if (_showBackgroundLocationBanner)
            _BackgroundLocationBanner(
              // Stacks below the OEM banner (~56px) when both are relevant
              // rather than overlapping it.
              topExtra: _oemBannerInfo != null ? 56 : 0,
              onDismiss: () =>
                  setState(() => _showBackgroundLocationBanner = false),
            ),
          if (_showBatteryOptimizationBanner)
            _BatteryOptimizationBanner(
              // Stacks below whichever of the OEM / "allow all the time"
              // banners are also showing (~56px each).
              topExtra:
                  (_oemBannerInfo != null ? 56 : 0) +
                  (_showBackgroundLocationBanner ? 56 : 0),
              onDismiss: () =>
                  setState(() => _showBatteryOptimizationBanner = false),
            ),
          // Not dismissible: a wrong clock stops location sharing entirely, and
          // the banner removes itself once the server accepts a live point.
          ClockSkewBanner(
            topExtra:
                (_oemBannerInfo != null ? 56 : 0) +
                (_showBackgroundLocationBanner ? 56 : 0) +
                (_showBatteryOptimizationBanner ? 56 : 0),
          ),
        ],
      ),
    );
  }
}

class _OemBatteryBanner extends StatelessWidget {
  final OemInfo oem;
  final VoidCallback onDismiss;

  const _OemBatteryBanner({required this.oem, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1EE),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFE5DE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.battery_alert_rounded,
                color: Color(0xFFF97316),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Finish setup for ${oem.displayName} so tracking keeps working in the background',
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C2D12),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await navigator.push(
                    MaterialPageRoute(
                      builder: (_) => OemBatteryScreen(
                        oem: oem,
                        onContinue: (_) => navigator.maybePop(),
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Fix',
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF97316),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Nudges the user to upgrade location from "While using the app" to
// "Allow all the time" — required for native OS-level geofencing
// (Android GeofencingClient) to keep detecting safe-place arrivals/exits
// when this app is backgrounded or killed. Without it, geofence events
// only get caught by the much slower periodic location-point fallback
// (see location.controller.js / geofence.service.js checkGeofencesBatch),
// which is what a real incident traced this exact gap to — two devices
// with foreground location already "granted" and OEM battery whitelisting
// already done, where every notification for months still came in 5-30
// minutes late because "Allow all the time" was never actually confirmed.
class _BackgroundLocationBanner extends StatelessWidget {
  final double topExtra;
  final VoidCallback onDismiss;

  const _BackgroundLocationBanner({
    required this.topExtra,
    required this.onDismiss,
  });

  Future<void> _openSettings() async {
    // openAppSettings() (permission_handler) is cross-platform: on Android
    // there's no single documented intent that jumps straight into the
    // granular Location permission sub-page across every OEM/API level, so
    // the App Info page is the one portable, always-resolvable route, one
    // tap from Permissions → Location → "Allow all the time". On iOS it
    // opens this app's own Settings page directly, one tap from
    // Location → "Always".
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8 + topExtra,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDBEAFE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF2563EB),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  // Match each OS's own permission-dialog label exactly —
                  // Android's is "Allow all the time", iOS's is "Always" /
                  // "Always Allow". Telling an iOS child to look for text
                  // that doesn't exist on their Settings screen is exactly
                  // the kind of gap that makes a nudge get ignored.
                  Platform.isIOS
                      ? 'Turn on "Always Allow" location for instant safe-place alerts'
                      : 'Turn on "Allow all the time" location for instant safe-place alerts',
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _openSettings,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Fix',
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatteryOptimizationBanner extends StatelessWidget {
  final double topExtra;
  final VoidCallback onDismiss;

  const _BatteryOptimizationBanner({
    required this.topExtra,
    required this.onDismiss,
  });

  Future<void> _requestExemption() async {
    // Same call the onboarding step and the permissions-checklist row use —
    // just re-requesting the standard system dialog directly, no settings
    // deep-link needed for this one (unlike OEM autostart managers, this is
    // a plain OS permission with its own system prompt).
    await Permission.ignoreBatteryOptimizations.request();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8 + topExtra,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDBEAFE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.battery_alert_rounded,
                color: Color(0xFF2563EB),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Turn off battery optimization so tracking keeps working in the background',
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _requestExemption,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Fix',
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// PROMINENT DISCLOSURE — Accessibility Service (Google Play Policy)
// Top-level function so it can be called from both _SosViewState (auto-show
// on first load) and _SosViewContent (on "Enable" tap).
// -------------------------------------------------------------------------
Future<void> showAccessibilityDisclosure(BuildContext context) async {
  final bool? agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(AppSizes.spacingL),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              Container(
                padding: const EdgeInsets.all(AppSizes.spacingM),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.accessibility_new_rounded,
                  color: AppColors.primaryColor,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSizes.spacingM),

              // Title
              Text(
                'Accessibility Service',
                textAlign: TextAlign.center,
                style: FigmaText.dialogTitle,
              ),
              const SizedBox(height: AppSizes.spacingS),

              // Intro
              Text(
                'NaviQ requires Accessibility permissions for two core parental control features to keep your child safe.',
                textAlign: TextAlign.center,
                style: FigmaText.dialogBody,
              ),
              const SizedBox(height: AppSizes.spacingL),

              // Feature 1: App Blocking
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.app_blocking_rounded,
                      color: AppColors.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSizes.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('App Blocking', style: FigmaText.dialogAction),
                        const SizedBox(height: 4),
                        Text(
                          'Detects which app is on screen and blocks restricted apps to enforce limits.',
                          style: FigmaText.dialogBody,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.spacingM),

              // Feature 2: Web Filtering
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.public_off_rounded,
                      color: AppColors.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSizes.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Web Filtering', style: FigmaText.dialogAction),
                        const SizedBox(height: 4),
                        Text(
                          'Reads website URLs in the browser to block 18+ and adult content.',
                          style: FigmaText.dialogBody,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.spacingL),

              // Privacy Note
              Container(
                padding: const EdgeInsets.all(AppSizes.spacingS),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.privacy_tip_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSizes.spacingS),
                    Expanded(
                      child: Text(
                        'NaviQ strictly uses this for safety. We do NOT read or transmit personal messages or passwords.',
                        style: FigmaText.dialogBody,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.spacingL),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSizes.spacingM,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                      ),
                      child: Text('Later', style: FigmaText.dialogAction),
                    ),
                  ),
                  const SizedBox(width: AppSizes.spacingM),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSizes.spacingM,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                      ),
                      child: Text(
                        'Enable',
                        style: FigmaText.dialogAction.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (agreed == true && context.mounted) {
    await injector<LockSyncService>().openAccessibilitySettings();
  }
}

class PulsingSosButton extends StatefulWidget {
  final VoidCallback onTap;
  const PulsingSosButton({super.key, required this.onTap});

  @override
  State<PulsingSosButton> createState() => _PulsingSosButtonState();
}

class _PulsingSosButtonState extends State<PulsingSosButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Figma: SOS button 188, a soft ring at 237 and another at 309.
    final button = 188.w;
    final ring1 = 237.w;
    final ring2 = 309.w;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: ring2,
        height: ring2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: ring2,
              height: ring2,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFEDF2FB),
              ),
            ),
            Container(
              width: ring1,
              height: ring1,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE2EAF8),
              ),
            ),
            // Gentle ripple spreading from the button across the rings.
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final progress = _controller.value;
                final size = button + (ring1 - button) * progress;
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(
                      0xFF2F6BF2,
                    ).withValues(alpha: 0.18 * (1.0 - progress)),
                  ),
                );
              },
            ),
            // Central SOS button
            Container(
              width: button,
              height: button,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B8FF5), Color(0xFF1F44B8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2F6BF2).withValues(alpha: 0.4),
                    blurRadius: 32.w,
                    offset: Offset(0, 12.w),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Colors.white,
                      size: 28.w,
                    ),
                    Text(
                      "SOS",
                      // Figma: Poppins Bold 48, line height 100%.
                      style: FigmaText.poppins(
                        48,
                        weight: FontWeight.w700,
                        lineHeight: 48,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "TAP FOR HELP",
                      style: FigmaText.labelSmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosViewContent extends StatefulWidget {
  final bool hasAccessibilityPermission;
  final bool hasLocationPermission;
  final bool hasNotificationPermission;
  final bool hasBackgroundPermission;
  final VoidCallback onPermissionUpdated;

  const _SosViewContent({
    required this.hasAccessibilityPermission,
    required this.hasLocationPermission,
    required this.hasNotificationPermission,
    required this.hasBackgroundPermission,
    required this.onPermissionUpdated,
  });

  @override
  State<_SosViewContent> createState() => _SosViewContentState();
}

class _SosViewContentState extends State<_SosViewContent> {
  List<Map<String, dynamic>> _contacts = [];
  int _selectedContactIndex = 0;
  List<Map<String, dynamic>> _localMappedApps = [];
  bool _logoutRequestPending = false;
  StreamSubscription<RemoteMessage>? _logoutTapSubscription;
  StreamSubscription<RemoteMessage>? _logoutForegroundSubscription;

  @override
  void initState() {
    super.initState();
    _loadCachedContacts();
    _fetchContactsFromBackend();
    _loadLocalMappedApps();

    // The parent's decision on a logout request arrives as a push (type
    // LOGOUT_RESULT) — listened for on both streams so it's caught whether
    // the app was already foregrounded or the child tapped the
    // notification, mirroring home_page.dart's TIME_EXTENSION_REQUEST
    // listeners. Unlike a time-extension result (which only needs a local
    // notification), an approval here has to actually drive the app to log
    // out, so this needs its own handler rather than the generic
    // heads-up-only path in firebase_notification_service.dart.
    _logoutTapSubscription = FirebaseNotificationService().notificationTapStream
        .listen(_handleLogoutResultMessage);
    _logoutForegroundSubscription = FirebaseNotificationService().messageStream
        .listen(_handleLogoutResultMessage);
  }

  @override
  void dispose() {
    _logoutTapSubscription?.cancel();
    _logoutForegroundSubscription?.cancel();
    super.dispose();
  }

  void _handleLogoutResultMessage(RemoteMessage message) {
    if (message.data['type'] != 'LOGOUT_RESULT') return;
    final approved = message.data['approved'] == 'true';
    if (!mounted) return;
    setState(() => _logoutRequestPending = false);
    if (approved) {
      _performLogout(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your parent denied the logout request.')),
      );
    }
  }

  Future<void> _loadLocalMappedApps() async {
    if (!Platform.isIOS) return;
    try {
      final prefs = SharedPrefsService.prefs;
      final list = prefs.getStringList('local_mapped_apps') ?? [];
      if (mounted) {
        setState(() {
          _localMappedApps = list
              .map((e) => jsonDecode(e) as Map<String, dynamic>)
              .toList();
        });
      }
    } catch (e) {
      AppLogger.error("Failed to load local mapped apps: $e");
    }
  }

  void _addMoreScreenTimeApps() async {
    final granted = await injector<child_info.ChildInfoService>()
        .openUsageSettings();
    if (granted) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AppCatalogScreen()),
      ).then((_) {
        _loadLocalMappedApps();
      });
    }
  }

  void _loadCachedContacts() {
    final sharedPrefs = injector<SharedPrefsService>();
    final contactsJson = sharedPrefs.getString('parents_contacts');
    final parentPhone = sharedPrefs.getString('parent_phone') ?? 'N/A';
    final parentName = sharedPrefs.getString('parent_name') ?? 'Parent';

    if (contactsJson != null && contactsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(contactsJson);
        setState(() {
          _contacts = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        });
        return;
      } catch (e) {
        // Fallback
      }
    }

    setState(() {
      _contacts = [
        {
          'id': 'default_parent_contact',
          'name': parentName,
          'phone': parentPhone,
          'relation': 'Parent',
          'is_default': true,
        },
      ];
    });
  }

  Future<void> _fetchContactsFromBackend() async {
    try {
      final response = await injector<ChildRepo>().getChildContacts();
      if (response.isSuccess && response.data != null) {
        final List<dynamic> list = response.data!;
        if (list.isNotEmpty) {
          setState(() {
            _contacts = list.map((e) => Map<String, dynamic>.from(e)).toList();
            if (_selectedContactIndex >= _contacts.length) {
              _selectedContactIndex = 0;
            }
          });
          final String encoded = jsonEncode(_contacts);
          injector<SharedPrefsService>().setString('parents_contacts', encoded);
        }
      }
    } catch (e) {
      // Fallback silently
    }
  }

  void _showDeviceInfoDialog(BuildContext context, DeviceInfo deviceInfo) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusL),
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSizes.paddingL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Device Information', style: FigmaText.dialogTitle),
                const SizedBox(height: AppSizes.spacingM),
                _buildInfoRow('Battery', '${deviceInfo.batteryPercentage}%'),
                const SizedBox(height: AppSizes.spacingS),
                _buildInfoRow('Network Status', deviceInfo.networkStatus),
                const SizedBox(height: AppSizes.spacingS),
                _buildInfoRow('Network Type', deviceInfo.networkType),
                const SizedBox(height: AppSizes.spacingS),
                _buildInfoRow('Sound Profile', deviceInfo.soundProfile),
                const SizedBox(height: AppSizes.spacingS),
                _buildInfoRow(
                  'Online Status',
                  deviceInfo.isOnline ? 'Online' : 'Offline',
                ),
                const SizedBox(height: AppSizes.spacingL),
                SizedBox(
                  width: double.infinity,
                  child: CommonButton(
                    text: 'OK',
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: FigmaText.dialogBody),
        Text(
          value,
          style: FigmaText.dialogBody.copyWith(color: FigmaColors.ink),
        ),
      ],
    );
  }

  Widget _buildPermissionItem(
    String title,
    bool isGranted,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(
            isGranted ? Icons.check_circle : Icons.error_outline,
            color: isGranted ? Colors.green : AppColors.error,
            size: 20,
          ),
          const SizedBox(width: AppSizes.spacingS),
          Expanded(child: Text(title, style: FigmaText.dialogBody)),
          if (!isGranted)
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Enable',
                  style: FigmaText.dialogAction.copyWith(
                    color: FigmaColors.danger,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Was a direct-logout confirm dialog. A child leaving the app is exactly
  // the kind of thing this app exists to prevent going unnoticed, so
  // logging out now needs the parent's sign-off first: tapping "Logout"
  // here sends a request instead of logging out immediately — the actual
  // teardown only runs once the parent approves (see
  // _handleLogoutResultMessage above).
  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
        ),
        title: Text('Logout', style: FigmaText.dialogTitle),
        content: Text(
          'Logging out needs your parent\'s approval. Send them a request now?',
          style: FigmaText.dialogBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: FigmaText.dialogAction),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _requestLogoutFromParent(context);
            },
            child: Text(
              'Request Logout',
              style: FigmaText.dialogAction.copyWith(color: FigmaColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestLogoutFromParent(BuildContext context) async {
    if (_logoutRequestPending) return;
    setState(() => _logoutRequestPending = true);
    final response = await injector<LogoutRequestRepository>().requestLogout();
    if (!context.mounted) return;
    if (!response.isSuccess) {
      setState(() => _logoutRequestPending = false);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.isSuccess
              ? 'Logout request sent to your parent. Waiting for approval…'
              : (response.message.isNotEmpty
                    ? response.message
                    : 'Could not send logout request. Try again.'),
        ),
      ),
    );
  }

  Future<void> _performLogout(BuildContext context) async {
    try {
      // Remove FCM token from server before logout
      try {
        await FirebaseNotificationService().removeTokenFromServer();
        AppLogger.info('FCM token removed from server');
      } catch (e) {
        AppLogger.error('Error removing FCM token: $e');
      }

      // Stop ChildBloc timers and tracking
      try {
        final childBloc = injector<ChildBloc>();
        childBloc.stopChildTracking();
        AppLogger.info('ChildBloc: Stopped all tracking activities');
      } catch (e) {
        AppLogger.error('Error stopping ChildBloc: $e');
      }

      // Stop background location service
      try {
        await BackgroundLocationService().stop();
        AppLogger.info('Background location service stopped');
      } catch (e) {
        // Ignore errors if service wasn't running
        AppLogger.warning('Error stopping background service: $e');
      }

      // Stop native app blocking and clear iOS credentials
      try {
        await injector<LockSyncService>().syncLockedAppsToNative([]);
        await injector<ChildRepo>().clearAppGroupCredentials();
        AppLogger.info('Cleared native lock list and App Group credentials');
      } catch (e) {
        AppLogger.error('Error clearing native credentials: $e');
      }

      // Stop web filtering
      try {
        await injector<DeviceInfoService>().setWebFiltering(false);
        AppLogger.info('Disabled web filtering on logout');
      } catch (e) {
        AppLogger.error('Error disabling web filtering: $e');
      }

      // Disconnect socket service
      final socketService = injector<SocketService>();
      if (socketService.isConnected) {
        final childId = injector<SharedPrefsService>().getString('child_id');
        if (childId != null) {
          socketService.leaveRoom(childId);
        }
        socketService.disconnect();
      }

      // Clear all user data
      final sharedPrefsService = injector<SharedPrefsService>();
      await sharedPrefsService.logout();

      // Navigate to onboarding screen and remove all previous routes
      if (context.mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(RouteNames.onBoarding, (route) => false);
      }
    } catch (e) {
      // Even if there's an error, try to navigate to onboarding
      if (context.mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(RouteNames.onBoarding, (route) => false);
      }
    }
  }

  // ChildRepo.sendSOS + the backend's POST /child/sos + notifySOS() were
  // already fully implemented (real-time socket emit + a bypass-preferences
  // push to every linked parent) but nothing in the app ever called
  // sendSOS — the SOS button only opened the phone dialer. Fire this
  // alongside the dial so the parent gets an immediate alert too, not just
  // whatever the child manages to say on the call.
  Future<void> _triggerSosAlert() async {
    try {
      final childId = injector<SharedPrefsService>().getString('child_id');
      if (childId == null || childId.isEmpty) return;

      double lat = 0;
      double lng = 0;
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        );
        lat = position.latitude;
        lng = position.longitude;
      } catch (e) {
        // GPS fix too slow/unavailable — fall back to the last known fix
        // rather than blocking the alert on a fresh one.
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          lat = last.latitude;
          lng = last.longitude;
        }
      }

      final response = await injector<ChildRepo>().sendSOS(
        childId: childId,
        lat: lat,
        lng: lng,
      );
      AppLogger.info('SOS alert sent to parent: ${response.isSuccess}');
    } catch (e) {
      AppLogger.error('Error sending SOS alert: $e');
    }
  }

  Future<void> _callNumber(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(' ', '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);
    try {
      if (!await launchUrl(launchUri)) {
        AppLogger.error('Could not launch dialer');
      }
    } catch (e) {
      AppLogger.error('Error launching dialer: $e');
    }
  }

  Widget _buildContactTab({
    required bool isSelected,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // Figma: selected = solid blue, other = white with a pale-blue outline.
    const blue = Color(0xFF2F6BF2);
    final fg = isSelected ? Colors.white : blue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44.w,
        decoration: BoxDecoration(
          color: isSelected ? blue : Colors.white,
          borderRadius: BorderRadius.circular(12.w),
          border: Border.all(
            color: isSelected ? blue : const Color(0xFFC9DCFB),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 18.w),
            SizedBox(width: 8.w),
            Text(label, style: FigmaText.bodyMedium.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleLogout(context);
      },
      child: BlocListener<ChildBloc, ChildState>(
        listenWhen: (previous, current) {
          return previous is! ChildDeviceInfoLoaded &&
              current is ChildDeviceInfoLoaded;
        },
        listener: (context, state) {
          if (state is ChildDeviceInfoLoaded) {
            _showDeviceInfoDialog(context, state.deviceInfo);
          }
        },
        child: BlocBuilder<ChildBloc, ChildState>(
          builder: (context, state) {
            final sharedPrefsService = injector<SharedPrefsService>();
            final childCode = sharedPrefsService.getString('child_code') ?? '';

            final contact =
                _contacts.isNotEmpty && _selectedContactIndex < _contacts.length
                ? _contacts[_selectedContactIndex]
                : null;
            final contactPhone = contact != null
                ? (contact['phone'] ?? '')
                : '';
            final contactRelation = contact != null
                ? (contact['relation'] ?? 'Parent')
                : 'Parent';

            final canCall = contactPhone.isNotEmpty && contactPhone != 'N/A';

            return Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              drawer: ChildAppDrawer(
                onLogout: () => _handleLogout(context),
                onShareLogs: () => shareCsvLogFiles(context),
              ),
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE6EDF9), Color(0xFFF8F9FC)],
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                  ),
                ),
                child: SafeArea(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24.w,
                        vertical: 16.w,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top Bar Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Back Button (Figma: 52px white circle)
                              FigmaCircleButton(
                                onTap: () => _handleLogout(context),
                                child: Image.asset(
                                  'assets/icons/auth_back.png',
                                  width: 24.w,
                                  height: 24.w,
                                ),
                              ),

                              // Right Status Icons
                              // Row(
                              //   children: [
                              //     GestureDetector(
                              //       onTap: () => Scaffold.of(context).openDrawer(),
                              //       child: const Icon(
                              //         Icons.wb_cloudy_outlined,
                              //         color: Color(0xFF3B82F6),
                              //         size: 22,
                              //       ),
                              //     ),
                              //     const SizedBox(width: 16),
                              //     GestureDetector(
                              //       onTap: () {
                              //         context.read<ChildBloc>().add(
                              //           CheckUsagePermission(),
                              //         );
                              //       },
                              //       child: const Icon(
                              //         Icons.star_outline_rounded,
                              //         color: Color(0xFF3B82F6),
                              //         size: 22,
                              //       ),
                              //     ),
                              //     const SizedBox(width: 16),
                              //     const Icon(
                              //       Icons.auto_awesome_outlined,
                              //       color: Color(0xFF3B82F6),
                              //       size: 22,
                              //     ),
                              //   ],
                              // ),
                            ],
                          ),

                          SizedBox(height: 16.w),

                          // Heading Text. Figma: Body Small label over a Bold 20
                          // title on one line.
                          Text(
                            "Need Help?",
                            textAlign: TextAlign.center,
                            style: FigmaText.bodySmall.copyWith(
                              color: const Color(0xFF2D3035),
                            ),
                          ),
                          SizedBox(height: 4.w),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "Press SOS to call for help!",
                              textAlign: TextAlign.center,
                              // Figma Heading H3: Poppins Bold 24 / 28.
                              style: FigmaText.poppins(
                                24,
                                weight: FontWeight.w700,
                                lineHeight: 28,
                                color: const Color(0xFF0F1320),
                              ),
                            ),
                          ),

                          SizedBox(height: 28.w),

                          // Center Pulsing SOS Button
                          Center(
                            child: PulsingSosButton(
                              onTap: () {
                                if (canCall) _callNumber(contactPhone);
                                _triggerSosAlert();
                              },
                            ),
                          ),

                          SizedBox(height: 24.w),

                          // Parents Contact Details Card
                          Container(
                            padding: EdgeInsets.all(20.w),
                            // Figma: white card, 24 radius, 1px grey border.
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24.w),
                              border: Border.all(
                                color: const Color(0xFFC9CCD1),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Parents Contact Details",
                                  // Figma: Poppins Regular 11, line height 100%.
                                  style: FigmaText.poppins(
                                    11,
                                    lineHeight: 11,
                                    letterSpacing: 0.2,
                                    color: const Color(0xFF2D3035),
                                  ),
                                ),
                                SizedBox(height: 12.w),

                                // Toggle Tabs
                                if (_contacts.length > 1) ...[
                                  Row(
                                    children: List.generate(_contacts.length, (
                                      index,
                                    ) {
                                      final c = _contacts[index];
                                      final isSelected =
                                          _selectedContactIndex == index;
                                      return Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            right: index == _contacts.length - 1
                                                ? 0
                                                : 12.w,
                                          ),
                                          child: _buildContactTab(
                                            isSelected: isSelected,
                                            label:
                                                c['relation'] ??
                                                c['name'] ??
                                                'Parent',
                                            icon: Icons.person_outline_rounded,
                                            onTap: () {
                                              setState(() {
                                                _selectedContactIndex = index;
                                              });
                                            },
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                  SizedBox(height: 16.w),
                                ],

                                // Phone Info Row
                                Row(
                                  children: [
                                    Container(
                                      width: 48.w,
                                      height: 48.w,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(
                                          12.w,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.person_outline_rounded,
                                        color: FigmaColors.ink,
                                        size: 24.w,
                                      ),
                                    ),
                                    SizedBox(width: 14.w),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            contactPhone,
                                            style: FigmaText.bodyLarge.copyWith(
                                              color: FigmaColors.ink,
                                            ),
                                          ),
                                          Text(
                                            "$contactRelation's number",
                                            style: FigmaText.bodySmall.copyWith(
                                              color: FigmaColors.body,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                SizedBox(height: 16.w),

                                // Action Button: Figma blue gradient with a glow.
                                Opacity(
                                  opacity: canCall ? 1 : 0.5,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12.w),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF5B8FF5),
                                          Color(0xFF1F44B8),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF2F6BF2,
                                          ).withValues(alpha: 0.35),
                                          blurRadius: 16.w,
                                          offset: Offset(0, 6.w),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          12.w,
                                        ),
                                        onTap: canCall
                                            ? () => _callNumber(contactPhone)
                                            : null,
                                        child: SizedBox(
                                          height: 52.w,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.phone_outlined,
                                                color: Colors.white,
                                                size: 22.w,
                                              ),
                                              SizedBox(width: 8.w),
                                              Text(
                                                "Call $contactRelation Now",
                                                style: FigmaText.bodyMedium
                                                    .copyWith(
                                                      color: Colors.white,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Expansion card for original permissions
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              title: Text(
                                "App Configuration & Diagnostic Logs",
                                style: GoogleFonts.poppins(
                                  fontSize: 12.0.sp,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              iconColor: const Color(0xFF94A3B8),
                              collapsedIconColor: const Color(0xFF94A3B8),
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFFEFF2F6),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.security_rounded,
                                            color: Color(0xFF0066FF),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'App Permissions Status',
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Divider(color: Color(0xFFEFF2F6)),
                                      if (Platform.isIOS) ...[
                                        _buildPermissionItem(
                                          'Location',
                                          widget.hasLocationPermission,
                                          () async {
                                            LocationPermission permission =
                                                await Geolocator.checkPermission();
                                            if (permission ==
                                                LocationPermission.denied) {
                                              permission =
                                                  await Geolocator.requestPermission();
                                            }
                                            if (permission ==
                                                    LocationPermission
                                                        .deniedForever ||
                                                permission ==
                                                    LocationPermission
                                                        .whileInUse) {
                                              await Geolocator.openAppSettings();
                                            }
                                            widget.onPermissionUpdated();
                                          },
                                        ),
                                        _buildPermissionItem(
                                          'Screen Time & App Blocking',
                                          widget.hasAccessibilityPermission,
                                          () => showAccessibilityDisclosure(
                                            context,
                                          ),
                                        ),
                                        // _buildPermissionItem(
                                        //   'Notifications',
                                        //   widget.hasNotificationPermission,
                                        //   () async {
                                        //     final status = await Permission
                                        //         .notification
                                        //         .request();
                                        //     if (!status.isGranted) {
                                        //       await openAppSettings();
                                        //     }
                                        //     widget.onPermissionUpdated();
                                        //   },
                                        // ),
                                      ] else ...[
                                        _buildPermissionItem(
                                          'Location',
                                          widget.hasLocationPermission,
                                          () async {
                                            LocationPermission permission =
                                                await Geolocator.checkPermission();
                                            if (permission ==
                                                LocationPermission.denied) {
                                              permission =
                                                  await Geolocator.requestPermission();
                                            }
                                            if (permission ==
                                                    LocationPermission
                                                        .deniedForever ||
                                                permission ==
                                                    LocationPermission
                                                        .whileInUse) {
                                              // If they denied it forever or only gave whileInUse, direct to settings.
                                              await Geolocator.openAppSettings();
                                            }
                                            widget.onPermissionUpdated();
                                          },
                                        ),
                                        _buildPermissionItem(
                                          'Background Work',
                                          widget.hasBackgroundPermission,
                                          () async {
                                            await Permission
                                                .ignoreBatteryOptimizations
                                                .request();
                                            widget.onPermissionUpdated();
                                          },
                                        ),
                                        _buildPermissionItem(
                                          'App Usage',
                                          state is ChildDeviceInfoLoaded
                                              ? state.hasUsagePermission
                                              : false,
                                          () => context.read<ChildBloc>().add(
                                            OpenUsageSettings(),
                                          ),
                                        ),
                                        _buildPermissionItem(
                                          'Accessibility',
                                          widget.hasAccessibilityPermission,
                                          () => showAccessibilityDisclosure(
                                            context,
                                          ),
                                        ),
                                        _buildPermissionItem(
                                          'Notifications',
                                          widget.hasNotificationPermission,
                                          () async {
                                            final status = await Permission
                                                .notification
                                                .request();
                                            if (status.isPermanentlyDenied) {
                                              await openAppSettings();
                                            }
                                            widget.onPermissionUpdated();
                                          },
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(
                                                  color: Color(0xFF0066FF),
                                                  width: 1.5,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.analytics_outlined,
                                                size: 16,
                                                color: Color(0xFF0066FF),
                                              ),
                                              label: Text(
                                                'Diagnostic Logs',
                                                style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.0.sp,
                                                  color: const Color(
                                                    0xFF0066FF,
                                                  ),
                                                ),
                                              ),
                                              onPressed: () {
                                                showModalBottomSheet(
                                                  context: context,
                                                  isScrollControlled: true,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  builder: (context) =>
                                                      const _DiagnosticLogsSheet(),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (Platform.isIOS &&
                                          _localMappedApps.isNotEmpty) ...[
                                        const SizedBox(height: 16),
                                        const Divider(color: Color(0xFF2C2C2E)),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Monitored Apps',
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14.0.sp,
                                                color: Colors.white,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: _addMoreScreenTimeApps,
                                              child: Text(
                                                '+ Add More',
                                                style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(
                                                    0xFF0066FF,
                                                  ),
                                                  fontSize: 13.0.sp,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: _localMappedApps.map((app) {
                                            return Chip(
                                              backgroundColor: const Color(
                                                0xFF1C1C1E,
                                              ),
                                              side: const BorderSide(
                                                color: Color(0xFF2C2C2E),
                                              ),
                                              label: Text(
                                                app['customName'] ??
                                                    'Unknown App',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontSize: 12.0.sp,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          Text(
                            'Child Code: $childCode',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 12.0.sp,
                              color: const Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Naviq Dev 1.0.10(Oct 22)',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 10.0.sp,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// DIAGNOSTIC LOGS VIEWER SHEET (iOS Background & App Activity Logs)
// -------------------------------------------------------------------------
class _DiagnosticLogsSheet extends StatefulWidget {
  const _DiagnosticLogsSheet();

  @override
  State<_DiagnosticLogsSheet> createState() => _DiagnosticLogsSheetState();
}

class _DiagnosticLogsSheetState extends State<_DiagnosticLogsSheet> {
  bool _isLoading = true;
  List<String> _appLogs = [];
  List<String> _apnsLogs = [];
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });

    final csvLogs = await CsvFileLogger.instance.readLogs();
    List<String> nativeLogs = [];
    if (Platform.isIOS) {
      try {
        const channel = MethodChannel('com.truenyx.naviq/parental_control');
        final result = await channel.invokeMethod<List<dynamic>>(
          'getExtensionLogs',
        );
        if (result != null) {
          nativeLogs = result
              .map((e) => e.toString())
              .toList()
              .reversed
              .toList();
        }
      } catch (e) {
        AppLogger.error('Failed to get iOS native extension logs: $e');
      }
    }

    if (mounted) {
      setState(() {
        _appLogs = csvLogs;
        _apnsLogs = nativeLogs;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Logs?'),
        content: const Text(
          'This will delete all activity and sync diagnostics logs from this device. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear Logs'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      await CsvFileLogger.instance.clearLogs();
      if (Platform.isIOS) {
        try {
          const channel = MethodChannel('com.truenyx.naviq/parental_control');
          await channel.invokeMethod<bool>('clearExtensionLogs');
        } catch (e) {
          AppLogger.error('Failed to clear iOS native logs: $e');
        }
      }

      await _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logs successfully cleared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  List<String> _filterLogs(List<String> logs) {
    if (_searchQuery.isEmpty) return logs;
    return logs
        .where((log) => log.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Widget _buildAppLogItem(String rawRow) {
    final parts = rawRow.split(',');
    if (parts.length < 4) {
      return _buildRawLogItem(rawRow);
    }
    final ts = parts[0];
    final tag = parts[1];
    final level = parts[2];
    final message = parts.skip(3).join(',').replaceAll('"', '');

    Color tagColor = Colors.blue;
    if (level == 'ERROR') tagColor = Colors.red;
    if (level == 'WARNING') tagColor = Colors.orange;
    if (level.contains('OK') ||
        message.toLowerCase().contains('success') ||
        message.contains('OK')) {
      tagColor = Colors.green;
    }

    String formattedTime = ts;
    try {
      final dateTime = DateTime.parse(ts).toLocal();
      formattedTime =
          "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}";
    } catch (_) {}

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied log to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tagColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: tagColor,
                          fontSize: 9.0.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        level,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 9.0.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  formattedTime,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.body2.copyWith(
                fontFamily: Platform.isIOS ? 'Courier' : 'monospace',
                fontSize: 12.0.sp,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApnsLogItem(String rawRow) {
    final timeRegex = RegExp(r'^\[(.*?)\]');
    final match = timeRegex.firstMatch(rawRow);
    String time = "";
    String body = rawRow;
    if (match != null) {
      time = match.group(1) ?? "";
      body = rawRow.replaceFirst(timeRegex, '').trim();
    }

    Color sourceColor = AppColors.primaryColor;
    if (body.contains("AppDel")) {
      sourceColor = Colors.teal;
    }
    if (body.contains("❌") ||
        body.toLowerCase().contains("failed") ||
        body.toLowerCase().contains("error")) {
      sourceColor = Colors.red;
    } else if (body.contains("✅") ||
        body.toLowerCase().contains("ok") ||
        body.toLowerCase().contains("success")) {
      sourceColor = Colors.green;
    }

    final displayBody = body
        .replaceFirst("AppDel:", "")
        .replaceFirst("Runner:", "")
        .trim();

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: rawRow));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied log to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    body.contains("AppDel")
                        ? "AppDelegate"
                        : "ScreenTimeExtension",
                    style: TextStyle(
                      color: sourceColor,
                      fontSize: 9.0.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              displayBody,
              style: AppTextStyles.body2.copyWith(
                fontFamily: Platform.isIOS ? 'Courier' : 'monospace',
                fontSize: 12.0.sp,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRawLogItem(String rawLog) {
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: rawLog));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied log to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Text(
          rawLog,
          style: AppTextStyles.body2.copyWith(
            fontFamily: Platform.isIOS ? 'Courier' : 'monospace',
            fontSize: 12.0.sp,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Draggable Handle Indicator
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),

              // Title and Actions Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Diagnostic Logs',
                          style: AppTextStyles.headline6.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Background Sync & System Logs',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.ios_share,
                            color: AppColors.primaryColor,
                          ),
                          tooltip: 'Share logs',
                          onPressed: () => shareCsvLogFiles(context),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.refresh,
                            color: AppColors.primaryColor,
                          ),
                          onPressed: _loadLogs,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.error,
                          ),
                          onPressed: _clearLogs,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search logs...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = "";
                              });
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Log Tabs and List View
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        labelColor: AppColors.primaryColor,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: AppColors.primaryColor,
                        indicatorSize: TabBarIndicatorSize.tab,
                        tabs: [
                          Tab(text: 'App Activity'),
                          Tab(text: 'APNs & Sync'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Tab 1: App Activity Logs
                            _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : Builder(
                                    builder: (context) {
                                      final filtered = _filterLogs(_appLogs);
                                      if (filtered.isEmpty) {
                                        return _buildEmptyState(
                                          'No Activity Logs found',
                                        );
                                      }
                                      return ListView.builder(
                                        controller: scrollController,
                                        itemCount: filtered.length,
                                        itemBuilder: (context, idx) =>
                                            _buildAppLogItem(filtered[idx]),
                                      );
                                    },
                                  ),

                            // Tab 2: APNs & Sync Logs
                            _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : Builder(
                                    builder: (context) {
                                      final filtered = _filterLogs(_apnsLogs);
                                      if (filtered.isEmpty) {
                                        return _buildEmptyState(
                                          'No APNs Sync Logs found',
                                        );
                                      }
                                      return ListView.builder(
                                        controller: scrollController,
                                        itemCount: filtered.length,
                                        itemBuilder: (context, idx) =>
                                            _buildApnsLogItem(filtered[idx]),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off,
            size: 48,
            color: Colors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
