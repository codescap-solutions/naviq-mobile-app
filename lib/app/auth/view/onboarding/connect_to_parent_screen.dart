import 'package:child_track/app/auth/view/onboarding/permission_sequence_screen.dart';
import 'package:child_track/app/auth/view/onboarding/deletion_restriction_config_screen.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class ConnectToParentScreen extends StatefulWidget {
  const ConnectToParentScreen({super.key});

  @override
  State<ConnectToParentScreen> createState() => _ConnectToParentScreenState();
}

class _ConnectToParentScreenState extends State<ConnectToParentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _childCodeController = TextEditingController();
  final _childRepo = injector<ChildRepo>();
  bool _isLoading = false;

  @override
  void dispose() {
    _childCodeController.dispose();
    super.dispose();
  }

  Future<void> _connectToParent() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);
      try {
        final childCode = _childCodeController.text.trim().toUpperCase();

        AppLogger.info('Logging in with child code: $childCode');

        // Call child login API
        final response = await _childRepo.childLogin(childCode: childCode);

        if (response.isSuccess) {
          AppLogger.info('Child login successful');

          if (!mounted) return;

          final isAllowDelete = SharedPrefsService().getAllowDelete();

          if (!isAllowDelete) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => const DeletionRestrictionConfigScreen(),
              ),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => const PermissionSequenceScreen(),
              ),
            );
          }
        } else {
          if (mounted) {
            AppSnackbar.showError(context, response.message);
          }
        }
      } catch (e) {
        AppLogger.error('Error connecting to parent: ${e.toString()}');
        if (mounted) {
          AppSnackbar.showError(context, 'Failed to connect: ${e.toString()}');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Where is my code?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '1. Open the Parents App.\n2. Go to the Child settings or Dashboard.\n3. Copy the 6-character code shown under your child\'s name.\n4. Enter that code on this screen.',
          style: GoogleFonts.poppins(height: 1.4),
        ),
        actions: [
          TextButton(
            child: Text('Close', style: GoogleFonts.poppins(color: const Color(0xFF0066FF), fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF0C1D37),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Add Child',
          style: GoogleFonts.poppins(
            fontSize: 20.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Enter Child Code',
                          style: GoogleFonts.poppins(
                            fontSize: 26.0.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0C1D37),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The six didgit code that generated in Parents App',
                          style: GoogleFonts.poppins(
                            fontSize: 14.0.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // How to get code blue box
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFDBEAFE),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDBEAFE),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.people_outline,
                                  color: Color(0xFF0066FF),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'How to get the code?',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14.0.sp,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0C1D37),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.0.sp,
                                          color: const Color(0xFF64748B),
                                          height: 1.4,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        children: [
                                          const TextSpan(text: "Incase you installed kids app first go parents app and "),
                                          TextSpan(
                                            text: "Finish Sign Up",
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0066FF),
                                            ),
                                          ),
                                          const TextSpan(text: " . The 6-character code will appear there."),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Child Code',
                          style: GoogleFonts.poppins(
                            fontSize: 14.0.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0C1D37),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _childCodeController,
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          onChanged: (value) {
                            setState(() {}); // Rebuild to update segment dashes
                          },
                          style: GoogleFonts.poppins(
                            fontSize: 28.0.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0C1D37),
                            letterSpacing: 4,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. KIDS01',
                            hintStyle: GoogleFonts.poppins(
                              color: const Color(0xFF94A3B8),
                              fontSize: 28.0.sp,
                              letterSpacing: 4,
                              fontWeight: FontWeight.bold,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Color(0xFF0C1D37), width: 2.0),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Color(0xFF0C1D37), width: 2.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Color(0xFF0066FF), width: 2.0),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Colors.red, width: 1.0),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Colors.red, width: 2.0),
                            ),
                          ),
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                            LengthLimitingTextInputFormatter(6),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter child code';
                            }
                            if (value.trim().length < 6) {
                              return 'Child code must be exactly 6 characters';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _connectToParent(),
                        ),
                        const SizedBox(height: 12),
                        // 6 segment dashes below code box
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (index) {
                            final isEntered = _childCodeController.text.length > index;
                            return Expanded(
                              child: Container(
                                height: 6,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isEntered ? const Color(0xFF5593F8) : const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 24),
                        // Yellow Note box
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFFDE68A),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '💡 ',
                                style: TextStyle(fontSize: 14.0.sp),
                              ),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.0.sp,
                                      color: const Color(0xFFB45309),
                                      height: 1.4,
                                    ),
                                    children: [
                                      const TextSpan(
                                        text: 'Note: ',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const TextSpan(
                                        text: 'You can add multiple kids by adding in parent app',
                                        style: TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        // Verify Code Button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5593F8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _isLoading ? null : _connectToParent,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    'Verify Code',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16.0.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Help footer link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Can't find the code? ",
                              style: GoogleFonts.poppins(
                                fontSize: 13.0.sp,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            GestureDetector(
                              onTap: _showHelpDialog,
                              child: Text(
                                "Help",
                                style: GoogleFonts.poppins(
                                  fontSize: 13.0.sp,
                                  color: const Color(0xFF5593F8),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Text formatter to convert input to uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
