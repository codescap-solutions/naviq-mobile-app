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
  static void showHelpChannelBlocked(
    BuildContext context,
    String channelName,
  ) {
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF0066FF), Color(0xFF6F9EFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 20.0.sp,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0C1D37),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Not Now',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
