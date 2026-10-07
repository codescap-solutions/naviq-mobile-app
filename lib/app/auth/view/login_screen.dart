import 'package:child_track/app/auth/view/onboarding/parent_profile_setup_view.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_bloc.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_event.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_state.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_strings.dart';
import 'package:child_track/core/widgets/common_textfield.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.isFromSignIn = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
  final bool isFromSignIn;
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _focusNode = FocusNode();
  final _otpFocusNode = FocusNode();
  bool _isPhoneValid = false;
  bool _agreeToTerms = false;
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
  }

  void _onPhoneChanged() {
    final text = _phoneController.text.trim();
    final isValid = text.length == 10;
    if (isValid != _isPhoneValid) {
      setState(() {
        _isPhoneValid = isValid;
      });
    }

    if (text.length < 10 && _otpSent) {
      setState(() {
        _otpSent = false;
        _otpController.clear();
      });
    }

    // Automatically trigger OTP send when it reaches 10 digits
    if (isValid && !_otpSent) {
      if (!_agreeToTerms) {
        setState(() {
          _agreeToTerms = true;
        });
      }
      _sendOtp();
    }
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _otpController.dispose();
    _focusNode.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthOtpSent) {
          setState(() {
            _otpSent = true;
          });
          AppSnackbar.showSuccess(context, 'OTP sent successfully');
        } else if (state is AuthNewUser) {
          // New user - navigate to Parent Profile setup screen first
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  ParentProfileSetupView(phoneNumber: state.phoneNumber),
            ),
          );
        } else if (state is AuthSuccess) {
          if (state.hasChildren) {
            // User has children - navigate to home screen
            Navigator.of(context).pushNamedAndRemoveUntil(
              RouteNames.home,
              (route) => false,
              arguments: {'initialIndex': state.showProfilesTab ? 3 : 0},
            );
          } else {
            // Existing user with no children - navigate to add child screen
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(RouteNames.addChild, (route) => false);
          }
        } else if (state is AuthNeedsRegistration) {
          // Navigate to registration screen when data is null
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(RouteNames.addChild, (route) => false);
        } else if (state is AuthError) {
          // Show error message
          AppSnackbar.showError(context, state.message);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEDF4FE),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFBFCFE), Color(0xFFEDF4FE)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Column(
            children: [
              _buildCustomAppBar(),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.paddingL,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 38),
                                _buildHeader(),
                                const SizedBox(height: 47),
                                _buildPhoneField(),
                                const SizedBox(height: 10),
                                _buildValidationTip(),
                                _buildOtpField(),
                                const SizedBox(height: AppSizes.spacingL),
                                const Spacer(),
                                _buildTermsCheckbox(),
                                const SizedBox(height: AppSizes.spacingL),
                                _buildActionButton(),
                                _buildResendOtpLink(),
                                const SizedBox(height: 96),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4),
      child: SizedBox(
        height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 27),
                child: GestureDetector(
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/icons/auth_back.png',
                      width: 24,
                      height: 24,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              widget.isFromSignIn ? 'Sign In' : 'Sign Up',
              style: GoogleFonts.poppins(
                fontSize: 24.0.sp,
                fontWeight: FontWeight.w600,
                height: 36 / 24,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verify and Proceed',
          style: GoogleFonts.poppins(
            fontSize: 32.0.sp,
            fontWeight: FontWeight.w700,
            height: 40 / 32,
            color: const Color(0xFF16181A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'No Spams, Just Personalized Notification',
          style: GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w400,
            height: 20 / 12,
            letterSpacing: 0.2,
            color: const Color(0xFF707784),
          ),
        ),
      ],
    );
  }

  TextStyle get _fieldHintStyle => GoogleFonts.poppins(
    fontSize: 16.0.sp,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: const Color(0xFF4A5267),
  );

  Widget _buildPhoneField() {
    return CommonTextField(
      controller: _phoneController,
      focusNode: _focusNode,
      hintText: 'Phone Number',
      hintStyle: _fieldHintStyle,
      fillColor: Colors.white,
      borderColor: Colors.black,
      borderWidth: 0.75,
      borderRadius: 14,
      contentPadding: const EdgeInsets.fromLTRB(41, 18, 24, 18),
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      suffixIcon: _isPhoneValid
          ? Padding(
              padding: const EdgeInsets.only(right: 11),
              child: SvgPicture.asset(
                'assets/icons/auth_phone_valid_check.svg',
                width: 25,
                height: 25,
              ),
            )
          : null,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      validator: (value) {
        if (value == null || value.isEmpty) {
          return AppStrings.phoneNumberRequired;
        }
        if (value.length != 10) {
          return AppStrings.invalidPhoneNumber;
        }
        return null;
      },
      onSubmitted: (_) => _sendOtp(),
    );
  }

  Widget _buildValidationTip() {
    return Padding(
      padding: const EdgeInsets.only(right: 15),
      child: Text(
        'we will generate otp automatically',
        textAlign: TextAlign.right,
        style: GoogleFonts.poppins(
          fontSize: 10.0.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: const Color(0xFF9BA4B5),
        ),
      ),
    );
  }

  Widget _buildTermsCheckbox() {
    final base = GoogleFonts.poppins(
      fontSize: 12.0.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
          child: _buildCheckboxBox(),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 207,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'I agree to the',
                    style: base.copyWith(color: const Color(0xFF4A5267)),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {},
                    child: Text(
                      'Terms of Service',
                      style: base.copyWith(color: const Color(0xFF0069F9)),
                    ),
                  ),
                ],
              ),
              Text.rich(
                TextSpan(
                  text: '&',
                  style: base.copyWith(color: const Color(0xFF4A4A4A)),
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () {},
                        child: Text(
                          ' Privacy Policy',
                          style: base.copyWith(color: const Color(0xFF3461FD)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 24px white box (radius 8) with the Figma inset shadow when unchecked.
  Widget _buildCheckboxBox() {
    return SizedBox(
      width: 24,
      height: 24,
      child: _agreeToTerms
          ? Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0069F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 18,
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.1),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildOtpField() {
    if (!_otpSent) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: CommonTextField(
        controller: _otpController,
        focusNode: _otpFocusNode,
        hintText: AppStrings.otpHint,
        hintStyle: _fieldHintStyle,
        fillColor: Colors.white,
        borderColor: Colors.black,
        borderWidth: 0.75,
        borderRadius: 14,
        contentPadding: const EdgeInsets.fromLTRB(40, 18, 24, 18),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        validator: (value) {
          if (value == null || value.isEmpty) {
            return AppStrings.otpRequired;
          }
          if (value.length != 4) {
            return AppStrings.invalidOtp;
          }
          return null;
        },
        onSubmitted: (_) => _verifyOtp(),
      ),
    );
  }

  Widget _buildResendOtpLink() {
    if (!_otpSent) return const SizedBox.shrink();

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Padding(
          padding: const EdgeInsets.only(top: AppSizes.spacingL),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Didn't receive the OTP? ",
                style: GoogleFonts.poppins(
                  fontSize: 14.0.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF62748E),
                ),
              ),
              GestureDetector(
                onTap: isLoading ? null : _resendOtp,
                child: Text(
                  'Resend OTP',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0066FF),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        final buttonText = _otpSent ? 'Continue' : 'Generate OTP';
        final disabled = isLoading || (!_agreeToTerms && !_otpSent);

        return Align(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 346),
            child: InkWell(
              onTap: disabled ? null : (_otpSent ? _verifyOtp : _sendOtp),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 56,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: disabled
                      ? const Color(0xFF0069F9).withValues(alpha: 0.5)
                      : const Color(0xFF0069F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        buttonText,
                        style: GoogleFonts.poppins(
                          fontSize: 20.0.sp,
                          fontWeight: FontWeight.w400,
                          height: 28 / 20,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _sendOtp() {
    if (!_agreeToTerms) {
      AppSnackbar.showError(
        context,
        'You must agree to the Terms of Service & Privacy Policy',
      );
      return;
    }
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.length == 10) {
      context.read<AuthBloc>().add(SendOtp(phoneNumber: phoneNumber));
    } else {
      AppSnackbar.showError(context, AppStrings.invalidPhoneNumber);
    }
  }

  void _verifyOtp() {
    if (_formKey.currentState?.validate() ?? false) {
      final otp = _otpController.text.trim();
      context.read<AuthBloc>().add(VerifyOtp(otp: otp));
    }
  }

  void _resendOtp() {
    _otpController.clear();
    final phoneNumber = _phoneController.text.trim();
    context.read<AuthBloc>().add(SendOtp(phoneNumber: phoneNumber));
  }
}
