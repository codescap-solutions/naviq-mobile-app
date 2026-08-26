import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/navigation/current_route_tracker.dart';
import '../../../core/navigation/route_names.dart';
import '../../../core/services/subscription_feature_gate.dart';
import '../../../core/services/subscription_manager.dart';
import 'subscription_popup_sheet.dart';
import '../models/subscription_plan.dart';

/// Persistent floating "upgrade" banner shown on every screen for the Free
/// tier only (per the spec's "All Pages" row). Mounted once, at the
/// `MaterialApp.builder` level, so it survives navigation instead of being
/// scoped to a single screen's Scaffold.
class GlobalUpgradeBanner extends StatefulWidget {
  const GlobalUpgradeBanner({super.key});

  @override
  State<GlobalUpgradeBanner> createState() => _GlobalUpgradeBannerState();
}

class _GlobalUpgradeBannerState extends State<GlobalUpgradeBanner> {
  // Screens where upgrade chrome doesn't belong: auth/onboarding (not
  // signed in yet), splash (nothing to show over), and the child-device SOS
  // screen (subscription is a parent-side concern).
  //
  // '/' covers the splash screen specifically — this claimed to already be
  // excluded (see above), but wasn't: main.dart boots via
  // `MaterialApp(home: SplashScreen())` rather than a named initial route,
  // and Flutter gives a bare `home:` widget the implicit route name '/', not
  // null and not a RouteNames constant. Confirmed live on a fresh install:
  // the banner rendered over the splash screen, before any account exists
  // to have a tier for. Every later screen in the app (Home, Settings,
  // Account, Devices, ...) is reached via plain unnamed MaterialPageRoute
  // pushes, whose route name is null, not '/' — so this only ever matches
  // the one true initial frame, not real content screens.
  static const _excludedRoutes = {
    '/',
    RouteNames.login,
    RouteNames.otp,
    RouteNames.onBoarding,
    RouteNames.sos,
  };

  bool _dismissedThisSession = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SubscriptionManager.instance,
      builder: (context, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: CurrentRouteTracker.currentRouteName,
          builder: (context, routeName, __) {
            return ValueListenableBuilder<bool>(
              valueListenable: CurrentRouteTracker.isModalRouteActive,
              builder: (context, isModalActive, ___) {
                final shouldShow =
                    !_dismissedThisSession &&
                    !isModalActive &&
                    SubscriptionFeatureGate.showsFloatingUpgradeBanner() &&
                    !_excludedRoutes.contains(routeName);
                if (!shouldShow) return const SizedBox.shrink();

                return Positioned(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 88,
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => SubscriptionPopup.show(
                          context,
                          SubscriptionTier.basic,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0066FF), Color(0xFF6F9EFF)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.workspace_premium_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Unlock more with a paid plan',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() {
                                  _dismissedThisSession = true;
                                }),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
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
            );
          },
        );
      },
    );
  }
}
