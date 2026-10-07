import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'toggle_switch.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class GeoPlaceCard extends StatelessWidget {
  final String title;
  final int radius;
  final bool toggleValue;
  final String? category;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;

  const GeoPlaceCard({
    super.key,
    required this.title,
    required this.radius,
    required this.toggleValue,
    this.category,
    this.onTap,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    Color iconBgColor;
    IconData iconData;

    final cat = (category ?? title).toLowerCase();
    if (cat.contains('home')) {
      iconBgColor = const Color(0xFF0C80E0); // Solid blue
      iconData = Icons.home_rounded;
    } else if (cat.contains('school')) {
      iconBgColor = const Color(0xFF10B981); // Solid green
      iconData = Icons.school_rounded;
    } else if (cat.contains('cricket') ||
        cat.contains('ground') ||
        cat.contains('play') ||
        cat.contains('sport')) {
      iconBgColor = const Color(0xFF6366F1); // Solid indigo/purple
      iconData = Icons.sports_cricket_rounded;
    } else {
      iconBgColor = const Color(0xFFF59E0B); // Solid amber
      iconData = Icons.location_on_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C1D37).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular container for icons
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Center(child: Icon(iconData, color: Colors.white, size: 24)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16.0.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0C1D37),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      "${radius}m radius • ",
                      style: GoogleFonts.poppins(
                        fontSize: 13.0.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    if (toggleValue) ...[
                      Text(
                        "Active",
                        style: GoogleFonts.poppins(
                          fontSize: 13.0.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    GestureDetector(
                      onTap: onTap,
                      child: Text(
                        "Edit",
                        style: GoogleFonts.poppins(
                          fontSize: 13.0.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0066FF),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          CustomToggleSwitch(
            value: toggleValue,
            onChanged: onToggle ?? (value) {},
          ),
        ],
      ),
    );
  }
}
