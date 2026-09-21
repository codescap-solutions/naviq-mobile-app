import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:child_track/app/auth/view/onboarding/connect_to_parent_screen.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/widgets/feature_card.dart';
import 'widgets/role_selector.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String _selectedRole = 'Parent'; // Default to Parent matching screenshot

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.onboardingBackgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.paddingL,
              ).copyWith(bottom: media.padding.bottom + AppSizes.paddingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // Brand Logo
                  Image.asset(
                    'assets/images/NaviQ Logo.png',
                    height: 50,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),

                  // Heading: Keep Your Kids Safe & Connected
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.oswald(
                        fontSize: 30.0.sp,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                      children: const [
                        TextSpan(
                          text: 'Keep Your Kids ',
                          style: TextStyle(color: AppColors.darkNavy),
                        ),
                        TextSpan(
                          text: 'Safe & \nConnected',
                          style: TextStyle(color: AppColors.primaryBlue),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // 2x2 Feature Grid using Row + Column with IntrinsicHeight
                  Column(
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: FeatureCard(
                                title: 'Real-Time Location',
                                description:
                                    'Know exactly where your child is at all times.',
                                icon: Icons.location_on_outlined,
                                borderColor: AppColors.locationBorder,
                                iconBgColor: AppColors.locationIconBg,
                                iconColor: AppColors.locationIcon,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: FeatureCard(
                                title: 'GeoFencing',
                                description:
                                    'Geofences around home, school & trusted places.',
                                icon: Icons.shield_outlined,
                                borderColor: AppColors.geofenceBorder,
                                iconBgColor: AppColors.geofenceIconBg,
                                iconColor: AppColors.geofenceIcon,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: FeatureCard(
                                title: 'Scroll',
                                description: 'Control over social media usage',
                                icon: Icons.notifications_none_outlined,
                                borderColor: AppColors.scrollBorder,
                                iconBgColor: AppColors.scrollIconBg,
                                iconColor: AppColors.scrollIcon,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: FeatureCard(
                                title: 'Activity History',
                                description:
                                    'Review routes from the past 30 days.',
                                icon: Icons.access_time_outlined,
                                borderColor: AppColors.activityBorder,
                                iconBgColor: AppColors.activityIconBg,
                                iconColor: AppColors.activityIcon,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),

                  // Quick setup description
                  Text(
                    'Quick setup in less than a minute',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12.0.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Role Selector (Kid/Parent switcher)
                  RoleSelector(
                    selected: _selectedRole,
                    onChanged: (role) {
                      setState(() {
                        _selectedRole = role;
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Let's Get Started Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_selectedRole == 'Kid') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ConnectToParentScreen(),
                            ),
                          );
                        } else {
                          Navigator.of(context).pushNamed(RouteNames.login);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Let's Get Started",
                            style: GoogleFonts.poppins(
                              fontSize: 16.0.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Already have an account? Sign In Link
                  Text.rich(
                    TextSpan(
                      text: 'Already have an account? ',
                      style: GoogleFonts.poppins(
                        fontSize: 14.0.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                      children: [
                        TextSpan(
                          text: 'Sign In',
                          style: GoogleFonts.poppins(
                            fontSize: 14.0.sp,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryBlue,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              Navigator.of(context).pushNamed(
                                RouteNames.login,
                                arguments: {'isFromSignIn': true},
                              );
                            },
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
