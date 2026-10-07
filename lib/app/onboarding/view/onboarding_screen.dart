import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.onboardingBackgroundGradient,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.paddingL,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 56),

                        // Brand Logo
                        Image.asset(
                          'assets/images/NaviQ Logo.png',
                          height: 50,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 20),

                        // Heading
                        Text(
                          "Know they're safe, without watching their every move.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 24.0.sp,
                            fontWeight: FontWeight.w700,
                            height: 28 / 24,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 37),

                        // 2x2 Feature Grid using Row + Column with IntrinsicHeight
                        Column(
                          children: [
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: const [
                                  Expanded(
                                    child: FeatureCard(
                                      title: 'Live Location',
                                      description:
                                          'Know exactly where your child is at all times.',
                                      iconAsset:
                                          'assets/icons/onboarding_live_location.svg',
                                      borderColor: Color(0xFFC2D9FF),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: FeatureCard(
                                      title: 'GeoGuard',
                                      description:
                                          'Digital fences around trusted places.',
                                      iconAsset:
                                          'assets/icons/onboarding_geoguard.svg',
                                      borderColor: Color(0xFFEEF0F4),
                                      descriptionColor: Color(0xFF4A5267),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: const [
                                  Expanded(
                                    child: FeatureCard(
                                      title: 'Scroll',
                                      description:
                                          'Control over social media usage',
                                      iconAsset:
                                          'assets/icons/onboarding_scroll.svg',
                                      borderColor: Color(0xFFEEF0F4),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: FeatureCard(
                                      title: 'Route History',
                                      description:
                                          'Review routes from the past 30 days.',
                                      iconAsset:
                                          'assets/icons/onboarding_route_history.svg',
                                      borderColor: Color(0xFFC2D9FF),
                                      titleColor: Color(0xFF0F1320),
                                      shadowBlur: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),

                        // Quick setup description
                        Text(
                          'Quick setup in less than a minute',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12.0.sp,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            letterSpacing: 0.2,
                            color: const Color(0xFF4A5267),
                          ),
                        ),
                        // Figma gap is 70; shrinks on shorter screens so the CTA stays
                        // on-screen.
                        const SizedBox(height: 16),
                        const Spacer(),

                        // Role Selector (Kid/Parent switcher)
                        RoleSelector(
                          selected: _selectedRole,
                          onChanged: (role) {
                            setState(() {
                              _selectedRole = role;
                            });
                          },
                        ),
                        const SizedBox(height: 26),

                        // Let's Get Started Action Button
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 346),
                          child: SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: ElevatedButton(
                              onPressed: () {
                                if (_selectedRole == 'Kid') {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ConnectToParentScreen(),
                                    ),
                                  );
                                } else {
                                  Navigator.of(
                                    context,
                                  ).pushNamed(RouteNames.login);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0069F9),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Let's Get Started",
                                    style: GoogleFonts.poppins(
                                      fontSize: 20.0.sp,
                                      fontWeight: FontWeight.w400,
                                      height: 28 / 20,
                                      letterSpacing: 0.2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Positioned(
                                          left: 7,
                                          top: 4,
                                          child: SvgPicture.asset(
                                            'assets/icons/onboarding_cta_arrow.svg',
                                            width: 10.4621,
                                            height: 17,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Already have an account? Sign In Link
                        Text.rich(
                          TextSpan(
                            text: 'Already have an account? ',
                            style: GoogleFonts.poppins(
                              fontSize: 12.0.sp,
                              fontWeight: FontWeight.w400,
                              height: 20 / 12,
                              letterSpacing: 0.2,
                              color: const Color(0xFF707784),
                            ),
                            children: [
                              TextSpan(
                                text: 'Sign In',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.0.sp,
                                  fontWeight: FontWeight.w400,
                                  height: 20 / 12,
                                  letterSpacing: 0.2,
                                  color: const Color(0xFF0069F9),
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
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
