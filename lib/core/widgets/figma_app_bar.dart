import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';

/// 52px white circle with the Figma drop shadow, used for the header's back
/// and trailing buttons.
class FigmaCircleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  const FigmaCircleButton({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Header shared by the Figma settings-style screens: white band running up
/// under the status bar, 52px back circle, centred Poppins Bold title and an
/// optional 52px trailing circle.
PreferredSizeWidget figmaAppBar(
  BuildContext context, {
  required String title,
  double titleSize = 20,
  Color titleColor = Colors.black,
  Color background = Colors.white,
  Widget? trailing,
  VoidCallback? onBack,
  Color circleColor = Colors.white,
  Widget? backIcon,
}) {
  return AppBar(
    backgroundColor: background,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    toolbarHeight: 68,
    leadingWidth: 70,
    leading: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 18),
        child: FigmaCircleButton(
          color: circleColor,
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          child:
              backIcon ??
              Image.asset('assets/icons/auth_back.png', width: 24, height: 24),
        ),
      ),
    ),
    title: Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: titleSize.sp,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: titleColor,
      ),
    ),
    actions: [
      if (trailing != null)
        Padding(padding: const EdgeInsets.only(right: 18), child: trailing),
    ],
  );
}
