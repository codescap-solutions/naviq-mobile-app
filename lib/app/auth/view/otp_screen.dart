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

class OtpScreen extends StatefulWidget {
  final String phoneNumber;

  const OtpScreen({super.key, required this.phoneNumber});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _phoneController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _phoneController.text = widget.phoneNumber;
  }

  @override
  void dispose() {
    _otpController.dispose();
    _phoneController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthNewUser) {
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
        backgroundColor: Color(0xFFEDF4FE),
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
                    const SizedBox(height: AppSizes.spacingXL),
                    _buildOtpField(),
                    const SizedBox(height: AppSizes.spacingXXL),
                    _buildVerifyOtpButton(),
                    const SizedBox(height: AppSizes.spacingXL),
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
          'Sign Up',
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
          readOnly: true,
          enabled: false,
          prefixIcon: const Icon(
            Icons.phone_android_rounded,
            color: Color(0xFF7C8BA0),
          ),
          suffixIcon: Container(
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
          ),
        ),
      ],
    );
  }

  Widget _buildOtpField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          focusNode: _focusNode,
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

  Widget _buildVerifyOtpButton() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return InkWell(
          onTap: isLoading ? null : _verifyOtp,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 60,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isLoading
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
                    'Verify and Proceed',
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

  Widget _buildResendOtpLink() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Row(
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
        );
      },
    );
  }

  void _verifyOtp() {
    if (_formKey.currentState?.validate() ?? false) {
      final otp = _otpController.text.trim();
      context.read<AuthBloc>().add(VerifyOtp(otp: otp));
    }
  }

  void _resendOtp() {
    _otpController.clear();
    context.read<AuthBloc>().add(SendOtp(phoneNumber: widget.phoneNumber));
  }
}
