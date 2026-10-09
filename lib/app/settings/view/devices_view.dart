import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'widgets/device_cards.dart';
import 'package:child_track/core/services/subscription_manager.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/app/home/model/device_model.dart';
import '../../subscription/models/subscription_plan.dart';
import '../../subscription/view/subscription_multi_plan_view.dart';

class DevicesView extends StatefulWidget {
  /// Opened from "Purchase Device": always show the buy pitch, even when a
  /// tracker is already linked or an entitlement is active.
  final bool showPurchasePitch;

  const DevicesView({super.key, this.showPurchasePitch = false});

  @override
  State<DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<DevicesView> {
  bool _isLoading = true;
  bool _simulatedPurchased = false; // toggle for manual testing
  DeviceInfo? _deviceInfo;
  // device_info has no last-updated timestamp of its own — "when" lives on
  // the sibling current_location section (LocationInfo.since), so this is
  // tracked separately from _deviceInfo.
  String? _lastUpdatedRaw;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  // Real tracker telemetry (battery/altitude/speed/online) for the device
  // card — this screen previously showed only hardcoded marketing copy
  // ("TrackPod Pro", "±2m accuracy", "87%") regardless of whether a real
  // device was even linked. altitude/speed are only ever populated by the
  // JT808 tracker pipeline (naviQ-server tcp/server.js), never a phone.
  Future<void> _loadDeviceInfo() async {
    try {
      // Explicit childId — without it this hits the backend's default
      // (the parent's primary child), not necessarily whichever child the
      // parent currently has selected elsewhere in the app. Confirmed real
      // case: viewing a non-primary child's Devices screen still showed
      // this screen driven by a different child's data.
      final childId = injector<SharedPrefsService>().getString('child_id');
      final response = await injector<HomeRepository>().getHomeData(
        childId: childId,
      );
      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _deviceInfo = response.data!.deviceInfo;
          _lastUpdatedRaw = response.data!.currentLocation.since;
          // "My Device" only when this child has a real tracker linked
          // (device_imei set); everyone else gets the buy pitch.
          if (!widget.showPurchasePitch &&
              (_deviceInfo?.deviceImei ?? '').isNotEmpty) {
            _simulatedPurchased = true;
          }
        });
      }
    } catch (_) {
      // Leave _deviceInfo null — cards below fall back to a neutral empty
      // state rather than showing stale/fake numbers.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Trusts the backend's own isOnline computation directly (it already has
  // its own freshness threshold — deviceOfflineJob.js, 5 min). This used
  // to ALSO require the location fix to be <15 min old, which conflated
  // two different facts: a tracker can check in (battery/online ping)
  // independently of sending a fresh GPS fix (stationary + power-saving,
  // or weak signal) — confirmed real case: isOnline was true (device
  // checked in 1.5 min ago) but the location fix was 4+ hours old, and
  // this badge showed "Offline" anyway, contradicting the "Device online"
  // note now shown on the home screen for the exact same child.
  bool get _isDeviceLive => _deviceInfo?.isOnline ?? false;

  String _formatDeviceLastUpdated() {
    final since = DateTime.tryParse(_lastUpdatedRaw ?? '');
    if (since == null) return 'No data yet';
    final diff = DateTime.now().toUtc().difference(since.toUtc());
    if (diff.isNegative || diff.inSeconds < 90) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  // Compact form for the metric-pod value slot (matches "±2m"/"24H"-style
  // short values) — _formatDeviceLastUpdated's "Updated Xm ago" phrasing is
  // for the Battery Life card's longer caption line instead.
  String _formatDeviceLastUpdatedCompact() {
    final since = DateTime.tryParse(_lastUpdatedRaw ?? '');
    if (since == null) return '—';
    final diff = DateTime.now().toUtc().difference(since.toUtc());
    if (diff.isNegative || diff.inSeconds < 90) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: figmaAppBar(
        context,
        title: _simulatedPurchased ? 'My Device' : 'Device',
        trailing: FigmaCircleButton(
          child: SvgPicture.asset(
            'assets/help/help_search.svg',
            width: 24.w,
            height: 24.w,
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : (_simulatedPurchased
                ? _buildPurchasedView()
                : _buildNonPurchasedView()),
      bottomNavigationBar: kDebugMode
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_buildDebugTierSwitcher() != null)
                  _buildDebugTierSwitcher()!,
                if (_buildDebugToggle() != null) _buildDebugToggle()!,
              ],
            )
          : null,
    );
  }

  // ── Debug / Demo review toggle ─────────────────────────────────────────────
  Widget? _buildDebugToggle() {
    if (!kDebugMode) return null;
    return SafeArea(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8.w, horizontal: 16.w),
        decoration: BoxDecoration(
          color: Color(0xFFF1F5F9),
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Review Simulator Tool:",
              style: GoogleFonts.poppins(
                fontSize: 12.0.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              children: [
                Text(
                  "Not Purchased",
                  style: GoogleFonts.poppins(
                    fontSize: 11.0.sp,
                    fontWeight: _simulatedPurchased
                        ? FontWeight.w500
                        : FontWeight.w800,
                    color: _simulatedPurchased
                        ? AppColors.textSecondary
                        : AppColors.primaryColor,
                  ),
                ),
                Switch(
                  activeThumbColor: AppColors.primaryColor,
                  value: _simulatedPurchased,
                  onChanged: (val) {
                    setState(() {
                      _simulatedPurchased = val;
                    });
                  },
                ),
                Text(
                  "Purchased",
                  style: GoogleFonts.poppins(
                    fontSize: 11.0.sp,
                    fontWeight: _simulatedPurchased
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: _simulatedPurchased
                        ? AppColors.primaryColor
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Debug tier switcher ─────────────────────────────────────────────────────
  // The toggle above only flips this screen's own local "purchased" demo
  // state — it never touched SubscriptionManager.instance, which is the
  // actual source of truth the tier-gated features (geofence limits, trip
  // history window, Social Apps lock actions, Help channels, the floating
  // upgrade banner, ...) read via SubscriptionFeatureGate. Without going
  // through a real RevenueCat sandbox purchase, there was no way to exercise
  // those gates end-to-end. debugSetTier exists specifically for this (see
  // its doc comment in subscription_manager.dart) but was never wired to any
  // UI. debugSetTier only changes in-memory state for the current app
  // session — it doesn't touch RevenueCat or the backend, so a real
  // checkAndUpdateStatus() call (app restart, or a real purchase) overrides
  // it back to the real entitlement.
  Widget? _buildDebugTierSwitcher() {
    if (!kDebugMode) return null;
    return AnimatedBuilder(
      animation: SubscriptionManager.instance,
      builder: (context, _) {
        final current = SubscriptionManager.instance.currentTier;
        return Container(
          margin: EdgeInsets.fromLTRB(16.w, 0.w, 16.w, 8.w),
          padding: EdgeInsets.symmetric(vertical: 10.w, horizontal: 12.w),
          decoration: BoxDecoration(
            color: Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12.w),
            border: Border.all(color: Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Text(
                "Debug tier:",
                style: GoogleFonts.poppins(
                  fontSize: 12.0.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: SubscriptionTier.values.map((tier) {
                    final isSelected = tier == current;
                    return GestureDetector(
                      onTap: () {
                        // ignore: invalid_use_of_visible_for_testing_member
                        SubscriptionManager.instance.debugSetTier(tier);
                        AppSnackbar.showSuccess(
                          context,
                          'Debug tier set to ${tier.id} (this session only)',
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 6.w,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryColor
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20.w),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primaryColor
                                : Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Text(
                          tier.id,
                          style: GoogleFonts.poppins(
                            fontSize: 11.0.sp,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Figma: 34px page margins, content starts 12px under the header.
  EdgeInsets get _pagePadding => EdgeInsets.fromLTRB(34.w, 12.w, 34.w, 24.w);

  // ── Non-Purchased View ──────────────────────────────────────────────────────
  Widget _buildNonPurchasedView() {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeviceHeroCard(
            label: 'GPS Tracker',
            name: 'TrackPod Pro',
            metrics: const [
              ('±2m', 'Accuracy'),
              ('24H', 'Coverage'),
              ('7d', 'Battery'),
            ],
          ),
          SizedBox(height: 18.w),
          DeviceSectionTitle('Features'),
          SizedBox(height: 12.w),
          DeviceFeatureGrid(
            cards: [
              DeviceFeatureCard(
                icon: Icons.location_on_outlined,
                iconColor: FigmaColors.primary,
                iconBackground: Color(0xFFEFF5FF),
                title: 'Accuracy',
                subtitle: '±2m GPS precision',
              ),
              DeviceFeatureCard(
                icon: Icons.schedule_rounded,
                iconColor: Color(0xFF10B981),
                iconBackground: Color(0xFFF3F5F8),
                title: '24H Tracking',
                subtitle: 'All-day coverage',
              ),
              DeviceFeatureCard(
                icon: Icons.battery_5_bar_rounded,
                iconColor: Color(0xFFF59E0B),
                iconBackground: Color(0xFFF3F5F8),
                title: '7-Day Battery',
                subtitle: 'Ultra-long life',
                compact: true,
              ),
              DeviceFeatureCard(
                icon: Icons.shield_outlined,
                iconColor: FigmaColors.primary,
                iconBackground: Color(0xFFF3F5F8),
                title: 'Safe Zone',
                subtitle: 'Geo-fence alerts',
                compact: true,
              ),
            ],
          ),
          SizedBox(height: 18.w),
          DevicePurchaseCard(
            onBuy: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SubscriptionMultiPlanView()),
            ),
          ),
          SizedBox(height: 16.w),
          Center(
            child: TextButton(
              onPressed: () => _showLinkDeviceSheet(context),
              child: Text(
                'Already have a tracker? Link Existing Tracker',
                style: FigmaText.poppins(
                  13,
                  weight: FontWeight.w600,
                  color: FigmaColors.primary,
                ).copyWith(decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Purchased View ──────────────────────────────────────────────────────────
  Widget _buildPurchasedView() {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showDeviceManagementSheet(context),
            child: DeviceHeroCard(
              label: 'GPS TRACKER',
              uppercaseLabel: true,
              name: 'TrackPod Pro',
              nameSize: 22,
              isLive: _isDeviceLive,
              metrics: [
                (
                  _deviceInfo != null
                      ? '${_deviceInfo!.batteryPercentage}%'
                      : '—',
                  'Battery',
                ),
                (
                  _deviceInfo?.altitude != null
                      ? '${_deviceInfo!.altitude!.round()}m'
                      : '—',
                  'Altitude',
                ),
                (_formatDeviceLastUpdatedCompact(), 'Last seen'),
              ],
            ),
          ),
          SizedBox(height: 12.w),
          DeviceBatteryCard(
            percent: _deviceInfo?.batteryPercentage,
            caption: _formatDeviceLastUpdated(),
          ),
          SizedBox(height: 12.w),
          DeviceGpsCard(caption: 'Last updated 2s ago'),
          SizedBox(height: 24.w),
          DeviceSectionTitle("Today's Tracking", size: 16),
          SizedBox(height: 12.w),
          DeviceActivityCard(
            onViewAll: () => AppSnackbar.showInfo(
              context,
              'Full activity history coming soon',
            ),
          ),
        ],
      ),
    );
  }

  // ── Modal Actions & Dialogs ─────────────────────────────────────────────────
  void _showLinkDeviceSheet(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController();
    bool sheetLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.w)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom:
                    MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.paddingOf(context).bottom +
                    24.w,
                top: 24.w,
                left: 24.w,
                right: 24.w,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Link Existing Tracker",
                          style: GoogleFonts.poppins(
                            fontSize: 20.0.sp,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.w),
                    Text(
                      "Enter the 10 or 11-digit device ID or serial number printed on the back of your NaviQ tracker package.",
                      style: GoogleFonts.poppins(
                        fontSize: 13.0.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 20.w),
                    TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      maxLength: 11,
                      decoration: InputDecoration(
                        hintText: "e.g., 37250151398",
                        prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.w),
                          borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.w),
                          borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.w),
                          borderSide: BorderSide(
                            color: AppColors.primaryColor,
                            width: 2.w,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Please enter device ID";
                        }
                        if (value.length < 10) {
                          return "Device ID must be 10 or 11 digits";
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 24.w),
                    SizedBox(
                      width: double.infinity,
                      height: 52.w,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.w),
                          ),
                          elevation: 0,
                        ),
                        onPressed: sheetLoading
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setSheetState(() {
                                    sheetLoading = true;
                                  });
                                  final navigator = Navigator.of(sheetContext);
                                  final messengerContext = context;
                                  await Future.delayed(
                                    Duration(milliseconds: 1500),
                                  );
                                  if (mounted) {
                                    setState(() {
                                      _simulatedPurchased = true;
                                    });
                                    navigator.pop();
                                    if (messengerContext.mounted) {
                                      AppSnackbar.showSuccess(
                                        messengerContext,
                                        "Device linked successfully!",
                                      );
                                    }
                                  }
                                }
                              },
                        child: sheetLoading
                            ? SizedBox(
                                height: 20.w,
                                width: 20.w,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                "Connect Device",
                                style: GoogleFonts.poppins(
                                  fontSize: 16.0.sp,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDeviceManagementSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.w)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: EdgeInsets.fromLTRB(
            16.w,
            24.w,
            16.w,
            24.w + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0.w),
                child: Text(
                  "Device Management",
                  style: GoogleFonts.poppins(
                    fontSize: 18.0.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: 16.w),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.volume_up_rounded,
                    color: Color(0xFF3B82F6),
                    size: 20.w,
                  ),
                ),
                title: Text(
                  "Ping / Ring Device",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _triggerPingAnimation(context);
                },
              ),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.restart_alt_rounded,
                    color: Color(0xFFF59E0B),
                    size: 20.w,
                  ),
                ),
                title: Text(
                  "Reboot Device",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRebootDialog(context);
                },
              ),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.delete_forever_rounded,
                    color: Color(0xFFEF4444),
                    size: 20.w,
                  ),
                ),
                title: Text(
                  "Unlink Device",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEF4444),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showUnlinkDialog(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _triggerPingAnimation(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _PingSimulationDialog(
          onCancel: () => Navigator.pop(dialogContext),
        );
      },
    );
  }

  void _showRebootDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isRebooting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.w),
              ),
              title: Text(
                "Reboot Tracker?",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
              ),
              content: isRebooting
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 12.w),
                        CircularProgressIndicator(),
                        SizedBox(height: 16.w),
                        Text(
                          "Sending reboot command...",
                          style: GoogleFonts.poppins(
                            fontSize: 14.0.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      "This will remotely restart the tracker device. It may take 1-2 minutes to reconnect online.",
                      style: GoogleFonts.poppins(
                        fontSize: 14.0.sp,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
              actions: isRebooting
                  ? null
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(
                          "Cancel",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          setDialogState(() {
                            isRebooting = true;
                          });
                          final navigator = Navigator.of(dialogContext);
                          final messengerContext = context;
                          await Future.delayed(Duration(milliseconds: 1500));
                          navigator.pop();
                          if (messengerContext.mounted) {
                            AppSnackbar.showSuccess(
                              messengerContext,
                              "Reboot command sent successfully!",
                            );
                          }
                        },
                        child: Text(
                          "Reboot",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  void _showUnlinkDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isUnlinking = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.w),
              ),
              title: Text(
                "Unlink Device?",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFEF4444),
                ),
              ),
              content: isUnlinking
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 12.w),
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Color(0xFFEF4444)),
                        ),
                        SizedBox(height: 16.w),
                        Text(
                          "Removing tracker association...",
                          style: GoogleFonts.poppins(
                            fontSize: 14.0.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      "Are you sure you want to unlink this tracker from your account? This child will no longer be tracked using this hardware device.",
                      style: GoogleFonts.poppins(
                        fontSize: 14.0.sp,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
              actions: isUnlinking
                  ? null
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(
                          "Keep Linked",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          setDialogState(() {
                            isUnlinking = true;
                          });
                          final navigator = Navigator.of(dialogContext);
                          final messengerContext = context;
                          await Future.delayed(Duration(milliseconds: 1500));
                          if (mounted) {
                            setState(() {
                              _simulatedPurchased = false;
                            });
                          }
                          navigator.pop();
                          if (messengerContext.mounted) {
                            AppSnackbar.showSuccess(
                              messengerContext,
                              "Device unlinked successfully.",
                            );
                          }
                        },
                        child: Text(
                          "Unlink",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
            );
          },
        );
      },
    );
  }
}

class _PingSimulationDialog extends StatefulWidget {
  final VoidCallback onCancel;
  const _PingSimulationDialog({required this.onCancel});

  @override
  State<_PingSimulationDialog> createState() => _PingSimulationDialogState();
}

class _PingSimulationDialogState extends State<_PingSimulationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat();

    Future.delayed(Duration(seconds: 5), () {
      if (mounted) {
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.w),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Locating Device",
              style: GoogleFonts.poppins(
                fontSize: 18.0.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8.w),
            Text(
              "Sending signal to play alarm...",
              style: GoogleFonts.poppins(
                fontSize: 13.0.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 40.w),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return SizedBox(
                  width: 160.w,
                  height: 160.w,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: (1.0 - _controller.value).clamp(0.0, 1.0),
                        child: Container(
                          width: 60.w + 100 * _controller.value,
                          height: 60.w + 100 * _controller.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryColor.withValues(
                                alpha: 0.4,
                              ),
                              width: 3.w,
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: (1.0 - (_controller.value + 0.33) % 1.0).clamp(
                          0.0,
                          1.0,
                        ),
                        child: Container(
                          width:
                              60.w + 100 * ((_controller.value + 0.33) % 1.0),
                          height:
                              60.w + 100 * ((_controller.value + 0.33) % 1.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryColor.withValues(
                                alpha: 0.5,
                              ),
                              width: 2.w,
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: (1.0 - (_controller.value + 0.66) % 1.0).clamp(
                          0.0,
                          1.0,
                        ),
                        child: Container(
                          width:
                              60.w + 100 * ((_controller.value + 0.66) % 1.0),
                          height:
                              60.w + 100 * ((_controller.value + 0.66) % 1.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryColor.withValues(
                                alpha: 0.7,
                              ),
                              width: 1.5.w,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 72.w,
                        height: 72.w,
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryColor.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 16.w,
                              offset: Offset(0.w, 4.w),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 32.w,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: 40.w),
            SizedBox(
              width: double.infinity,
              height: 48.w,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.w),
                  ),
                ),
                onPressed: widget.onCancel,
                child: Text(
                  "Stop Ping",
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
