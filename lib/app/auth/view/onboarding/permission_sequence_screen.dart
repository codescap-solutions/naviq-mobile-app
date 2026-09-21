import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/services/location_service.dart';
import 'package:child_track/core/services/background_location_service.dart';
import 'package:child_track/core/services/device_info_service.dart';
import 'package:child_track/app/childapp/view_model/repository/device_info_service.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/app/auth/view/onboarding/mapping_context_screen.dart';
import 'package:child_track/app/auth/view/onboarding/app_catalog_screen.dart';
import 'package:child_track/app/auth/view/onboarding/oem_battery_screen.dart';
import 'package:child_track/core/services/oem_battery_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:child_track/core/utils/responsive_font.dart';

enum PermissionStep {
  location,
  notification,
  battery,
  usageData,
  accessibility,
  success,
}

class PermissionSequenceScreen extends StatefulWidget {
  const PermissionSequenceScreen({super.key});

  @override
  State<PermissionSequenceScreen> createState() =>
      _PermissionSequenceScreenState();
}

class _PermissionSequenceScreenState extends State<PermissionSequenceScreen>
    with WidgetsBindingObserver {
  late final List<PermissionStep> _steps;
  int _currentStepIndex = 0;
  final PageController _pageController = PageController();
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Build the permission steps list dynamically based on platform
    if (Platform.isAndroid) {
      _steps = [
        PermissionStep.location,
        PermissionStep.notification,
        PermissionStep.battery,
        PermissionStep.usageData,
        PermissionStep.accessibility,
        PermissionStep.success,
      ];
    } else {
      _steps = [
        PermissionStep.location,
        PermissionStep.notification,
        PermissionStep
            .usageData, // Usage Data on iOS maps to Family Controls / Screen Time Access
        PermissionStep.success,
      ];
    }

    // Run initial permission check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCurrentPermission(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCurrentPermission(silent: true);
    }
  }

  /// Automatically check if current step's permission is already granted.
  /// If it is, advance automatically (with a silent delay to feel smooth).
  Future<void> _checkCurrentPermission({bool silent = false}) async {
    if (_currentStepIndex >= _steps.length) return;
    final step = _steps[_currentStepIndex];

    bool isGranted = false;

    try {
      switch (step) {
        case PermissionStep.location:
          // Only 'always' actually satisfies this step. Accepting
          // whileInUse here let a child pass this screen having only
          // granted foreground location — background_location_service.dart
          // (and the whole point of this app) needs Always, so this used to
          // silently wave the child through to SosView with tracking that
          // would go dark the moment the app backgrounded, matching a real
          // report: "location off aayittum SOS screen il pokunnu."
          // requestAlwaysAllowPermission() in the explicit-tap path below
          // already gets this right (only advances on true 'always');
          // this silent auto-check just hadn't matched that.
          final permission = await Geolocator.checkPermission();
          isGranted = permission == LocationPermission.always;
          break;
        case PermissionStep.notification:
          final status = await Permission.notification.status;
          isGranted = status.isGranted || (Platform.isIOS && status.isProvisional);
          break;
        case PermissionStep.battery:
          isGranted = await Permission.ignoreBatteryOptimizations.isGranted;
          break;
        case PermissionStep.usageData:
          // This step is the *permission* gate only — whether Screen Time
          // authorization (iOS) / usage-access (Android) is granted at the
          // OS level. It used to also require a non-empty getAppMappings()
          // response on iOS, conflating "permission granted" with "the
          // separate app-selection flow (MappingContextScreen/
          // AppCatalogScreen) already finished and synced". Since this
          // check re-runs silently on every app resume
          // (didChangeAppLifecycleState), a child who granted Screen Time
          // but whose mapping save hadn't gone through yet (network hiccup,
          // picked no apps, still mid-flow) got permanently stuck seeing
          // "not granted" and bounced straight back to this same screen —
          // matching a real report of the permission screen looping even
          // after granting it. The explicit "Allow Access" tap below
          // already pushes into the mapping flow as its own separate step
          // once raw authorization is confirmed; that's where mapping
          // completeness belongs, not here.
          isGranted = await injector<ChildInfoService>().checkUsagePermission();
          break;
        case PermissionStep.accessibility:
          isGranted = await injector<DeviceInfoService>()
              .checkAccessibilityPermission();
          break;
        case PermissionStep.success:
          isGranted = true;
          break;
      }
    } catch (e) {
      AppLogger.error('Error checking permission for $step: $e');
    }

    if (isGranted && step != PermissionStep.success) {
      if (mounted) {
        if (silent) {
          // If silent, add a tiny delay to ensure smooth transition
          await Future.delayed(const Duration(milliseconds: 300));
        }
        _advanceToNextStep();
      }
    }
  }

  void _advanceToNextStep() {
    if (_currentStepIndex < _steps.length - 1) {
      setState(() {
        _currentStepIndex++;
      });
      _pageController.animateToPage(
        _currentStepIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      // Landing on the new step doesn't mean it needs asking. Only the
      // very first step in _steps ever got the silent auto-check (from
      // initState) — every step reached by advancing through here never
      // re-ran it, so an already-granted step (e.g. notification, allowed
      // in a previous install) stalled on its own screen waiting for a
      // redundant tap instead of skipping itself. Confirmed live: a child
      // with notification permission already granted still saw/tapped
      // through the notification step on login. Chaining this call lets
      // _checkCurrentPermission recurse through any number of
      // already-granted steps in a row, stopping at the first one that
      // actually needs the user.
      _checkCurrentPermission(silent: true);
    }
  }

  void _goToPreviousStep() {
    if (_currentStepIndex > 0) {
      setState(() {
        _currentStepIndex--;
      });
      _pageController.animateToPage(
        _currentStepIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _handlePermissionRequest() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);

    final step = _steps[_currentStepIndex];

    try {
      switch (step) {
        case PermissionStep.location:
          final locationService = LocationService();
          bool isServiceEnabled = await locationService
              .isLocationServiceEnabled();
          if (!isServiceEnabled) {
            await locationService.openSystemLocationSettings();
            setState(() => _isRequesting = false);
            return;
          }
          final result = await locationService.requestAlwaysAllowPermission();
          final granted = result['granted'] as bool? ?? false;
          final needsSettings = result['needsSettings'] as bool? ?? false;
          if (granted) {
            _advanceToNextStep();
          } else if (needsSettings) {
            await locationService.openLocationSettings();
          }
          break;

        case PermissionStep.notification:
          final status = await Permission.notification.request();
          if (status.isGranted) {
            _advanceToNextStep();
          } else if (status.isPermanentlyDenied) {
            await openAppSettings();
          }
          break;

        case PermissionStep.battery:
          await Permission.ignoreBatteryOptimizations.request();
          // Always advance to make it non-blocking in case of manufacturer restrictions
          _advanceToNextStep();
          break;

        case PermissionStep.usageData:
          if (Platform.isIOS) {
            // First: Request raw Screen Time authorization if not granted
            final authorized = await injector<ChildInfoService>().checkUsagePermission();
            if (!authorized) {
              final granted = await injector<ChildInfoService>().openUsageSettings();
              if (!granted) {
                // User rejected permission request
                return;
              }
            }

            // Screen Time authorization is what this onboarding step gates
            // on — advance right away instead of waiting on app-mapping
            // completion (matches FindMyKids: grant the permission, you're
            // through; picking which apps to monitor is a separate,
            // optional step that can be finished or skipped any time from
            // Settings). This used to block here until getAppMappings()
            // came back non-empty — if the child backed out of
            // AppCatalogScreen with nothing selected (which had no way to
            // continue with zero apps chosen either — see that screen's own
            // fix) or the save failed, they landed back on this exact
            // screen with authorized still true, tapped Allow Access again,
            // and got sent straight back into the same mapping flow —
            // a real reported loop.
            _advanceToNextStep();

            // Still offer app selection immediately while we have their
            // attention, but purely as a bonus — its outcome no longer
            // gates onboarding completion.
            if (mounted) {
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (context) => MappingContextScreen(
                    onContinue: () {
                      Navigator.pushReplacement(
                        context,
                        CupertinoPageRoute(
                          builder: (context) => const AppCatalogScreen(),
                        ),
                      );
                    },
                  ),
                ),
              );
            }
          } else {
            final granted = await injector<ChildInfoService>()
                .checkUsagePermission();
            if (granted) {
              _advanceToNextStep();
            } else {
              await injector<ChildInfoService>().openUsageSettings();
            }
          }
          break;

        case PermissionStep.accessibility:
          final granted = await injector<DeviceInfoService>()
              .checkAccessibilityPermission();
          if (granted) {
            _advanceToNextStep();
          } else {
            await injector<DeviceInfoService>().openAccessibilitySettings();
          }
          break;

        case PermissionStep.success:
          // Complete onboarding, start background service, navigate to SOS View
          try {
            await BackgroundLocationService().start();
            AppLogger.info('Background location service started successfully');
          } catch (e) {
            AppLogger.error('Failed to start background tracking service: $e');
          }

          // Takes the BuildContext to navigate with explicitly, rather than
          // closing over this screen's own context/mounted — when called
          // from OemBatteryScreen's onContinue, this screen has already
          // been pushReplacement'd out (and disposed) by the time the user
          // actually taps a button there, so checking THIS screen's
          // `mounted` would always be false and silently no-op. The caller
          // always passes a context that's valid at the moment it's used.
          void goToSos(BuildContext ctx) {
            // Named route, matching main.dart's own cold-start-into-SosView
            // path via app_router.dart.
            Navigator.of(ctx).pushReplacementNamed(RouteNames.sos);
          }

          // Only relevant on Android — manufacturers with their own
          // background-kill managers beyond stock Doze (see
          // OemBatteryHelper). Unrecognized manufacturers skip straight to
          // SosView with no extra step.
          if (Platform.isAndroid) {
            final oem = await OemBatteryHelper().detectOem();
            if (oem != null && mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => OemBatteryScreen(oem: oem, onContinue: goToSos),
                ),
              );
              break;
            }
          }
          if (mounted) goToSos(context);
          break;
      }
    } catch (e) {
      AppLogger.error('Error requesting permission for $step: $e');
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFE6EFFF), // soft sky blue
              Color(0xFFF1F7FF), // very light blue
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAppBar(),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    return _buildStepContent(_steps[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final isSuccessStep = _currentStepIndex < _steps.length &&
        _steps[_currentStepIndex] == PermissionStep.success;
    if (isSuccessStep) {
      return const SizedBox(height: 30);
    }
    return SizedBox(
      height: 30,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: AppColors.textPrimary,
            ),
            onPressed: _goToPreviousStep,
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(PermissionStep step) {
    if (step == PermissionStep.success) {
      return _buildSuccessStep();
    }

    String title;
    String subtitle;
    String imagePath;
    List<Widget> pills = [];

    switch (step) {
      case PermissionStep.location:
        title = "Location Access";
        subtitle =
            "NaviQ collects location data to enable parental monitoring and safety tracking even when the app is closed or not in use.";
        imagePath = 'assets/images/location-access device-preview (1) 1.png';
        pills = [
          _buildPill("Live Tracking", Icons.location_on_rounded),
          _buildPill("Safe Boundaries", Icons.notifications_active_rounded),
          _buildPill("Encrypted", Icons.lock_rounded),
        ];
        break;
      case PermissionStep.notification:
        title = "Notification Access";
        subtitle =
            "Personalised Alerts only. We'll alert you only when something truly matters changes—no spam, no irrelevant notifications.";
        imagePath = 'assets/images/notification-access-device-preview 1.png';
        pills = [
          _buildPill("No Spam", Icons.check_circle_rounded),
          _buildPill("Smart Alerts", Icons.notifications_active_rounded),
          _buildPill("Personalised", Icons.lock_rounded),
        ];
        break;
      case PermissionStep.battery:
        title = "Battery Access";
        subtitle =
            "Efficient battery use. More accurate background tracking—smart, battery-efficient, with full visibility into usage so you're always informed.";
        imagePath = 'assets/images/battery_access-device-preview 1.png';
        pills = [
          _buildPill("Smart Tracking", Icons.check_circle_rounded),
          _buildPill("Battery Safe", Icons.battery_std_rounded),
          _buildPill("Full Visibility", Icons.lock_rounded),
        ];
        break;
      case PermissionStep.usageData:
        title = Platform.isIOS ? "Screen Time Access" : "Usage Data Access";
        subtitle =
            "Safety ensured power for you. Empowers you to access and block apps from your usage data—no third-party access, full privacy control.";
        imagePath = 'assets/images/usage_data-access-device-preview 1.png';
        pills = [
          _buildPill("No 3rd Party", Icons.lock_rounded),
          _buildPill("Full Control", Icons.settings_rounded),
          _buildPill("Encrypted", Icons.security_rounded),
        ];
        break;
      case PermissionStep.accessibility:
        title = "Accessibility Access";
        subtitle =
            "Personalised Alerts only. Enables app usage monitoring via accessibility—your data stays private, no third-party access, full control assured.";
        imagePath = 'assets/images/accebility-service-access.png';
        pills = [
          _buildPill("Private", Icons.check_circle_rounded),
          _buildPill("Full Control", Icons.settings_rounded),
          _buildPill("No Sharing", Icons.lock_rounded),
        ];
        break;
      default:
        title = "";
        subtitle = "";
        imagePath = "";
    }

    return Stack(
      children: [
        // Top Half: preview device PNG positioned at top and extending downwards
        Positioned(
          top: -20, // push it slightly up to align nicely below the back button
          left: 0,
          right: 0,
          bottom:
              120, // allows the bottom portion to extend far below the white card top edge
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.broken_image,
                  size: 64,
                  color: Colors.grey,
                );
              },
            ),
          ),
        ),

        // Bottom Half: White Card overlapping the device image
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Overlapping floating permission icon
                Positioned(top: -28, left: 28, child: _buildFloatingIcon(step)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 42, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 22.0.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Subtitle
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5.sp,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF475569),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Pills/Badges row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: pills.map((pill) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: pill,
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Color(0xFFF1F5F9), height: 1),
                      const SizedBox(height: 16),

                      // How it works info and step dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFF0F172A),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "How does it work",
                                style: GoogleFonts.poppins(
                                  fontSize: 13.0.sp,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          _buildStepDots(),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Action Buttons Row
                      Row(
                        children: [
                          // Skip Button
                          SizedBox(
                            width: 100,
                            height: 52,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _isRequesting
                                  ? null
                                  : _advanceToNextStep,
                              child: Text(
                                "Skip",
                                style: GoogleFonts.poppins(
                                  fontSize: 15.0.sp,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Allow Access Button
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0066FF),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: _isRequesting
                                    ? null
                                    : _handlePermissionRequest,
                                child: _isRequesting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        "Allow Access",
                                        style: GoogleFonts.poppins(
                                          fontSize: 15.0.sp,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingIcon(PermissionStep step) {
    IconData iconData;
    Widget? badge;

    switch (step) {
      case PermissionStep.location:
        iconData = Icons.location_on_rounded;
        break;
      case PermissionStep.notification:
        iconData = Icons.notifications_rounded;
        badge = Positioned(
          top: 6,
          right: 6,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
            child: Text(
              "3",
              style: TextStyle(
                color: Colors.white,
                fontSize: 8.0.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        break;
      case PermissionStep.battery:
        iconData = Icons.battery_std_rounded;
        break;
      case PermissionStep.usageData:
        iconData = Icons.bar_chart_rounded;
        break;
      case PermissionStep.accessibility:
        iconData = Icons.accessibility_new_rounded;
        break;
      default:
        iconData = Icons.check_circle_rounded;
    }

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0066FF).withValues(alpha: 0.12),
            blurRadius: 12,
            spreadRadius: 4,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(iconData, color: const Color(0xFF0066FF), size: 26),
          if (badge != null) badge,
        ],
      ),
    );
  }

  Widget _buildPill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF0066FF).withValues(alpha: 0.18),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF0066FF), size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12.0.sp,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0066FF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDots() {
    final totalDots = _steps.length - 1; // success step doesn't count
    if (_currentStepIndex >= totalDots) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalDots, (index) {
        final isActive = index == _currentStepIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(left: 4),
          width: isActive ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0066FF) : const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildSuccessStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 2),
                    
                    // Title
                    Text(
                      "All Set!",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 32.0.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Subtitle
                    Text(
                      "Your security and privacy settings\nare now configured.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 15.0.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                    
                    const Spacer(flex: 2),
                    
                    // White card containing details
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFEFF2F6), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildSuccessRow(
                            icon: Icons.lock_outline_rounded,
                            title: "Security",
                            subtitle: "Your account is protected",
                          ),
                          const Divider(color: Color(0xFFEFF2F6), height: 1, indent: 16, endIndent: 16),
                          _buildSuccessRow(
                            icon: Icons.visibility_outlined,
                            title: "Privacy",
                            subtitle: "Your information is private",
                          ),
                          const Divider(color: Color(0xFFEFF2F6), height: 1, indent: 16, endIndent: 16),
                          _buildSuccessRow(
                            icon: Icons.shield_outlined,
                            title: "Permissions",
                            subtitle: "App access is set",
                          ),
                        ],
                      ),
                    ),
                    
                    const Spacer(flex: 3),
                    
                    // Celebration Text
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "🎉 ",
                          style: GoogleFonts.poppins(fontSize: 14.0.sp),
                        ),
                        Text(
                          "You're ready to use the app securely!",
                          style: GoogleFonts.poppins(
                            fontSize: 14.0.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Go Home Button
                    SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0066FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isRequesting ? null : _handlePermissionRequest,
                        icon: const Icon(Icons.home_outlined, color: Colors.white, size: 20),
                        label: Text(
                          "Go Home",
                          style: GoogleFonts.poppins(
                            fontSize: 15.0.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                        ),
                      ),
                    ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Watch Tutorial Button
                    SizedBox(
                      height: 54,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF0F172A), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: Colors.transparent,
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Tutorial coming soon!"),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_arrow_outlined, color: Color(0xFF0F172A), size: 20),
                        label: Text(
                          "Watch Tutorial",
                          style: GoogleFonts.poppins(
                            fontSize: 15.0.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 1),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuccessRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Row(
        children: [
          // Icon Container
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: const Color(0xFF3B82F6),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // Texts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          // Checkmark
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF10B981),
            size: 24,
          ),
        ],
      ),
    );
  }
}
