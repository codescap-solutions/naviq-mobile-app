import 'package:child_track/app/auth/view/onboarding/parent_profile_setup_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:child_track/app/auth/view/onboarding/connect_to_parent_screen.dart';
import 'package:child_track/core/constants/app_colors.dart';
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
      backgroundColor: Color(0xFFFFFFFF),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.onboardingBackgroundGradient,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    // 16 so the heading gets Figma's 400px-wide text box; the
                    // card grid adds 8 back to keep its 24px page margin.
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: 56.w),

                        // Brand Logo
                        Image.asset(
                          'assets/images/NaviQ Logo.png',
                          height: 50.w,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: 24.w),

                        // Heading — Figma "Body Large": Poppins Regular 20/28.
                        Text(
                          "Know they're safe, without watching their every move.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 20.0.sp,
                            fontWeight: FontWeight.w400,
                            height: 28 / 20,
                            letterSpacing: 0.2,
                            color: Color(0xFF16181A),
                          ),
                        ),
                        SizedBox(height: 24.w),

                        // 2x2 Feature Grid using Row + Column with IntrinsicHeight
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.w),
                          child: Column(
                            children: [
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: FeatureCard(
                                        title: 'Live Location',
                                        description:
                                            'Know exactly where your child is at all times.',
                                        iconAsset:
                                            'assets/icons/onboarding_live_location.svg',
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    Expanded(
                                      child: FeatureCard(
                                        title: 'GeoGuard',
                                        description:
                                            'Digital fences around trusted places.',
                                        iconAsset:
                                            'assets/icons/onboarding_geoguard.svg',
                                        descriptionColor: Color(0xFF4A5267),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 8.w),
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: FeatureCard(
                                        title: 'Scroll',
                                        description:
                                            'Control over social media usage',
                                        iconAsset:
                                            'assets/icons/onboarding_scroll.svg',
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    Expanded(
                                      child: FeatureCard(
                                        title: 'Route History',
                                        description:
                                            'Review routes from the past 30 days.',
                                        iconAsset:
                                            'assets/icons/onboarding_route_history.svg',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12.w),

                        // Quick setup description
                        Text(
                          'Quick setup in less than a minute',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12.0.sp,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            letterSpacing: 0.2,
                            color: Color(0xFF4A5267),
                          ),
                        ),
                        // Figma gap is 70; shrinks on shorter screens so the CTA stays
                        // on-screen.
                        SizedBox(height: 16.w),
                        Spacer(),

                        // Role Selector (Kid/Parent switcher)
                        RoleSelector(
                          selected: _selectedRole,
                          onChanged: (role) {
                            setState(() {
                              _selectedRole = role;
                            });
                          },
                        ),
                        SizedBox(height: 26.w),

                        // Let's Get Started Action Button
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 346.w),
                          child: SizedBox(
                            width: double.infinity,
                            height: 60.w,
                            child: ElevatedButton(
                              onPressed: () {
                                if (_selectedRole == 'Kid') {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ConnectToParentScreen(),
                                    ),
                                  );
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ParentProfileSetupView(),
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF0069F9),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24.w,
                                  vertical: 16.w,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14.w),
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
                                  SizedBox(width: 8.w),
                                  SizedBox(
                                    width: 24.w,
                                    height: 24.w,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Positioned(
                                          left: 7.w,
                                          top: 4.w,
                                          child: SvgPicture.asset(
                                            'assets/icons/onboarding_cta_arrow.svg',
                                            width: 10.4621.w,
                                            height: 17.w,
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
                        SizedBox(height: 12.w),

                        // Already have an account? Sign In Link
                        Text.rich(
                          TextSpan(
                            text: 'Already have an account? ',
                            style: GoogleFonts.poppins(
                              fontSize: 12.0.sp,
                              fontWeight: FontWeight.w400,
                              height: 20 / 12,
                              letterSpacing: 0.2,
                              color: Color(0xFF707784),
                            ),
                            children: [
                              TextSpan(
                                text: 'Sign In',
                                style: GoogleFonts.poppins(
                                  fontSize: 14.0.sp,
                                  fontWeight: FontWeight.w700,
                                  height: 20 / 14, // keeps the 20px line
                                  letterSpacing: 0.2,
                                  color: Color(0xFF0069F9),
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
                        SizedBox(height: 16.w),
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
