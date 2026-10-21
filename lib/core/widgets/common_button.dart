import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_text_styles.dart';

class CommonButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final Color? backgroundColor;
  final Color? textColor;
  final double? width;
  final double? height;
  final EdgeInsets? padding;
  final double? borderRadius;
  final Widget? icon;
  final bool isEnabled;
  final double? fontSize;
  const CommonButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.backgroundColor,
    this.textColor,
    this.width,
    this.height,
    this.padding,
    this.borderRadius,
    this.icon,
    this.isEnabled = true,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isEnabled && !isLoading ? onPressed : null;
    final effectiveBackgroundColor = backgroundColor ?? AppColors.primaryColor;
    final effectiveTextColor = textColor ?? AppColors.surfaceColor;

    if (isOutlined) {
      return SizedBox(
        width: width,
        height: height ?? AppSizes.buttonHeightM,
        child: OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: effectiveTextColor,
            side: BorderSide(
              color: isEnabled
                  ? effectiveBackgroundColor
                  : AppColors.borderColor,
              width: 1.5,
            ),
            padding:
                padding ??
                const EdgeInsets.symmetric(horizontal: AppSizes.paddingL),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                borderRadius ?? AppSizes.radiusM,
              ),
            ),
          ),
          child: _buildButtonContent(),
        ),
      );
    }

    final double resolvedRadius = borderRadius ?? AppSizes.radiusM;

    // Gradient filled button when enabled and not outlined
    final bool useGradient =
        isEnabled && !isOutlined && backgroundColor == null;

    final Widget buttonChild = ElevatedButton(
      onPressed: effectiveOnPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: useGradient
            ? Colors.transparent
            : (isEnabled ? effectiveBackgroundColor : AppColors.borderColor),
        foregroundColor: effectiveTextColor,
        shadowColor: Colors.transparent,
        elevation: 0,
        padding:
            padding ??
            // No vertical padding, so a fixed `height` never clips the label.
            const EdgeInsets.symmetric(horizontal: AppSizes.paddingL),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(resolvedRadius),
        ),
      ),
      child: _buildButtonContent(),
    );

    if (!useGradient) {
      return SizedBox(
        width: width,
        height: height ?? AppSizes.buttonHeightM,
        child: buttonChild,
      );
    }

    return SizedBox(
      width: width,
      height: height ?? AppSizes.buttonHeightM,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(resolvedRadius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF004CE8), // #004CE8
              Color(0xFF6F9EFF), // #6F9EFF
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(resolvedRadius),
          child: buttonChild,
        ),
      ),
    );
  }

  Widget _buildButtonContent() {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator.adaptive(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            isOutlined ? AppColors.primaryColor : AppColors.surfaceColor,
          ),
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon!,
          const SizedBox(width: AppSizes.paddingS),
          Text(
            text,
            style: AppTextStyles.button.copyWith(
              color: isEnabled ? textColor : AppColors.textHint,
            ),
          ),
        ],
      );
    }

    return Text(
      text,
      style: AppTextStyles.button.copyWith(
        fontSize: fontSize ?? 14,
        color: isEnabled ? textColor : AppColors.textHint,
      ),
    );
  }
}
