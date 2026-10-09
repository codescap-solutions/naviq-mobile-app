import 'package:flutter/material.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
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
        width: 52.w,
        height: 52.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2.w,
              offset: Offset(0.w, 4.w),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Header used by every Figma screen: white band running up under the status
/// bar, 52px back circle (24px arrow), centred Poppins Regular 20 / 28 title
/// (letter spacing 0.2, #0F1320) and an optional 52px trailing circle holding
/// a 24px icon. The title style is deliberately not configurable so all
/// screens stay identical.
PreferredSizeWidget figmaAppBar(
  BuildContext context, {
  required String title,
  Widget? trailing,
  VoidCallback? onBack,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    toolbarHeight: 68.w,
    leadingWidth: 70.w,
    leading: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 18.w),
        child: FigmaCircleButton(
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          child: Image.asset(
            'assets/icons/auth_back.png',
            width: 24.w,
            height: 24.w,
          ),
        ),
      ),
    ),
    title: Text(title, style: FigmaText.appBarTitle),
    actions: [
      if (trailing != null)
        Padding(
          padding: EdgeInsets.only(right: 18.w),
          child: trailing,
        ),
    ],
  );
}
