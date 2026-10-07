import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_text_styles.dart';

class CommonTextField extends StatefulWidget {
  final String? hintText;
  final String? labelText;
  final String? initialValue;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool readOnly;
  final bool enabled;
  final int? maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final void Function()? onTap;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final EdgeInsets? contentPadding;
  final double? borderRadius;
  final Color? fillColor;
  final Color? borderColor;
  final double? borderWidth;
  final TextStyle? hintStyle;
  final Color? focusedBorderColor;
  final Color? errorBorderColor;
  final String? errorText;
  final bool autofocus;

  const CommonTextField({
    super.key,
    this.hintText,
    this.labelText,
    this.initialValue,
    this.controller,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.prefixIcon,
    this.suffixIcon,
    this.inputFormatters,
    this.focusNode,
    this.contentPadding,
    this.borderRadius,
    this.fillColor,
    this.borderColor,
    this.borderWidth,
    this.hintStyle,
    this.focusedBorderColor,
    this.errorBorderColor,
    this.errorText,
    this.autofocus = false,
  });

  @override
  State<CommonTextField> createState() => _CommonTextFieldState();
}

class _CommonTextFieldState extends State<CommonTextField> {
  late TextEditingController _controller;
  bool _obscureText = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
    _obscureText = widget.obscureText;
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: _obscureText,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      inputFormatters: widget.inputFormatters,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      style: AppTextStyles.body1,
      decoration: InputDecoration(
        hintText: widget.hintText,
        labelText: widget.labelText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: _buildSuffixIcon(),
        filled: true,
        fillColor: widget.fillColor ?? AppColors.surfaceColor,
        contentPadding:
            widget.contentPadding ??
            const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingM,
              vertical: AppSizes.paddingM,
            ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            widget.borderRadius ?? AppSizes.radiusM,
          ),
          borderSide: BorderSide(
            color: widget.borderColor ?? AppColors.borderColor,
            width: widget.borderWidth ?? 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            widget.borderRadius ?? AppSizes.radiusM,
          ),
          borderSide: BorderSide(
            color: widget.borderColor ?? AppColors.borderColor,
            width: widget.borderWidth ?? 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            widget.borderRadius ?? AppSizes.radiusM,
          ),
          borderSide: BorderSide(
            color: widget.focusedBorderColor ?? AppColors.primaryColor,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            widget.borderRadius ?? AppSizes.radiusM,
          ),
          borderSide: BorderSide(
            color: widget.errorBorderColor ?? AppColors.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            widget.borderRadius ?? AppSizes.radiusM,
          ),
          borderSide: BorderSide(
            color: widget.errorBorderColor ?? AppColors.error,
            width: 2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            widget.borderRadius ?? AppSizes.radiusM,
          ),
          borderSide: BorderSide(
            color: AppColors.borderColor.withValues(alpha: 0.5),
          ),
        ),
        hintStyle:
            widget.hintStyle ??
            AppTextStyles.body2.copyWith(color: AppColors.textHint),
        labelStyle: AppTextStyles.body2.copyWith(
          color: AppColors.textSecondary,
        ),
        errorText: widget.errorText,
        counterText: widget.maxLength != null ? null : '',
      ),
    );
  }

  Widget? _buildSuffixIcon() {
    if (widget.obscureText) {
      return IconButton(
        icon: Icon(
          _obscureText ? Icons.visibility_off : Icons.visibility,
          color: AppColors.textSecondary,
        ),
        onPressed: () {
          setState(() {
            _obscureText = !_obscureText;
          });
        },
      );
    }

    return widget.suffixIcon;
  }
}
