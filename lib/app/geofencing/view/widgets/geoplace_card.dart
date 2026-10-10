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
    final cat = '${category ?? ''} $title'.toLowerCase();
    final IconData iconData;
    if (cat.contains('home')) {
      iconData = Icons.home_outlined;
    } else if (cat.contains('school')) {
      iconData = Icons.menu_book_outlined;
    } else if (cat.contains('cricket') ||
        cat.contains('ground') ||
        cat.contains('play') ||
        cat.contains('sport')) {
      iconData = Icons.sports_basketball_outlined;
    } else {
      iconData = Icons.location_on_outlined;
    }

    // Figma "CARD": 94 high, 46 icon tile at (16,24), text 12px right of it,
    // 48x28 toggle at the right edge, 8px between cards.
    return Container(
      height: 94.w,
      margin: EdgeInsets.only(bottom: 8.w),
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.w),
      ),
      child: Row(
        children: [
          Container(
            height: 46.w,
            width: 46.w,
            decoration: BoxDecoration(
              color: Color(0xFFF7F8FA),
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, color: Color(0xFF0F1320), size: 22.w),
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
                    weight: FontWeight.w600,
                    color: Color(0xFF0F1320),
                    lineHeight: 24,
                  ),
                ),
                SizedBox(height: 2.w),
                Row(
                  children: [
                    Text(
                      "$radius m radius  ·  ",
                      style: _detail(Color(0xFF4B5567), FontWeight.w400),
                    ),
                    if (toggleValue) ...[
                      Text(
                        "Active",
                        style: _detail(Color(0xFF34B27B), FontWeight.w600),
                      ),
                      SizedBox(width: 12.w),
                    ],
                    GestureDetector(
                      onTap: onTap,
                      child: Text(
                        "Edit",
                        style: _detail(Color(0xFF2C67F0), FontWeight.w600),
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
            activeColor: Color(0xFF2C67F0),
            width: 48,
            height: 28,
            knob: 22,
          ),
        ],
      ),
    );
  }

  TextStyle _detail(Color color, FontWeight weight) =>
      FigmaText.poppins(12, weight: weight, color: color, lineHeight: 16);
}
