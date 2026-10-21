import 'package:child_track/app/auth/view/onboarding/permission_sequence_screen.dart';
import 'package:child_track/app/auth/view/onboarding/deletion_restriction_config_screen.dart';
import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';

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
                builder: (_) => DeletionRestrictionConfigScreen(),
              ),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => PermissionSequenceScreen()),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.w),
        ),
        title: Text('Where is my code?', style: FigmaText.dialogTitle),
        content: Text(
          '1. Open the Parents App.\n2. Go to the Child settings or Dashboard.\n3. Copy the 6-character code shown under your child\'s name.\n4. Enter that code on this screen.',
          style: FigmaText.dialogBody,
        ),
        actions: [
          TextButton(
            child: Text(
              'Close',
              style: FigmaText.dialogAction.copyWith(color: Color(0xFF0066FF)),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F8FE),
      // Figma: 52px white back circle with an arrow, centred Bold title, on
      // the same near-white blue as the page.
      appBar: figmaAppBar(context, title: 'Add Child'),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFAFCFE), Color(0xFFF5F8FE)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(22.w, 20.w, 22.w, 24.w),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 44,
                  ),
                  child: IntrinsicHeight(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enter Child Code',
                            style: GoogleFonts.poppins(
                              fontSize: 24.0.sp,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF16181A),
                            ),
                          ),
                          SizedBox(height: 6.w),
                          Text(
                            'The six didgit code that generated in Parents App',
                            style: GoogleFonts.poppins(
                              fontSize: 14.0.sp,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF4A5267),
                            ),
                          ),
                          SizedBox(height: 24.w),
                          // How to get code blue box
                          Container(
                            padding: EdgeInsets.all(16.w),
                            decoration: BoxDecoration(
                              color: Color(0xFFEFF7FF),
                              borderRadius: BorderRadius.circular(16.w),
                              border: Border.all(
                                color: Color(0xFFD9E6F8),
                                width: 1.5.w,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 30.w,
                                  height: 30.w,
                                  decoration: BoxDecoration(
                                    color: Color(0xFFD9EAFF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.people_outline,
                                    color: Color(0xFF0069F9),
                                    size: 16.w,
                                  ),
                                ),
                                SizedBox(width: 16.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'How to get the code?',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14.0.sp,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF16181A),
                                        ),
                                      ),
                                      SizedBox(height: 4.w),
                                      RichText(
                                        text: TextSpan(
                                          style: GoogleFonts.poppins(
                                            fontSize: 12.0.sp,
                                            color: Color(0xFF4A5267),
                                            height: 1.5,
                                            fontWeight: FontWeight.w400,
                                          ),
                                          children: [
                                            TextSpan(
                                              text:
                                                  "Incase you installed kids app first go parents app and ",
                                            ),
                                            TextSpan(
                                              text: "Finish Sign Up",
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF0069F9),
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  " . The 6-character code will appear there.",
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 28.w),
                          Text(
                            'Child Code',
                            style: GoogleFonts.poppins(
                              fontSize: 14.0.sp,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16181A),
                            ),
                          ),
                          SizedBox(height: 8.w),
                          TextFormField(
                            controller: _childCodeController,
                            textCapitalization: TextCapitalization.characters,
                            onChanged: (value) {
                              setState(
                                () {},
                              ); // Rebuild to update segment dashes
                            },
                            style: GoogleFonts.poppins(
                              fontSize: 20.0.sp,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16181A),
                              letterSpacing: 4,
                            ),
                            decoration: InputDecoration(
                              hintText: 'e.g. KIDS01',
                              hintStyle: GoogleFonts.poppins(
                                color: Color(0xFF949DAA),
                                fontSize: 20.0.sp,
                                letterSpacing: 4,
                                fontWeight: FontWeight.w600,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 24.w,
                                vertical: 16.w,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16.w),
                                borderSide: BorderSide(
                                  color: Color(0xFF16181A),
                                  width: 1.5.w,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16.w),
                                borderSide: BorderSide(
                                  color: Color(0xFF16181A),
                                  width: 1.5.w,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16.w),
                                borderSide: BorderSide(
                                  color: Color(0xFF0069F9),
                                  width: 2.0.w,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16.w),
                                borderSide: BorderSide(
                                  color: Colors.red,
                                  width: 1.0.w,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16.w),
                                borderSide: BorderSide(
                                  color: Colors.red,
                                  width: 2.0.w,
                                ),
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
                          SizedBox(height: 12.w),
                          // 6 segment dashes below code box
                          Row(
                            children: List.generate(6, (index) {
                              final isEntered =
                                  _childCodeController.text.length > index;
                              return Expanded(
                                child: Container(
                                  height: 5.w,
                                  margin: EdgeInsets.only(
                                    left: index == 0.w ? 0.w : 6.w,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isEntered
                                        ? Color(0xFF5593F8)
                                        : Color(0xFFE2E7F3),
                                    borderRadius: BorderRadius.circular(3.w),
                                  ),
                                ),
                              );
                            }),
                          ),
                          SizedBox(height: 28.w),
                          // Yellow Note box
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 12.w,
                            ),
                            decoration: BoxDecoration(
                              color: Color(0xFFFFFBEF),
                              borderRadius: BorderRadius.circular(12.w),
                              border: Border.all(
                                color: Color(0xFFFFF1C4),
                                width: 1.0.w,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.poppins(
                                        fontSize: 12.0.sp,
                                        color: Color(0xFF8C7612),
                                        height: 1.4,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      children: [
                                        TextSpan(
                                          text:
                                              'Note: You can add multiple kids by adding in parent app',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Spacer(),
                          SizedBox(height: 32.w),
                          // Verify Code Button
                          SizedBox(
                            width: double.infinity,
                            height: 56.w,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF61A2F9),
                                disabledBackgroundColor: Color(0xFF61A2F9),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16.w),
                                ),
                                elevation: 0,
                              ),
                              onPressed: _isLoading ? null : _connectToParent,
                              child: _isLoading
                                  ? SizedBox(
                                      width: 24.w,
                                      height: 24.w,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      'Verify Code',
                                      style: GoogleFonts.poppins(
                                        fontSize: 20.0.sp,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          SizedBox(height: 16.w),
                          // Help footer link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Can't find the code? ",
                                style: GoogleFonts.poppins(
                                  fontSize: 14.0.sp,
                                  color: Color(0xFF4A5267),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              GestureDetector(
                                onTap: _showHelpDialog,
                                child: Text(
                                  "Help",
                                  style: GoogleFonts.poppins(
                                    fontSize: 14.0.sp,
                                    color: Color(0xFF0069F9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8.w),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
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
