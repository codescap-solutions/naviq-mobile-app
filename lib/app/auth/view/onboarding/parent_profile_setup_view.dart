import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/widgets/common_textfield.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_bloc.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_event.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_state.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/app/auth/view/onboarding/add_kid_view.dart';
import 'package:child_track/app/auth/view/onboarding/parent_all_set_screen.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class ParentProfileSetupView extends StatefulWidget {
  // null: first screen of the sign-up flow, nothing is registered yet; the
  // picks travel on to the Sign Up screen. Set: the number is already
  // verified (Sign In that turned out to be a new user), so register here.
  final String? phoneNumber;

  const ParentProfileSetupView({super.key, this.phoneNumber});

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

  bool get _collectOnly => widget.phoneNumber == null;

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
      if (_collectOnly) {
        final profile = ParentSignUpProfile(
          parentingSituation: _getParentingSituationValue(
            _selectedFamilyStructureIndex,
          ),
          parentRoutine: _getParentRoutineValue(_selectedLifestyleIndex),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ParentAllSetScreen(profile: profile),
          ),
        );
        return;
      }
      if (_lifestyleFormKey.currentState?.validate() ?? false) {
        final name = _nameController.text.trim();
        final parentingSituation = _getParentingSituationValue(
          _selectedFamilyStructureIndex,
        );
        final parentRoutine = _getParentRoutineValue(_selectedLifestyleIndex);

        context.read<AuthBloc>().add(
          RegisterUser(
            phoneNumber: widget.phoneNumber!,
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
              (_collectOnly || _nameController.text.trim().length >= 2));

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

  // Figma header: 52px white back circle + centred title, on the page gradient.
  Widget _buildCustomAppBar() {
    return SizedBox(
      height: 68.w,
      child: Row(
        children: [
          SizedBox(width: 18.w),
          FigmaCircleButton(
            onTap: _previousStep,
            child: Image.asset(
              'assets/icons/auth_back.png',
              width: 24.w,
              height: 24.w,
            ),
          ),
          Expanded(
            child: Text(
              'Parent Profile',
              textAlign: TextAlign.center,
              style: FigmaText.appBarTitle,
            ),
          ),
          SizedBox(width: 18.w + 52.w), // balance the back button
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
              fontSize: 12.0.sp, // Figma Body Small
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
              color: Color(0xFF707784),
            ),
          ),
          SizedBox(height: 8.w),
          Text(
            'How would you describe your parenting situation?',
            style: GoogleFonts.poppins(
              fontSize: 16.0.sp, // Figma Body Medium
              fontWeight: FontWeight.w400,
              height: 24 / 16,
              letterSpacing: 0.2,
              color: Color(0xFF1D293C),
            ),
          ),
          SizedBox(height: AppSizes.spacingXL.w),
          ParentOptionCard(
            emoji: '👫',
            title: 'Co-Parenting',
            iconAsset: 'assets/icons/parent_co_parenting.svg',
            subtitle: 'You share parenting with a partner or co-parent',
            detailText: 'Shared dashboards & coordinated schedule visibility.',
            tipText:
                "💡 Co-parents save 30 min/day by eliminating 'where are the kids?' check-in calls.",
            themeColor: Color(0xFF0066FF),
            isSelected: _selectedFamilyStructureIndex == 0,
            circleIcon: true,
            expandOnSelect: true,
            idleBorder: Color(0xFFDBEAFE),

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
            iconAsset: 'assets/icons/parent_single_mom.svg',
            subtitle: "You're raising your children independently",
            detailText: 'Dedicated emergency SOS & trusted contact shortcuts.',
            tipText:
                "💡 Single parents rely on quick-glance safety updates — we've designed every feature with you in mind.",
            themeColor: Color(0xFF0066FF),
            isSelected: _selectedFamilyStructureIndex == 1,
            circleIcon: true,
            expandOnSelect: true,
            idleBorder: Color(0xFFDBEAFE),
            iconBackground: false,

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
            iconAsset: 'assets/icons/parent_single_dad.svg',
            subtitle: "You're the primary caregiver for your children",
            detailText:
                'Quick SOS, school pick-up alerts & after-school zones.',
            tipText:
                '💡 Dads who use location tools report 40% less daily stress about child safety.',
            themeColor: Color(0xFF0066FF),
            isSelected: _selectedFamilyStructureIndex == 2,
            circleIcon: true,
            expandOnSelect: true,
            idleBorder: Color(0xFFDBEAFE),
            iconBackground: false,

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
            iconAsset: 'assets/icons/parent_guardian.svg',
            subtitle: "You're the primary caretaker for your children",
            detailText:
                'Quick SOS, school pick-up alerts & after-school zones.',
            tipText:
                '💡 Dads who use location tools report 40% less daily stress about child safety.',
            themeColor: Color(0xFF0066FF),
            isSelected: _selectedFamilyStructureIndex == 3,
            circleIcon: true,
            expandOnSelect: true,
            idleBorder: Color(0xFFDBEAFE),

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
              // Figma Body Medium: Poppins Regular 16 / 24, Text/Body/default.
              style: GoogleFonts.poppins(
                fontSize: 16.0.sp,
                fontWeight: FontWeight.w400,
                height: 24 / 16,
                letterSpacing: 0.2,
                color: Color(0xFF43474F),
              ),
            ),
            SizedBox(height: 8.w),
            Text(
              'What best describes your daily routine?',
              // Figma Body Large: Poppins Regular 20 / 28.
              style: GoogleFonts.poppins(
                fontSize: 20.0.sp,
                fontWeight: FontWeight.w400,
                height: 28 / 20,
                letterSpacing: 0.2,
                color: Color(0xFF16181A),
              ),
            ),
            SizedBox(height: AppSizes.spacingXL.w),
            if (!_collectOnly) ...[
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
            ],
            ParentOptionCard(
              emoji: '🏠',
              title: 'Homemaker Parent',
              subtitle:
                  "You're at home full-time — the heart of the household.",
              badgeText: 'Full-time caregiver',
              badgeColor: Colors.transparent,
              badgeTextColor: Color(0xFFE17100),
              detailText:
                  "We'll set up home-zone alerts & routine check-ins tailored to your day.",
              tipText:
                  '💡 Homemaker parents are often the first responders in their household. SafeNest helps you stay aware without hovering — giving you peace of mind while letting kids build independence.',
              themeColor: Color(0xFFE17100),
              figmaBorder: Color(0xFFFFB900),
              circleIcon: true,
              figmaFill: Color(0xFFF7F8FA),
              stat1Value: '76%',
              stat1Label: 'feel safer with real-time awareness',
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
              figmaBorder: Color(0xFFA684FF),
              circleIcon: true,
              figmaFill: Color(0xFFEEF0F4),
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
                    _currentStep == 0 || _collectOnly ? 'Continue' : 'Register',
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
  // Figma: the family-structure cards use a circular icon background, the
  // lifestyle cards keep the rounded square.
  final bool circleIcon;
  // Figma illustration; the emoji is the fallback when there is none.
  final String? iconAsset;
  // false: selecting the card only highlights it (Figma family-structure page).
  final bool expandOnSelect;
  // Lifestyle-page Figma look: 2px themed border, 60% fill, bold 14 title,
  // check mark when selected. Both must be set to switch it on.
  final Color? figmaBorder;
  final Color? figmaFill;
  // Family-structure Figma look (node 3524:8429): 24 radius, 2px border that
  // is `idleBorder` until selected, then blue with a 5% tint + check mark.
  final Color? idleBorder;
  final bool iconBackground;

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
    this.circleIcon = false,
    this.iconAsset,
    this.expandOnSelect = true,
    this.figmaBorder,
    this.figmaFill,
    this.idleBorder,
    this.iconBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final family = idleBorder != null;
    final figma = (figmaBorder != null && figmaFill != null) || family;
    final card = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        padding: EdgeInsets.all(16.w),
        decoration: family
            ? BoxDecoration(
                color: isSelected ? Color(0xFFF2F8FE) : Colors.white,
                borderRadius: BorderRadius.circular(24.w),
                border: Border.all(
                  color: isSelected ? themeColor : idleBorder!,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6.w,
                    offset: Offset(0, 4.w),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4.w,
                    offset: Offset(0, 2.w),
                  ),
                ],
              )
            : figma && figmaBorder != null
            ? BoxDecoration(
                color: figmaFill!.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20.w),
                border: Border.all(color: figmaBorder!, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2.w,
                    spreadRadius: -1,
                    offset: Offset(0, 1.w),
                  ),
                ],
              )
            : BoxDecoration(
                color: isSelected
                    ? themeColor.withValues(alpha: 0.03)
                    : Colors.white,
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
                  width: family ? 54.w : 44.w,
                  height: family ? 55.w : 44.w,
                  decoration: BoxDecoration(
                    color: family && !iconBackground
                        ? null
                        : themeColor.withValues(alpha: 0.1),
                    shape: circleIcon && !family
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                    borderRadius: circleIcon && !family
                        ? null
                        : BorderRadius.circular(family ? 12.w : 12.w),
                  ),
                  alignment: Alignment.center,
                  child: iconAsset != null
                      ? SvgPicture.asset(
                          iconAsset!,
                          height: family
                              ? (iconBackground ? 32.w : 35.w)
                              : 24.w,
                        )
                      : Text(emoji, style: TextStyle(fontSize: 22.0.sp)),
                ),
                SizedBox(width: family ? 16.w : 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: figma
                                  // Lifestyle cards: Poppins Bold 14 / 20.
                                  ? GoogleFonts.poppins(
                                      fontSize: 14.0.sp,
                                      fontWeight: FontWeight.w700,
                                      height: 20 / 14,
                                      color: Color(0xFF1D293C),
                                    )
                                  : GoogleFonts.poppins(
                                      fontSize: 16.0.sp, // Figma Body Medium
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF1D293C),
                                    ),
                            ),
                          ),
                          if (figma && isSelected)
                            Icon(
                              Icons.check_circle_outline_rounded,
                              color: themeColor,
                              size: family ? 18.w : 20.w,
                            ),
                          if (badgeText != null && !figma) ...[
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
                      if (badgeText != null && figma) ...[
                        SizedBox(height: 4.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 2.w,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(20.w),
                            border: Border.all(color: badgeTextColor!),
                          ),
                          child: Text(
                            badgeText!,
                            style: GoogleFonts.poppins(
                              fontSize: 10.0.sp,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.2,
                              color: badgeTextColor,
                            ),
                          ),
                        ),
                      ],
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
              child: isSelected && expandOnSelect
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: family ? 8.w : 16.w),
                        Container(
                          height: 1,
                          color: family
                              ? Color(0xFFE2E8F0)
                              : AppColors.borderColor,
                        ),
                        SizedBox(height: family ? 9.w : 16.w),
                        // Detail Text Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              family
                                  ? Icons.auto_awesome_outlined
                                  : Icons.arrow_right_alt_rounded,
                              color: themeColor,
                              size: family ? 12.w : 18.w,
                            ),
                            SizedBox(width: family ? 6.w : 8.w),
                            Expanded(
                              child: Text(
                                detailText,
                                // Figma Body Small: Poppins Regular 12 / 20.
                                style: GoogleFonts.poppins(
                                  fontSize: 12.0.sp,
                                  fontWeight: family
                                      ? FontWeight.w500
                                      : FontWeight.w400,
                                  height: family ? 16 / 12 : 20 / 12,
                                  letterSpacing: family ? 0 : 0.2,
                                  color: themeColor,
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
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        stat1Value!,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          // Figma: Poppins Regular 18 / 19.8, centred.
                                          fontSize: 18.0.sp,
                                          fontWeight: FontWeight.w400,
                                          height: 19.8 / 18,
                                          letterSpacing: 0,
                                          color: themeColor,
                                        ),
                                      ),
                                      SizedBox(height: 4.w),
                                      Text(
                                        stat1Label!,
                                        textAlign: TextAlign.center,
                                        // Figma: Poppins Regular 10 / 12, centred.
                                        style: GoogleFonts.poppins(
                                          fontSize: 10.0.sp,
                                          fontWeight: FontWeight.w400,
                                          height: 12 / 10,
                                          letterSpacing: 0.2,
                                          color: Color(0xFF62748E),
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
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        stat2Value!,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          // Figma: Poppins Regular 18 / 19.8, centred.
                                          fontSize: 18.0.sp,
                                          fontWeight: FontWeight.w400,
                                          height: 19.8 / 18,
                                          letterSpacing: 0,
                                          color: themeColor,
                                        ),
                                      ),
                                      SizedBox(height: 4.w),
                                      Text(
                                        stat2Label!,
                                        textAlign: TextAlign.center,
                                        // Figma: Poppins Regular 10 / 12, centred.
                                        style: GoogleFonts.poppins(
                                          fontSize: 10.0.sp,
                                          fontWeight: FontWeight.w400,
                                          height: 12 / 10,
                                          letterSpacing: 0.2,
                                          color: Color(0xFF62748E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    )
                  : SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        card,
        SizedBox(height: family ? 12.w : 8.w),
        _WhyThisMattersSection(
          tipText: tipText,
          themeColor: themeColor,
          showHowUsed: stat1Value != null,
          family: family,
        ),
      ],
    );
  }
}

class _WhyThisMattersSection extends StatefulWidget {
  final String tipText;
  final Color themeColor;
  final bool showHowUsed;
  final bool family;

  const _WhyThisMattersSection({
    required this.tipText,
    required this.themeColor,
    this.showHowUsed = false,
    this.family = false,
  });

  @override
  State<_WhyThisMattersSection> createState() => _WhyThisMattersSectionState();
}

class _WhyThisMattersSectionState extends State<_WhyThisMattersSection> {
  // Closed until the user taps it (Figma note).
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final grey = widget.family ? Color(0xFF90A1B9) : Color(0xFF707784);
    final labelStyle = widget.family
        ? GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w500,
            height: 16 / 12,
            color: grey,
          )
        : GoogleFonts.poppins(
            fontSize: 10.0.sp,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
            color: grey,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.family ? 12.w : 4.w,
              vertical: 2.w,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: grey, size: 12.w),
                SizedBox(width: 6.w),
                Text('Why this matters', style: labelStyle),
                if (widget.showHowUsed) ...[
                  Spacer(),
                  Text(
                    'How is this used?',
                    style: labelStyle.copyWith(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _isExpanded
              ? Padding(
                  padding: EdgeInsets.only(top: 8.0.w),
                  child: Container(
                    width: double.infinity,
                    padding: widget.family
                        ? EdgeInsets.fromLTRB(13.w, 12.w, 13.w, 14.w)
                        : EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: widget.family
                          ? Color(0xFFF0FDFA)
                          : widget.themeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        widget.family ? 16.w : 12.w,
                      ),
                      border: widget.family
                          ? Border.all(color: Color(0xFFCBFBF1))
                          : null,
                    ),
                    child: Text(
                      widget.tipText,
                      style: widget.family
                          ? GoogleFonts.poppins(
                              fontSize: 12.0.sp,
                              fontWeight: FontWeight.w400,
                              height: 19.5 / 12,
                              color: Color(0xFF00786F),
                            )
                          : GoogleFonts.poppins(
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
