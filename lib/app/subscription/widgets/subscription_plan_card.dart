import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import '../models/subscription_plan.dart';

/// One plan card of the Subscription screen (Figma): a tinted left panel with
/// label / icon / name / price, and a right panel with the plan's feature
/// bullets and CTA. Everything shown comes from the backend plan; only the
/// per-tier colours, the tier icon, the "Recommended" chip and the CTA copy
/// are local.
class SubscriptionPlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isYearly;
  final VoidCallback onTap;

  /// The plan the user is on right now: gets a blue outline and a green
  /// "Current Plan" button (no "Recommended" chip).
  final bool isCurrent;

  /// Days left in the current plan; shown in place of the price on the
  /// current plan's card when set.
  final int? daysLeft;

  /// false: no "Recommended" chip, blue outline or "Most Popular" label on the
  /// Smart card (the user is already on a higher plan).
  final bool showRecommendation;

  /// The card previews this many features; "View all features" (the detail
  /// screen) lists the rest. Same count on every card (Figma).
  static const previewFeatureCount = 6;

  const SubscriptionPlanCard({
    super.key,
    required this.plan,
    required this.isYearly,
    required this.onTap,
    this.isCurrent = false,
    this.daysLeft,
    this.showRecommendation = true,
  });

  static const _blue = Color(0xFF0069F9);
  static const _green = Color(0xFF43A047);
  static const _orange = Color(0xFFF5A623);
  static const _navy = Color(0xFF0F1320);
  static const _slate = Color(0xFF4A5267);

  _TierStyle get _style {
    switch (plan.tier) {
      case SubscriptionTier.smart:
        return const _TierStyle(
          accent: _blue,
          panel: [Color(0xFFDDE9FF), Color(0xFFC2D9FF)],
          rightBg: Color(0xFFF7F8FA),
          circleFill: Color(0xFFB9D4FE),
          icon: 'assets/icons/subscription_shield.svg',
          iconColor: _blue,
          checkRing: Color(0xFF2A81F9),
          checkFill: Color(0xFFE8F1FF),
          cta: _blue,
          chipBg: Color(0xFFB4D1FD),
          chipText: _blue,
        );
      case SubscriptionTier.premium:
        return const _TierStyle(
          accent: _orange,
          panel: [Color(0xFFFFF7E3), Color(0xFFFFEBB0)],
          rightBg: Colors.white,
          circleFill: Color(0xFFFEEAC4),
          icon: 'assets/icons/subscription_crown.svg',
          iconColor: _orange,
          checkRing: Color(0xFFF6B548),
          checkFill: Color(0xFFFFF3DB),
          cta: _orange,
          chipBg: Color(0xFFFEE8B9),
          chipText: _orange,
        );
      case SubscriptionTier.basic:
        return const _TierStyle(
          accent: _blue,
          panel: [Color(0xFFF5F7FB), Color(0xFFE8E9EC)],
          rightBg: Colors.white,
          circleFill: Color(0xFFDFE1E7),
          icon: 'assets/icons/subscription_shield.svg',
          iconColor: _slate,
          checkRing: Color(0xFFACB3C1),
          checkFill: Color(0xFFF3F4F6),
          cta: _navy,
          chipBg: Color(0xFFDCE0E7),
          chipText: _blue,
        );
      case SubscriptionTier.starter:
        return const _TierStyle(
          accent: _slate,
          panel: null,
          rightBg: Colors.white,
          circleFill: Color(0xFFE9EAED),
          icon: 'assets/icons/subscription_send.svg',
          iconColor: _slate,
          checkRing: Color(0xFFACB3C1),
          checkFill: Color(0xFFF3F4F6),
          cta: _navy,
          chipBg: Color(0xFFDCE0E7),
          chipText: _slate,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final isSmart = plan.tier == SubscriptionTier.smart && showRecommendation;
    final radius = BorderRadius.circular(14.w);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: s.rightBg,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: _navy.withValues(alpha: 0.06),
                  blurRadius: 16.w,
                  offset: Offset(0.w, 4.w),
                ),
              ],
            ),
            // The 1.5px Smart border is painted on top so it does not change
            // the card's size (Figma strokes sit inside the frame).
            foregroundDecoration: isCurrent || isSmart
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: _blue, width: 1.5),
                  )
                : null,
            child: ClipRRect(
              borderRadius: radius,
              // Figma: 232 high, 127 wide left panel. Grows if a long feature
              // name wraps instead of overflowing.
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: 232.w),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 127.w, child: _leftPanel(s)),
                      Expanded(child: _rightPanel(s)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isSmart && !isCurrent)
            Positioned(
              top: -13.w,
              right: 18.w,
              child: Container(
                height: 26.w,
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(14.w),
                ),
                child: Text(
                  'Recommended',
                  // Figma: Poppins SemiBold 12, line height 100%, 0.2 spacing.
                  style: FigmaText.labelSmall.copyWith(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Left panel ────────────────────────────────────────────────────────────
  Widget _leftPanel(_TierStyle s) {
    final hideBadge =
        plan.tier == SubscriptionTier.smart && !showRecommendation;
    final label = hideBadge
        ? null
        : plan.badge ?? (plan.tier == SubscriptionTier.starter ? 'Free' : null);
    final isFree = plan.isFree;

    final top = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 15.w,
          child: label == null
              ? null
              : Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10.0.sp,
                    fontWeight: FontWeight.w600,
                    height: 15 / 10,
                    color: plan.tier == SubscriptionTier.starter
                        ? _slate
                        : (plan.tier == SubscriptionTier.premium
                              ? _orange
                              : _blue),
                  ),
                ),
        ),
        SizedBox(height: 8.w),
        Container(
          width: 42.w,
          height: 42.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.circleFill,
            shape: BoxShape.circle,
          ),
          child: SvgPicture.asset(
            s.icon,
            width: 24.w,
            height: 24.w,
            colorFilter: ColorFilter.mode(s.iconColor, BlendMode.srcIn),
          ),
        ),
        SizedBox(height: 7.w),
        Text(
          isFree ? 'FREE' : plan.name.toUpperCase(),
          maxLines: 1,
          style: GoogleFonts.poppins(
            // Figma sets ULTIMATE smaller (66px wide) than SMART/BASIC (~60px).
            fontSize: (plan.tier == SubscriptionTier.premium ? 14.0 : 17.0).sp,
            fontWeight: FontWeight.w700,
            height: 27 / 17,
            color: s.accent,
          ),
        ),
      ],
    );

    final price = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '₹',
              style: GoogleFonts.poppins(
                fontSize: 16.0.sp,
                fontWeight: FontWeight.w600,
                color: isFree ? _slate : _navy,
              ),
            ),
            SizedBox(width: 4.w),
            Text(
              isFree ? '0' : '${plan.monthlyPrice.toInt()}',
              style: GoogleFonts.poppins(
                fontSize: 28.0.sp,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: isFree ? _slate : _navy,
              ),
            ),
          ],
        ),
        Text(
          isFree ? 'forever free' : '/month',
          style: FigmaText.bodySmall.copyWith(color: _slate),
        ),
        // Figma (Yearly selected): the yearly price sits in a small chip under
        // the monthly price.
        if (!isFree && isYearly && plan.yearlyPrice != null) ...[
          Container(
            height: 24.w,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: s.chipBg,
              borderRadius: BorderRadius.circular(12.w),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                '₹${plan.yearlyPrice!.toInt()}/yr',
                style: FigmaText.bodySmall.copyWith(color: _slate, height: 1.0),
              ),
            ),
          ),
        ],
      ],
    );

    final days = isCurrent ? daysLeft : null;
    final daysLeftBox = days == null
        ? null
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        days == 1 ? '1 DAY LEFT' : '$days DAYS LEFT',
                        maxLines: 1,
                        style: GoogleFonts.poppins(
                          fontSize: 13.0.sp,
                          fontWeight: FontWeight.w700,
                          height: 18 / 13,
                          color: _green,
                        ),
                      ),
                    ),
                    Text(
                      'in your plan',
                      style: FigmaText.bodySmall.copyWith(
                        color: _slate,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    return Container(
      decoration: s.panel == null
          ? null
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: s.panel!,
              ),
            ),
      padding: EdgeInsets.fromLTRB(12.w, 22.w, 8.w, 14.w),
      child: isFree
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                top,
                SizedBox(height: 4.w),
                price,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [top, daysLeftBox ?? price],
            ),
    );
  }

  List<SubscriptionFeature> get _preview =>
      plan.features.take(previewFeatureCount).toList();

  // ── Right panel ───────────────────────────────────────────────────────────
  Widget _rightPanel(_TierStyle s) {
    return Container(
      color: s.rightBg,
      padding: EdgeInsets.fromLTRB(12.w, 21.w, 12.w, 12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _preview.length; i++) ...[
            if (i > 0) SizedBox(height: 6.w),
            Row(
              children: [
                Container(
                  width: 16.w,
                  height: 16.w,
                  decoration: BoxDecoration(
                    color: s.checkFill,
                    shape: BoxShape.circle,
                    border: Border.all(color: s.checkRing, width: 1),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 10.w,
                    color: s.checkRing,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    _preview[i].name,
                    // Pricing-sheet wording is long ("3 Parents / Guardians
                    // Access Logins"): wrap instead of cutting it off.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // Figma Body Small: 12 / 20.
                    style: FigmaText.bodySmall.copyWith(color: _slate),
                  ),
                ),
              ],
            ),
          ],
          if (plan.tagline != null) ...[
            SizedBox(height: 31.w),
            Text(
              plan.tagline!,
              style: GoogleFonts.poppins(
                fontSize: 11.0.sp,
                fontWeight: FontWeight.w600,
                height: 15 / 11,
                color: _orange,
              ),
            ),
          ] else ...[
            // Button sits on the bottom edge (12 up from it), Figma 198 x 36.
            SizedBox(height: 12.w),
            const Spacer(),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 198.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: isCurrent ? _green : s.cta,
                  borderRadius: BorderRadius.circular(18.w),
                ),
                child: isCurrent
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 20.w,
                            height: 20.w,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 14.w,
                              color: _green,
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            'CURRENT PLAN',
                            style: FigmaText.bodySmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              height: 1.0,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'View all Features',
                            style: FigmaText.bodySmall.copyWith(
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          SizedBox(width: 6.w),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16.w,
                            color: Colors.white,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TierStyle {
  final Color accent;
  final List<Color>? panel;
  final Color rightBg;
  final Color circleFill;
  final String icon;
  final Color iconColor;
  final Color checkRing;
  final Color checkFill;
  final Color cta;
  final Color chipBg;
  final Color chipText;
  const _TierStyle({
    required this.accent,
    required this.panel,
    required this.rightBg,
    required this.circleFill,
    required this.icon,
    required this.iconColor,
    required this.checkRing,
    required this.checkFill,
    required this.cta,
    required this.chipBg,
    required this.chipText,
  });
}
