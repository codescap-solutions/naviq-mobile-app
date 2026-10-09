import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';

/// Visual body of a "type of place" preset card (Figma New Fencing sheet):
/// white card, 1px #EEF0F4 border, radius 14, 44px solid emoji badge and a
/// Poppins Regular 20/28 label.
class PresetPlaceCardBody extends StatelessWidget {
  final String label;
  final String emoji;
  final Color color;
  const PresetPlaceCardBody({
    super.key,
    required this.label,
    required this.emoji,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: 96.w),
      padding: EdgeInsets.symmetric(
        horizontal: 7.w,
        vertical: 7.w,
      ), // border is inside the 196x100 Figma box
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.w),
        border: Border.all(color: Color(0xFFEEF0F4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44.w,
            height: 44.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              emoji,
              style: GoogleFonts.poppins(
                fontSize: 22.0.sp,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(height: 12.w),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20.0.sp,
              fontWeight: FontWeight.w400,
              height: 28 / 20,
              letterSpacing: 0.2,
              color: Color(0xFF16181A),
            ),
          ),
        ],
      ),
    );
  }
}
