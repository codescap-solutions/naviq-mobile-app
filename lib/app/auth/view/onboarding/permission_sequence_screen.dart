import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/app/auth/view/onboarding/all_set_content.dart';

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
  // "How does it work" panel; closed again whenever the step changes.
  bool _showHow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Build the permission steps list dynamically based on platform
    if (Platform.isAndroid) {
      _steps = [
        PermissionStep.notification,
        PermissionStep.battery,
        PermissionStep.usageData,
        PermissionStep.accessibility,
        PermissionStep.success,
      ];
    } else {
      _steps = [
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
          isGranted =
              status.isGranted || (Platform.isIOS && status.isProvisional);
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
          await Future.delayed(Duration(milliseconds: 300));
        }
        _advanceToNextStep();
      }
    }
  }

  void _advanceToNextStep() {
    if (_currentStepIndex < _steps.length - 1) {
      setState(() {
        _currentStepIndex++;
        _showHow = false;
      });
      _pageController.animateToPage(
        _currentStepIndex,
        duration: Duration(milliseconds: 400),
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
        _showHow = false;
      });
      _pageController.animateToPage(
        _currentStepIndex,
        duration: Duration(milliseconds: 400),
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
            final authorized = await injector<ChildInfoService>()
                .checkUsagePermission();
            if (!authorized) {
              final granted = await injector<ChildInfoService>()
                  .openUsageSettings();
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
                          builder: (context) => AppCatalogScreen(),
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
                  builder: (_) =>
                      OemBatteryScreen(oem: oem, onContinue: goToSos),
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
    final isSuccessStep =
        _currentStepIndex < _steps.length &&
        _steps[_currentStepIndex] == PermissionStep.success;
    // The Figma permission screens have no back arrow: the system back
    // gesture / button steps back through the permissions instead.
    return PopScope(
      canPop: _currentStepIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToPreviousStep();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Container(
          decoration: isSuccessStep
              ? BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE6EFFF), Color(0xFFF1F7FF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                )
              : null,
          child: SafeArea(
            child: PageView.builder(
              controller: _pageController,
              physics: NeverScrollableScrollPhysics(),
              itemCount: _steps.length,
              itemBuilder: (context, index) {
                return _buildStepContent(_steps[index]);
              },
            ),
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
    // Figma sub-copy is two-tone: a dark lead sentence, then a grey rest.
    String lead;
    String rest = '';
    String imagePath;
    List<Widget> pills = [];

    switch (step) {
      case PermissionStep.location:
        title = "Location Access";
        lead = "We just wanna be accurate. No data sharing or theft.";
        imagePath = 'assets/images/onboarding_perm_location.png';
        pills = [
          _buildPill("No Data Sharing", Icons.verified_user_rounded),
          _buildPill("Encryption", Icons.lock_rounded),
          _buildPill("Optimised battery use", Icons.battery_std_rounded),
        ];
        break;
      case PermissionStep.notification:
        title = "Notification Access";
        lead = "Personalised Alerts only.";
        rest = " We'll alert you only when something truly matters";
        imagePath = 'assets/images/onboarding_perm_notification.png';
        pills = [
          _buildPill("No Spam", Icons.verified_user_rounded),
          _buildPill("Smart Alerts", Icons.notifications_rounded),
          _buildPill("Personalised", Icons.lock_rounded),
        ];
        break;
      case PermissionStep.battery:
        title = "Battery Access";
        lead = "Efficient battery use.";
        rest = " More accurate background tracking";
        imagePath = 'assets/images/onboarding_perm_battery.png';
        pills = [
          _buildPill("Smart Tracking", Icons.verified_user_rounded),
          _buildPill("Battery Life", Icons.battery_std_rounded),
          _buildPill("Full Visibility", Icons.lock_rounded),
        ];
        break;
      case PermissionStep.usageData:
        title = Platform.isIOS ? "Screen Time Access" : "Usage Data Access";
        lead = "Safety ensured power for you.";
        rest =
            " Empowers you to access and block apps from your usage data—no third-party access, full privacy control.";
        imagePath = 'assets/images/usage_data-access-device-preview 1.png';
        pills = [
          _buildPill("No 3rd Party", Icons.lock_rounded),
          _buildPill("Full Control", Icons.settings_rounded),
          _buildPill("Encrypted", Icons.security_rounded),
        ];
        break;
      case PermissionStep.accessibility:
        title = "Accessibility Access";
        lead = "Personalised Alerts only.";
        rest =
            " Enables app usage monitoring via accessibility—your data stays private, no third-party access, full control assured.";
        imagePath = 'assets/images/accebility-service-access.png';
        pills = [
          _buildPill("Private", Icons.verified_user_rounded),
          _buildPill("Full Control", Icons.settings_rounded),
          _buildPill("No Sharing", Icons.lock_rounded),
        ];
        break;
      default:
        title = "";
        lead = "";
        imagePath = "";
    }

    final how = switch (step) {
      PermissionStep.location =>
        'NaviQ uses your location only to show your parents you are safe and to '
            'alert them about safe places. Choose "Always" so it keeps working '
            'when the app is closed.',
      PermissionStep.notification =>
        'You get a heads-up when your parent changes a limit, answers your '
            'time request or a safety alert fires. No spam, only what matters.',
      PermissionStep.battery =>
        'Phones pause background apps to save battery. Allowing this keeps '
            'tracking and app blocking working even when the screen is off.',
      PermissionStep.usageData =>
        Platform.isIOS
            ? 'Screen Time access lets NaviQ see which apps are used and apply '
                  'the limits your parent sets. It stays on your device and is '
                  'never shared.'
            : 'Usage access lets NaviQ see how long each app is used so your '
                  "parent's time limits work. It is never shared with anyone.",
      PermissionStep.accessibility =>
        'Accessibility lets NaviQ notice which app or site is open so it can '
            'block locked apps and adult content. It never reads your messages '
            'or passwords.',
      _ => '',
    };

    final subtitleStyle = FigmaText.poppins(
      16,
      lineHeight: 24,
      letterSpacing: 0.2,
      color: Color(0xFF43474F),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Illustration: full width under the status bar (Figma 428 x 375).
        Expanded(
          child: Image.asset(
            imagePath,
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stackTrace) {
              return Icon(Icons.broken_image, size: 64.w, color: Colors.grey);
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          // stretch: the Allow Access button and the dots row need the full
          // width; the icon is aligned left explicitly.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _buildFloatingIcon(step),
              ),
              SizedBox(height: 12.w),
              // Figma Heading H2: Poppins Bold 32 / 40.
              Text(
                title,
                style: FigmaText.poppins(
                  32,
                  weight: FontWeight.w700,
                  lineHeight: 40,
                  color: Color(0xFF0F1320),
                ),
              ),
              SizedBox(height: 4.w),
              // Figma Body Medium: Poppins Regular 16 / 24, 0.2 spacing.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: lead,
                      style: subtitleStyle.copyWith(color: FigmaColors.ink),
                    ),
                    if (rest.isNotEmpty)
                      TextSpan(
                        text: rest,
                        style: subtitleStyle.copyWith(color: Color(0xFF707784)),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 16.w),
              Wrap(spacing: 10.w, runSpacing: 10.w, children: pills),
              SizedBox(height: 28.w),

              // How it works info and step dots
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _showHow = !_showHow),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: FigmaColors.ink,
                          size: 20.w,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          "How does it work",
                          style: FigmaText.poppins(
                            12,
                            lineHeight: 20,
                            letterSpacing: 0.2,
                            color: Color(0xFF2D3035),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStepDots(),
                ],
              ),
              AnimatedSize(
                duration: Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _showHow && how.isNotEmpty
                    ? Container(
                        margin: EdgeInsets.only(top: 12.w),
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: Color(0xFFBBEBCE),
                          borderRadius: BorderRadius.circular(16.w),
                        ),
                        child: Text(
                          how,
                          style: FigmaText.poppins(
                            12,
                            lineHeight: 20,
                            letterSpacing: 0.2,
                            color: FigmaColors.ink,
                          ),
                        ),
                      )
                    : SizedBox(width: double.infinity),
              ),
              SizedBox(height: 16.w),

              // Allow Access: solid blue, 56 high, 14 radius.
              SizedBox(
                height: 56.w,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FigmaColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.w),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isRequesting ? null : _handlePermissionRequest,
                  child: _isRequesting
                      ? SizedBox(
                          width: 20.w,
                          height: 20.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text(
                          "Allow Access",
                          style: FigmaText.poppins(
                            20,
                            lineHeight: 28,
                            letterSpacing: 0.2,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 8.w),
              // Skip: plain text under the button.
              Center(
                child: TextButton(
                  onPressed: _isRequesting ? null : _advanceToNextStep,
                  child: Text(
                    "Skip",
                    style: FigmaText.poppins(
                      18,
                      lineHeight: 28,
                      letterSpacing: 0.2,
                      color: Color(0xFF4A5267),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8.w),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingIcon(PermissionStep step) {
    IconData iconData;
    switch (step) {
      case PermissionStep.location:
        iconData = Icons.location_on_outlined;
        break;
      case PermissionStep.notification:
        iconData = Icons.notifications_none_rounded;
        break;
      case PermissionStep.battery:
        iconData = Icons.battery_charging_full_rounded;
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

    // Figma: 62px pale-blue circle, outlined blue glyph.
    return Container(
      width: 62.w,
      height: 62.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFEAF2FF), Color(0xFFD5E5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(iconData, color: FigmaColors.primary, size: 28.w),
    );
  }

  /// Outlined blue pill, Figma Body Small (Poppins Regular 12 / 20).
  Widget _buildPill(String text, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40.w),
        border: Border.all(color: FigmaColors.primary, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: FigmaColors.primary, size: 13.w),
          SizedBox(width: 6.w),
          Text(
            text,
            style: FigmaText.poppins(
              12,
              lineHeight: 20,
              letterSpacing: 0.2,
              color: FigmaColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDots() {
    final totalDots = _steps.length - 1; // success step doesn't count
    if (_currentStepIndex >= totalDots) return SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalDots, (index) {
        final isActive = index == _currentStepIndex;
        return AnimatedContainer(
          duration: Duration(milliseconds: 300),
          margin: EdgeInsets.only(left: 6.w),
          width: isActive ? 24.w : 6.w,
          height: 6.w,
          decoration: BoxDecoration(
            color: isActive ? FigmaColors.ink : Color(0xFFD5D6D9),
            borderRadius: BorderRadius.circular(3.w),
          ),
        );
      }),
    );
  }

  Widget _buildSuccessStep() {
    return AllSetContent(
      onGoHome: _isRequesting ? null : _handlePermissionRequest,
    );
  }
}
