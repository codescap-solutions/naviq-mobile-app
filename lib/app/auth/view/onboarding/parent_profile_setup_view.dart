import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/widgets/common_textfield.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_bloc.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_event.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_state.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/app/auth/view/onboarding/add_kid_view.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class ParentProfileSetupView extends StatefulWidget {
  final String phoneNumber;

  const ParentProfileSetupView({super.key, required this.phoneNumber});

  @override
  State<ParentProfileSetupView> createState() => _ParentProfileSetupViewState();
}

class _ParentProfileSetupViewState extends State<ParentProfileSetupView> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Step 1 Selection: Your Family Structure
  int _selectedFamilyStructureIndex = -1;

  // Step 2 Selection: About Your Lifestyle
  int _selectedLifestyleIndex = -1;

  // Step 2 Name Form Key & Controller
  final _lifestyleFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  String _getParentingSituationValue(int index) {
    switch (index) {
      case 0:
        return 'co_parenting';
      case 1:
        return 'single_mom';
      case 2:
        return 'single_dad';
      case 3:
        return 'guardian';
      default:
        return 'co_parenting';
    }
  }

  String _getParentRoutineValue(int index) {
    switch (index) {
      case 0:
        return 'homemaker';
      case 1:
        return 'working_parent';
      default:
        return 'homemaker';
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_selectedFamilyStructureIndex == -1) return;
      setState(() {
        _currentStep = 1;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      if (_selectedLifestyleIndex == -1) return;
      if (_lifestyleFormKey.currentState?.validate() ?? false) {
        final name = _nameController.text.trim();
        final parentingSituation = _getParentingSituationValue(
          _selectedFamilyStructureIndex,
        );
        final parentRoutine = _getParentRoutineValue(_selectedLifestyleIndex);

        context.read<AuthBloc>().add(
          RegisterUser(
            phoneNumber: widget.phoneNumber,
            name: name,
            parentingSituation: parentingSituation,
            parentRoutine: parentRoutine,
          ),
        );
      }
    }
  }

  void _previousStep() {
    if (_currentStep == 1) {
      setState(() {
        _currentStep = 0;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isContinueEnabled = _currentStep == 0
        ? _selectedFamilyStructureIndex != -1
        : (_selectedLifestyleIndex != -1 &&
              _nameController.text.trim().length >= 2);

    return BlocProvider.value(
      value: injector<AuthBloc>(),
      child: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthSuccess) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AddKidView()),
            );
          } else if (state is AuthError) {
            AppSnackbar.showError(context, state.message);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFBFCFE), Color(0xFFEDF4FE)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: AppSizes.spacingS.w),
                  _buildCustomAppBar(),
                  _buildProgressBar(),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: NeverScrollableScrollPhysics(),
                      children: [
                        _buildFamilyStructureStep(),
                        _buildLifestyleStep(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(AppSizes.paddingL.w),
                    child: _buildContinueButton(isContinueEnabled),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.paddingS.w),
      child: Row(
        children: [
          IconButton(
            onPressed: _previousStep,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: AppColors.textPrimary,
              size: 32.w,
            ),
          ),
          Spacer(),
          Text(
            'Parent profile',
            style: GoogleFonts.poppins(
              fontSize: 18.0.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Spacer(),
          SizedBox(width: 48.w), // Balance spacing with Back button
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.paddingL.w,
        vertical: AppSizes.paddingS.w,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 4.w,
              decoration: BoxDecoration(
                color: Color(0xFF0066FF),
                borderRadius: BorderRadius.circular(2.w),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              height: 4.w,
              decoration: BoxDecoration(
                color: _currentStep >= 1
                    ? Color(0xFF0066FF)
                    : Color(0xFF0066FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2.w),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyStructureStep() {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: AppSizes.paddingL.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: AppSizes.spacingM.w),
          Text(
            'Your Family Structure',
            style: GoogleFonts.poppins(
              fontSize: 12.0.sp,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0066FF),
            ),
          ),
          SizedBox(height: 8.w),
          Text(
            'How would you describe your parenting situation?',
            style: GoogleFonts.oswald(
              fontSize: 22.0.sp,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1D293C),
            ),
          ),
          SizedBox(height: 8.w),
          Text(
            "We'll customise sharing settings and support features around your family.",
            style: GoogleFonts.poppins(
              fontSize: 13.0.sp,
              fontWeight: FontWeight.w500,
              color: Color(0xFF62748E),
            ),
          ),
          SizedBox(height: AppSizes.spacingXL.w),
          ParentOptionCard(
            emoji: '👫',
            title: 'Co-Parenting',
            subtitle: 'You share parenting with a partner or co-parent',
            detailText: 'Shared dashboards & coordinated schedule visibility.',
            tipText:
                "💡 Co-parents save 30 min/day by eliminating 'where are the kids?' check-in calls.",
            themeColor: Color(0xFF0066FF),
            isSelected: _selectedFamilyStructureIndex == 0,
            onTap: () {
              setState(() {
                _selectedFamilyStructureIndex = 0;
              });
            },
          ),
          SizedBox(height: 16.w),
          ParentOptionCard(
            emoji: '👩',
            title: 'Single Mom',
            subtitle: "You're raising your children independently",
            detailText: 'Dedicated emergency SOS & trusted contact shortcuts.',
            tipText:
                "💡 Single parents rely on quick-glance safety updates — we've designed every feature with you in mind.",
            themeColor: Color(0xFF0066FF),
            isSelected: _selectedFamilyStructureIndex == 1,
            onTap: () {
              setState(() {
                _selectedFamilyStructureIndex = 1;
              });
            },
          ),
          SizedBox(height: 16.w),
          ParentOptionCard(
            emoji: '👨',
            title: 'Single Dad',
            subtitle: "You're the primary caregiver for your children",
            detailText:
                'Quick SOS, school pick-up alerts & after-school zones.',
            tipText:
                '💡 Dads who use location tools report 40% less daily stress about child safety.',
            themeColor: Color(0xFF0066FF),
            isSelected: _selectedFamilyStructureIndex == 2,
            onTap: () {
              setState(() {
                _selectedFamilyStructureIndex = 2;
              });
            },
          ),
          SizedBox(height: 16.w),
          ParentOptionCard(
            emoji: '👨',
            title: 'Guardian',
            subtitle: "You're the primary caretaker for your children",
            detailText:
                'Quick SOS, school pick-up alerts & after-school zones.',
            tipText:
                '💡 Dads who use location tools report 40% less daily stress about child safety.',
            themeColor: Color(0xFF0066FF),
            isSelected: _selectedFamilyStructureIndex == 3,
            onTap: () {
              setState(() {
                _selectedFamilyStructureIndex = 3;
              });
            },
          ),
          SizedBox(height: AppSizes.spacingL.w),
        ],
      ),
    );
  }

  Widget _buildLifestyleStep() {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: AppSizes.paddingL.w),
      child: Form(
        key: _lifestyleFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSizes.spacingM.w),
            Text(
              'About Your Lifestyle',
              style: GoogleFonts.poppins(
                fontSize: 12.0.sp,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0066FF),
              ),
            ),
            SizedBox(height: 8.w),
            Text(
              'What best describes your daily routine?',
              style: GoogleFonts.oswald(
                fontSize: 22.0.sp,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1D293C),
              ),
            ),
            SizedBox(height: 8.w),
            Text(
              'This helps us personalise your notification schedule and safety alerts.',
              style: GoogleFonts.poppins(
                fontSize: 13.0.sp,
                fontWeight: FontWeight.w500,
                color: Color(0xFF62748E),
              ),
            ),
            SizedBox(height: AppSizes.spacingXL.w),
            Text(
              'Parent Name',
              style: GoogleFonts.poppins(
                fontSize: 12.0.sp,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D293C),
              ),
            ),
            SizedBox(height: 8.w),
            CommonTextField(
              controller: _nameController,
              hintText: 'Enter parent name',
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                color: Color(0xFF7C8BA0),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                if (value.trim().length < 2) {
                  return 'Name must be at least 2 characters';
                }
                return null;
              },
            ),
            SizedBox(height: AppSizes.spacingXL.w),
            ParentOptionCard(
              emoji: '🏠',
              title: 'Homemaker Parent',
              subtitle:
                  "You're at home full-time — the heart of the household.",
              badgeText: 'Full-time caregiver',
              badgeColor: Color(0xFFFFEAD5),
              badgeTextColor: Color(0xFFD35F00),
              detailText:
                  "We'll set up home-zone alerts & routine check-ins tailored to your day.",
              tipText:
                  '💡 Homemaker parents are often the first responders in their household. SafeNest helps you stay aware without hovering — giving you peace of mind while letting kids build independence.',
              themeColor: Color(0xFFD35F00),
              stat1Value: '76%',
              stat1Label: 'feel safer with real-time location awareness',
              stat2Value: '3×',
              stat2Label: 'faster response to unexpected departures',
              isSelected: _selectedLifestyleIndex == 0,
              onTap: () {
                setState(() {
                  _selectedLifestyleIndex = 0;
                });
              },
            ),
            SizedBox(height: 16.w),
            ParentOptionCard(
              emoji: '💼',
              title: 'Working Parent',
              subtitle:
                  'You balance a career while raising your children every day.',
              badgeText: 'Career + family',
              badgeColor: Color(0xFFE8DDFC),
              badgeTextColor: Color(0xFF7A4AF6),
              detailText:
                  'Priority alerts between meetings & school hours — no noise, just what matters.',
              tipText:
                  '💡 Working parents often feel the tension between being present at work and being present for their kids. SafeNest bridges that gap with smart, quiet alerts — only buzzing when it truly matters.',
              themeColor: Color(0xFF7A4AF6),
              stat1Value: '8×',
              stat1Label: 'average daily location checks by working parents',
              stat2Value: '62%',
              stat2Label: 'report reduced work-day anxiety about child safety',
              isSelected: _selectedLifestyleIndex == 1,
              onTap: () {
                setState(() {
                  _selectedLifestyleIndex = 1;
                });
              },
            ),
            SizedBox(height: AppSizes.spacingL.w),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton(bool isEnabled) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        final bool shouldDisable = !isEnabled || isLoading;
        return InkWell(
          onTap: shouldDisable ? null : _nextStep,
          borderRadius: BorderRadius.circular(16.w),
          child: Container(
            height: 60.w,
            decoration: BoxDecoration(
              color: shouldDisable
                  ? Color(0xFF0066FF).withValues(alpha: 0.5)
                  : Color(0xFF0066FF),
              borderRadius: BorderRadius.circular(16.w),
            ),
            alignment: Alignment.center,
            child: isLoading
                ? SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    _currentStep == 0 ? 'Continue' : 'Register',
                    style: GoogleFonts.poppins(
                      fontSize: 16.0.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class ParentOptionCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String? badgeText;
  final Color? badgeColor;
  final Color? badgeTextColor;
  final String detailText;
  final String tipText;
  final Color themeColor;
  final String? stat1Value;
  final String? stat1Label;
  final String? stat2Value;
  final String? stat2Label;
  final bool isSelected;
  final VoidCallback onTap;

  const ParentOptionCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.badgeText,
    this.badgeColor,
    this.badgeTextColor,
    required this.detailText,
    required this.tipText,
    required this.themeColor,
    this.stat1Value,
    this.stat1Label,
    this.stat2Value,
    this.stat2Label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: isSelected ? themeColor.withValues(alpha: 0.03) : Colors.white,
          borderRadius: BorderRadius.circular(16.w),
          border: Border.all(
            color: isSelected ? themeColor : AppColors.borderColor,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.1),
                    blurRadius: 10.w,
                    offset: Offset(0, 4.w),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4.w,
                    offset: Offset(0, 2.w),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44.w,
                  height: 44.w,
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.w),
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: TextStyle(fontSize: 22.0.sp)),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: GoogleFonts.poppins(
                                fontSize: 14.0.sp,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1D293C),
                              ),
                            ),
                          ),
                          if (badgeText != null) ...[
                            SizedBox(width: 8.w),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8.w,
                                vertical: 4.w,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(8.w),
                              ),
                              child: Text(
                                badgeText!,
                                style: GoogleFonts.poppins(
                                  fontSize: 10.0.sp,
                                  fontWeight: FontWeight.w700,
                                  color: badgeTextColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 4.w),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 12.0.sp,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF62748E),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: isSelected
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 16.w),
                        Container(height: 1, color: AppColors.borderColor),
                        SizedBox(height: 16.w),
                        // Detail Text Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.arrow_right_alt_rounded,
                              color: themeColor,
                              size: 18.w,
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                detailText,
                                style: GoogleFonts.poppins(
                                  fontSize: 12.0.sp,
                                  fontWeight: FontWeight.w500,
                                  color: themeColor,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Optional Stats Block
                        if (stat1Value != null && stat2Value != null) ...[
                          SizedBox(height: 16.w),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: EdgeInsets.all(12.w),
                                  decoration: BoxDecoration(
                                    color: themeColor.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12.w),
                                    border: Border.all(
                                      color: themeColor.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stat1Value!,
                                        style: GoogleFonts.oswald(
                                          fontSize: 22.0.sp,
                                          fontWeight: FontWeight.bold,
                                          color: themeColor,
                                        ),
                                      ),
                                      SizedBox(height: 4.w),
                                      Text(
                                        stat1Label!,
                                        style: GoogleFonts.poppins(
                                          fontSize: 10.0.sp,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF62748E),
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Container(
                                  padding: EdgeInsets.all(12.w),
                                  decoration: BoxDecoration(
                                    color: themeColor.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12.w),
                                    border: Border.all(
                                      color: themeColor.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stat2Value!,
                                        style: GoogleFonts.oswald(
                                          fontSize: 22.0.sp,
                                          fontWeight: FontWeight.bold,
                                          color: themeColor,
                                        ),
                                      ),
                                      SizedBox(height: 4.w),
                                      Text(
                                        stat2Label!,
                                        style: GoogleFonts.poppins(
                                          fontSize: 10.0.sp,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF62748E),
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        SizedBox(height: 16.w),
                        // Expanded Tip / Info Section
                        _WhyThisMattersSection(
                          tipText: tipText,
                          themeColor: themeColor,
                        ),
                      ],
                    )
                  : SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhyThisMattersSection extends StatefulWidget {
  final String tipText;
  final Color themeColor;

  const _WhyThisMattersSection({
    required this.tipText,
    required this.themeColor,
  });

  @override
  State<_WhyThisMattersSection> createState() => _WhyThisMattersSectionState();
}

class _WhyThisMattersSectionState extends State<_WhyThisMattersSection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Row(
            children: [
              Icon(
                _isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF7C8BA0),
                size: 16.w,
              ),
              SizedBox(width: 4.w),
              Text(
                'Why this matters',
                style: GoogleFonts.poppins(
                  fontSize: 11.0.sp,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7C8BA0),
                ),
              ),
              Spacer(),
              Text(
                'How is this used?',
                style: GoogleFonts.poppins(
                  fontSize: 11.0.sp,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF7C8BA0),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _isExpanded
              ? Padding(
                  padding: EdgeInsets.only(top: 8.0.w),
                  child: Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12.w),
                    ),
                    child: Text(
                      widget.tipText,
                      style: GoogleFonts.poppins(
                        fontSize: 12.0.sp,
                        fontWeight: FontWeight.w500,
                        color: widget.themeColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                )
              : SizedBox.shrink(),
        ),
      ],
    );
  }
}
