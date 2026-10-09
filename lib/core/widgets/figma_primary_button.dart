import 'package:flutter/material.dart';
import '../constants/figma_tokens.dart';
import '../utils/responsive_font.dart';

/// Solid blue CTA from Figma: 60px high, 16px radius, 20px label by default
/// (the Sign Up frame uses 56 / 14). Dims itself when [onPressed] is null or
/// while [isLoading] (which also shows a spinner and ignores taps).
class FigmaPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final double radius;

  const FigmaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.height = 60,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius.w);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: borderRadius,
        child: Container(
          height: height.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FigmaColors.primary.withValues(
              alpha: isLoading || onPressed == null ? 0.5 : 1,
            ),
            borderRadius: borderRadius,
          ),
          child: isLoading
              ? SizedBox(
                  width: 24.w,
                  height: 24.w,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(label, style: FigmaText.buttonLabel),
        ),
      ),
    );
  }
}
