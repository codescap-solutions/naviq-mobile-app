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
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / 2;
          return Stack(
            children: [
              // Sliding Selection Indicator
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: isKidSelected ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: tabWidth - 4, // subtle inner padding
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066FF),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0066FF).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              // Option labels in a Row
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged('Kid'),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '👦',
                              style: TextStyle(fontSize: 16.0.sp),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Kid',
                              style: GoogleFonts.poppins(
                                fontSize: 15.0.sp,
                                fontWeight: FontWeight.w700,
                                color: isKidSelected
                                    ? Colors.white
                                    : const Color(0xFF5F6368),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged('Parent'),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '👪',
                              style: TextStyle(fontSize: 16.0.sp),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Parent',
                              style: GoogleFonts.poppins(
                                fontSize: 15.0.sp,
                                fontWeight: FontWeight.w700,
                                color: !isKidSelected
                                    ? Colors.white
                                    : const Color(0xFF5F6368),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
