import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class ChildCodeScreen extends StatelessWidget {
  final String childCode;
  final String childId;
  final bool isFirstChild;

  const ChildCodeScreen({
    super.key,
    required this.childId,
    required this.childCode,
    this.isFirstChild = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.paddingL.w,
            vertical: AppSizes.paddingM.w,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isFirstChild) ...[
                SizedBox(height: 24.w),
                Text(
                  'Add your first child by\npasting this code',
                  style: GoogleFonts.poppins(
                    fontSize: 24.0.sp,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0C1D37),
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.w),
                _buildCodeContainer(context),
                SizedBox(height: 16.w),
                Text(
                  'Enter this code on your child\'s device to link their account and start monitoring their activity.',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    color: Color(0xFF62748E),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.w),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.w),
                    border: Border.all(color: Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF0066FF).withValues(alpha: 0.02),
                        blurRadius: 8.w,
                        offset: Offset(0, 2.w),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildChecklistItem(
                        icon: Icons.lock_outline_rounded,
                        title: 'Security',
                        subtitle: 'Your account is protected',
                      ),
                      Divider(height: 1, color: Color(0xFFE2E8F0)),
                      _buildChecklistItem(
                        icon: Icons.visibility_outlined,
                        title: 'Privacy',
                        subtitle: 'Your information is private',
                      ),
                      Divider(height: 1, color: Color(0xFFE2E8F0)),
                      _buildChecklistItem(
                        icon: Icons.shield_outlined,
                        title: 'Permissions',
                        subtitle: 'App access is set',
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20.w),
                Text(
                  "🎉 You're ready to use the app securely!",
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0C1D37),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.w),
                CommonButton(
                  text: 'Go Home',
                  icon: Icon(
                    Icons.home_outlined,
                    color: Colors.white,
                    size: 20.w,
                  ),
                  height: 54.w,
                  borderRadius: 16,
                  onPressed: () => _navigateToHome(context),
                ),
                SizedBox(height: 12.w),
                SizedBox(
                  height: 54.w,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Color(0xFF0C1D37), width: 1.5.w),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.w),
                      ),
                      backgroundColor: Colors.transparent,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Tutorial coming soon!"),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.play_arrow_outlined,
                      color: Color(0xFF0C1D37),
                      size: 20.w,
                    ),
                    label: Text(
                      "Watch Tutorial",
                      style: GoogleFonts.poppins(
                        fontSize: 15.0.sp,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0C1D37),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(height: 48.w),
                Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 80.w,
                  ),
                ),
                SizedBox(height: 24.w),
                Text(
                  'Child Created Successfully!',
                  style: GoogleFonts.poppins(
                    fontSize: 24.0.sp,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0C1D37),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32.w),
                Text(
                  'Your Child Code:',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    color: Color(0xFF62748E),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12.w),
                _buildCodeContainer(context),
                SizedBox(height: 16.w),
                Text(
                  'Enter this code on your child\'s device to link their account and start monitoring their activity.',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    color: Color(0xFF62748E),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 48.w),
                CommonButton(
                  text: 'Continue to Home',
                  height: 54.w,
                  borderRadius: 16,
                  onPressed: () => _navigateToHome(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeContainer(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.w),
        border: Border.all(color: Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0066FF).withValues(alpha: 0.03),
            blurRadius: 12.w,
            offset: Offset(0, 4.w),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            childCode.split('').join(' '),
            style: GoogleFonts.poppins(
              fontSize: 26.0.sp,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0066FF),
              letterSpacing: 2,
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: childCode));
              AppSnackbar.showInfo(context, 'Child code copied to clipboard!');
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.w),
              decoration: BoxDecoration(
                color: Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8.w),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.copy_rounded,
                    color: Color(0xFF0066FF),
                    size: 16.w,
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    'Copy',
                    style: GoogleFonts.poppins(
                      fontSize: 14.0.sp,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0066FF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.w),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Color(0xFF0066FF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0C1D37),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 12.0.sp,
                    color: const Color(0xFF62748E),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
        ],
      ),
    );
  }

  Future<void> _navigateToHome(BuildContext context) async {
    // Await this — the next screen (and a possible quick splash/auth check)
    // reads child_id right away, and a fire-and-forget write here could race
    // with that read.
    await injector<SharedPrefsService>().setString('child_id', childId);
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(RouteNames.home, (route) => false);
  }
}
