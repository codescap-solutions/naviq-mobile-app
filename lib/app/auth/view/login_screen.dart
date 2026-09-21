import 'package:child_track/app/auth/view/onboarding/parent_profile_setup_view.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_bloc.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_event.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_state.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/constants/app_colors.dart';
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
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.paddingL,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSizes.spacingS),
                    _buildCustomAppBar(),
                    const SizedBox(height: AppSizes.spacingL),
                    _buildHeader(),
                    const SizedBox(height: AppSizes.spacingXXL),
                    _buildPhoneField(),
                    const SizedBox(height: AppSizes.spacingS),
                    _buildValidationTip(),
                    _buildOtpField(),
                    const SizedBox(height: AppSizes.spacingXL),
                    _buildTermsCheckbox(),
                    const SizedBox(height: AppSizes.spacingXXL),
                    _buildActionButton(),
                    _buildResendOtpLink(),
                    const SizedBox(height: AppSizes.spacingXL),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(
            Icons.chevron_left_rounded,
            color: AppColors.textPrimary,
            size: 32,
          ),
        ),
        const Spacer(),
        Text(
          widget.isFromSignIn ? 'Sign In' : 'Sign Up',
          style: GoogleFonts.poppins(
            fontSize: 18.0.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        const SizedBox(
          width: 48,
        ), // Align text to center by balancing the Back button size
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Personalisation',
          style: GoogleFonts.poppins(
            fontSize: 10.0.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0069F8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Verify and Proceed',
          style: GoogleFonts.poppins(
            fontSize: 24.0.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1D293C),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'No Spams, Just Personalized Notification',
          style: GoogleFonts.poppins(
            fontSize: 14.0.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF62748E),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone Number',
          style: GoogleFonts.poppins(
            fontSize: 10.0.sp,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF7C8BA0),
          ),
        ),
        const SizedBox(height: 8),
        CommonTextField(
          controller: _phoneController,
          focusNode: _focusNode,
          hintText: 'Enter device/child code',
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          prefixIcon: const Icon(
            Icons.phone_android_rounded,
            color: Color(0xFF7C8BA0),
          ),
          suffixIcon: _isPhoneValid
              ? Container(
                  margin: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8FAF6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF00C096),
                    size: 16,
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
        ),
      ],
    );
  }

  Widget _buildValidationTip() {
    return Text(
      'we will generate otp automatically',
      style: GoogleFonts.poppins(
        fontSize: 10.0.sp,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF838383),
      ),
    );
  }



  Widget _buildTermsCheckbox() {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _agreeToTerms,
            onChanged: (val) {
              setState(() {
                _agreeToTerms = val ?? false;
              });
            },
            activeColor: const Color(0xFF0066FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            side: const BorderSide(color: Color(0xFFBDBDBD), width: 1.5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'I agree to the ',
                style: GoogleFonts.poppins(
                  fontSize: 12.0.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF494949),
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: Text(
                  'Terms of Service',
                  style: GoogleFonts.poppins(
                    fontSize: 12.0.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF0066FF),
                  ),
                ),
              ),
              Text(
                ' & ',
                style: GoogleFonts.poppins(
                  fontSize: 12.0.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF494949),
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: Text(
                  'Privacy Policy',
                  style: GoogleFonts.poppins(
                    fontSize: 12.0.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF0066FF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtpField() {
    if (!_otpSent) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.spacingXL),
        Text(
          'OTP',
          style: GoogleFonts.poppins(
            fontSize: 10.0.sp,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF7C8BA0),
          ),
        ),
        const SizedBox(height: 8),
        CommonTextField(
          controller: _otpController,
          focusNode: _otpFocusNode,
          hintText: AppStrings.otpHint,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFF7C8BA0)),
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
      ],
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
        final buttonText = _otpSent ? 'Verify and Proceed' : 'Create Account';

        return InkWell(
          onTap: (isLoading || (!_agreeToTerms && !_otpSent))
              ? null
              : (_otpSent ? _verifyOtp : _sendOtp),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 60,
            width: double.infinity,
            decoration: BoxDecoration(
              color: (isLoading || (!_agreeToTerms && !_otpSent))
                  ? const Color(0xFF0066FF).withValues(alpha: 0.5)
                  : const Color(0xFF0066FF),
              borderRadius: BorderRadius.circular(16),
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
                      fontSize: 16.0.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
