import 'package:child_track/app/auth/view/onboarding/parent_all_set_screen.dart';
import 'package:child_track/app/auth/view/onboarding/parent_profile_setup_view.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_bloc.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_event.dart';
import 'package:child_track/app/auth/view_model/bloc/auth_state.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_strings.dart';
import 'package:child_track/core/widgets/common_textfield.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/widgets/figma_primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.isFromSignIn = false, this.profile});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
  final bool isFromSignIn;
  // Set when arriving from the sign-up flow: adds the name field and registers
  // these answers if the verified number is new.
  final ParentSignUpProfile? profile;
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();
  final _focusNode = FocusNode();
  final _otpFocusNode = FocusNode();
  bool _isPhoneValid = false;
  bool _agreeToTerms = false;
  bool _otpSent = false;
  bool _nameError = false;

  bool get _askName => widget.profile != null;
  bool get _nameValid => _nameController.text.trim().length >= 2;

  // Resend is locked for a while after every send, so it can't be spammed.
  static const _resendCooldown = 30;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = _resendCooldown);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendSeconds <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
    _nameController.addListener(_onNameChanged);
  }

  // Number typed before the name: send as soon as the name is long enough.
  void _onNameChanged() {
    final valid = _nameValid;
    if (_nameError && valid) _nameError = false;
    if (valid && _isPhoneValid && !_otpSent) {
      if (!_agreeToTerms) _agreeToTerms = true;
      _sendOtp();
    }
    setState(() {});
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

    // Automatically trigger OTP send when it reaches 10 digits (and, on
    // sign-up, a name has been typed first)
    if (isValid && !_otpSent && (!_askName || _nameValid)) {
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
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _focusNode.dispose();
    _otpFocusNode.dispose();
    _resendTimer?.cancel();
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
          _startResendCooldown();
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _otpFocusNode.requestFocus(),
          );
          AppSnackbar.showSuccess(context, 'OTP sent successfully');
        } else if (state is AuthNewUser && widget.profile != null) {
          // Sign-up flow: profile already answered, create the account now.
          context.read<AuthBloc>().add(
            RegisterUser(
              phoneNumber: state.phoneNumber,
              name: _nameController.text.trim(),
              parentingSituation: widget.profile!.parentingSituation,
              parentRoutine: widget.profile!.parentRoutine,
            ),
          );
        } else if (state is AuthNewUser) {
          // New user from Sign In - collect the profile first
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
          decoration: BoxDecoration(
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
                      physics: ClampingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSizes.paddingL.w,
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
                                SizedBox(height: 38.w),
                                _buildHeader(),
                                SizedBox(height: 47.w),
                                if (_askName) ...[
                                  _buildNameField(),
                                  SizedBox(height: 16.w),
                                ],
                                _buildPhoneField(),
                                SizedBox(height: 10.w),
                                _buildValidationTip(),
                                _buildOtpField(),
                                _buildResendOtp(),
                                SizedBox(height: AppSizes.spacingL.w),
                                Spacer(),
                                _buildTermsCheckbox(),
                                SizedBox(height: AppSizes.spacingL.w),
                                _buildActionButton(),
                                SizedBox(height: 96.w),
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
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4.w),
      child: SizedBox(
        height: 72.w,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 27.w),
                child: GestureDetector(
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Container(
                    width: 52.w,
                    height: 52.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 2.w,
                          offset: Offset(0, 4.w),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/icons/auth_back.png',
                      width: 24.w,
                      height: 24.w,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              widget.isFromSignIn ? 'Sign In' : 'Sign Up',
              style: FigmaText.poppins(
                24,
                weight: FontWeight.w600,
                lineHeight: 36,
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
          // Figma HD 03: Poppins Bold 24 / 28, Heading/900.
          style: FigmaText.poppins(
            24,
            weight: FontWeight.w700,
            lineHeight: 28,
            color: const Color(0xFF0F1320),
          ),
        ),
        SizedBox(height: 4.w),
        Text(
          'No Spams, Just Personalized Notification',
          style: FigmaText.poppins(
            12,
            lineHeight: 20,
            letterSpacing: 0.2,
            color: const Color(0xFF707784),
          ),
        ),
      ],
    );
  }

  TextStyle get _fieldHintStyle =>
      FigmaText.input.copyWith(color: FigmaColors.body);

  Widget _buildNameField() {
    return CommonTextField(
      controller: _nameController,
      hintText: _nameError ? 'Please enter name' : 'Enter your name',
      hintStyle: _nameError
          ? _fieldHintStyle.copyWith(color: Colors.red)
          : _fieldHintStyle,
      fillColor: Colors.white,
      borderColor: _nameError ? Colors.red : Colors.black,
      borderWidth: 0.75,
      borderRadius: 14,
      contentPadding: EdgeInsets.fromLTRB(41.w, 18.w, 24.w, 18.w),
      keyboardType: TextInputType.name,
      textInputAction: TextInputAction.next,
    );
  }

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
      contentPadding: EdgeInsets.fromLTRB(41.w, 18.w, 24.w, 18.w),
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      suffixIcon: _isPhoneValid
          ? Padding(
              padding: EdgeInsets.only(right: 11.w),
              // Figma: 25 x 25. The suffix slot hands its child tight 48px
              // constraints, so the Align is what lets the icon stay 25.
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                child: SizedBox(
                  width: 25.w,
                  height: 25.w,
                  child: SvgPicture.asset(
                    'assets/icons/auth_phone_valid_check.svg',
                    fit: BoxFit.contain,
                  ),
                ),
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
      padding: EdgeInsets.only(right: 15.w),
      child: Text(
        // Once the OTP has gone out the number is confirmed good.
        _otpSent
            ? 'phone number is correct'
            : 'we will generate otp automatically',
        textAlign: TextAlign.right,
        // Figma Body Small: Poppins Regular 12 / 20, letter spacing 0.2.
        style: FigmaText.poppins(
          12,
          lineHeight: 20,
          letterSpacing: 0.2,
          color: const Color(0xFF9BA4B5),
        ),
      ),
    );
  }

  Widget _buildTermsCheckbox() {
    final base = FigmaText.poppins(
      12,
      weight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
          child: _buildCheckboxBox(),
        ),
        SizedBox(width: 12.w),
        SizedBox(
          width: 207.w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'I agree to the',
                    style: base.copyWith(color: FigmaColors.body),
                  ),
                  SizedBox(width: 4.w),
                  GestureDetector(
                    onTap: () {},
                    child: Text(
                      'Terms of Service',
                      style: base.copyWith(color: FigmaColors.primary),
                    ),
                  ),
                ],
              ),
              Text.rich(
                TextSpan(
                  text: '&',
                  style: base.copyWith(color: Color(0xFF4A4A4A)),
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () {},
                        child: Text(
                          ' Privacy Policy',
                          style: base.copyWith(color: Color(0xFF3461FD)),
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
      width: 24.w,
      height: 24.w,
      child: _agreeToTerms
          ? Container(
              decoration: BoxDecoration(
                color: FigmaColors.primary,
                borderRadius: BorderRadius.circular(8.w),
              ),
              child: Icon(Icons.check_rounded, color: Colors.white, size: 18.w),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.w),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.w),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.w),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.1),
                        width: 3.w,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildOtpField() {
    if (!_otpSent) return SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: 22.w),
      child: CommonTextField(
        controller: _otpController,
        focusNode: _otpFocusNode,
        hintText: AppStrings.otpHint,
        hintStyle: _fieldHintStyle,
        fillColor: Colors.white,
        borderColor: Colors.black,
        borderWidth: 0.75,
        borderRadius: 14,
        contentPadding: EdgeInsets.fromLTRB(40.w, 18.w, 24.w, 18.w),
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

  /// "Resend" under the OTP field, right-aligned like the hint above it
  /// (Figma). Counts down before it can be used again.
  Widget _buildResendOtp() {
    if (!_otpSent) return SizedBox.shrink();

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final canResend = _resendSeconds == 0 && state is! AuthLoading;
        return Padding(
          padding: EdgeInsets.only(top: 8.w, right: 15.w),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canResend ? _resendOtp : null,
              child: Text(
                _resendSeconds > 0 ? 'Resend in ${_resendSeconds}s' : 'Resend',
                style: FigmaText.bodySmall.copyWith(
                  color: canResend
                      ? const Color(0xFF4A5267)
                      : const Color(0xFF9BA4B5),
                ),
              ),
            ),
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
            constraints: BoxConstraints(maxWidth: 346.w),
            child: FigmaPrimaryButton(
              label: buttonText,
              height: 56,
              radius: 14,
              isLoading: isLoading,
              onPressed: disabled ? null : (_otpSent ? _verifyOtp : _sendOtp),
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
    if (_askName && !_nameValid) {
      setState(() => _nameError = true);
      AppSnackbar.showError(context, 'Please enter your name');
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
