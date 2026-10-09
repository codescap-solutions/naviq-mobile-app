import 'package:flutter/material.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/widgets/figma_toggle.dart';
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

    // Figma "CARD": 400x94, 46px icon at (16,24), text column 12px right of it,
    // 48x28 toggle at the right edge, 8px between cards.
    return Container(
      height: 94.w,
      margin: EdgeInsets.only(bottom: 8.w),
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.w),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0C1D37).withValues(alpha: 0.03),
            blurRadius: 12.w,
            offset: Offset(0, 4.w),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 46.w,
            width: 46.w,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(iconData, color: Colors.white, size: 24.w),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FigmaText.poppins(
                    16,
                    weight: FontWeight.w800,
                    color: Color(0xFF0C1D37),
                    lineHeight: 24,
                  ),
                ),
                SizedBox(height: 2.w),
                Row(
                  children: [
                    Text(
                      "${radius}m radius • ",
                      style: _detail(Color(0xFF64748B), FontWeight.w500),
                    ),
                    if (toggleValue) ...[
                      Text(
                        "Active",
                        style: _detail(Color(0xFF22C55E), FontWeight.w700),
                      ),
                      SizedBox(width: 12.w),
                    ],
                    GestureDetector(
                      onTap: onTap,
                      child: Text(
                        "Edit",
                        style: _detail(FigmaColors.primary, FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          FigmaToggle(
            value: toggleValue,
            onChanged: onToggle ?? (value) {},
            activeColor: Color(0xFF22C55E),
            width: 48,
            height: 28,
            knob: 22,
          ),
        ],
      ),
    );
  }

  TextStyle _detail(Color color, FontWeight weight) =>
      FigmaText.poppins(13, weight: weight, color: color, lineHeight: 18);
}
