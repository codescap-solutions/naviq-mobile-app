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
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              emoji,
              style: GoogleFonts.poppins(
                fontSize: 22,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20.0.sp,
              fontWeight: FontWeight.w400,
              height: 28 / 20,
              letterSpacing: 0.2,
              color: const Color(0xFF16181A),
            ),
          ),
        ],
      ),
    );
  }
}
