import 'package:flutter/material.dart';

/// Pill toggle from the Figma settings screens: coloured track, white knob
/// with a soft shadow. Settings uses 48x26 / knob 20 in blue; Notification
/// settings uses 50x28 / knob 22 in green.
class FigmaToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;
  final Color inactiveColor;
  final double width;
  final double height;
  final double knob;

  const FigmaToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor = const Color(0xFF0069F9),
    this.inactiveColor = const Color(0xFFDDE1EA),
    this.width = 48,
    this.height = 26,
    this.knob = 20,
  });

  @override
  Widget build(BuildContext context) {
    final double pad = (height - knob) / 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: value ? activeColor : inactiveColor,
          borderRadius: BorderRadius.circular(height),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: knob,
            height: knob,
            margin: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
