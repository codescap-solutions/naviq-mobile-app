import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';

import '../models/subscription_plan.dart';
import 'subscription_popup_sheet.dart';

/// Shared "this feature/limit needs a higher plan" dialog. Every gated
/// screen (geofencing cap, screen-time actions, trip history window, help
/// channels, ...) should call [UpgradeRestrictionDialog.show] instead of
/// building a bespoke popup, so the restriction UX stays consistent.
///
/// Visual style mirrors the existing "Unlock Premium Protection" dialog in
/// settings_view.dart's `_showPremiumLogoutDialog`.
class UpgradeRestrictionDialog {
  /// Shows the standard "this support channel needs a higher plan" prompt.
  /// [channelName] is the disallowed channel's display name, e.g. "Chat"
  /// or "Call".
  static void showHelpChannelBlocked(BuildContext context, String channelName) {
    show(
      context,
      title: '$channelName Support Unavailable',
      message:
          '$channelName support isn\'t included in your current plan. '
          'Upgrade to unlock it.',
      suggestedTier: SubscriptionTier.smart,
    );
  }

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required SubscriptionTier suggestedTier,
    String ctaText = 'View Plans',
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _UpgradeRestrictionDialogContent(
        title: title,
        message: message,
        suggestedTier: suggestedTier,
        ctaText: ctaText,
      ),
    );
  }
}

class _UpgradeRestrictionDialogContent extends StatelessWidget {
  final String title;
  final String message;
  final SubscriptionTier suggestedTier;
  final String ctaText;

  const _UpgradeRestrictionDialogContent({
    required this.title,
    required this.message,
    required this.suggestedTier,
    required this.ctaText,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.w)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.w),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20.w,
              offset: Offset(0.w, 8.w),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF0066FF), Color(0xFF6F9EFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                color: Colors.white,
                size: 32.w,
              ),
            ),
            SizedBox(height: 18.w),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 20.0.sp,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0C1D37),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.w),
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.w),
            // Min height (not a fixed one) + explicit padding so the label is
            // never clipped when the system font size is larger.
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF0066FF),
                minimumSize: Size(double.infinity, 48.w),
                padding: EdgeInsets.symmetric(vertical: 14.w),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.w),
                ),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context);
                SubscriptionPopup.show(context, suggestedTier);
              },
              child: Text(
                ctaText,
                style: GoogleFonts.poppins(
                  fontSize: 14.5.sp,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 8.w),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: Size(double.infinity, 44.w),
                padding: EdgeInsets.symmetric(vertical: 12.w),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.w),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Not Now',
                style: GoogleFonts.poppins(
                  fontSize: 14.0.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
