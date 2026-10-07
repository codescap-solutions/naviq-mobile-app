import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class FeatureCard extends StatelessWidget {
  final String title;
  final String description;
  final String iconAsset;
  final Color borderColor;
  final Color titleColor;
  final Color descriptionColor;
  final double shadowBlur;
  final VoidCallback? onTap;

  const FeatureCard({
    super.key,
    required this.title,
    required this.description,
    required this.iconAsset,
    required this.borderColor,
    this.titleColor = const Color(0xFF16181A),
    this.descriptionColor = const Color(0xFF707784),
    this.shadowBlur = 5,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: shadowBlur,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFEBF3FF),
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(iconAsset, width: 20, height: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 16.0.sp,
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: GoogleFonts.poppins(
                fontSize: 12.0.sp,
                fontWeight: FontWeight.w400,
                color: descriptionColor,
                height: 20 / 12,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
