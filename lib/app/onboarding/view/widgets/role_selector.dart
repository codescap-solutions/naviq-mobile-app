import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';

/// An animated capsule-shaped selector for choosing between Kid and Parent roles.
class RoleSelector extends StatelessWidget {
  final String selected; // 'Kid' or 'Parent'
  final ValueChanged<String> onChanged;

  const RoleSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isKidSelected = selected == 'Kid';

    return Container(
      width: 310,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SizedBox(
        height: 47,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabWidth = constraints.maxWidth / 2;
            return Stack(
              children: [
                // Sliding Selection Indicator
                AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: isKidSelected
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    width: tabWidth,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0069F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                // Option labels in a Row
                Row(
                  children: [
                    Expanded(child: _label('Kid', isKidSelected)),
                    Expanded(child: _label('Parent', !isKidSelected)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _label(String role, bool isSelected) {
    return GestureDetector(
      onTap: () => onChanged(role),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Text(
          role,
          style: GoogleFonts.poppins(
            fontSize: 16.0.sp,
            fontWeight: FontWeight.w400,
            height: 24 / 16,
            letterSpacing: 0.2,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
