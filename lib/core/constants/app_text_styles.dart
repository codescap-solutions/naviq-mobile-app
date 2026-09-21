import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import '../utils/responsive_font.dart';

class AppTextStyles {
  // Oswald Font Styles for Headings
  static TextStyle get headlineXL => GoogleFonts.oswald(
    fontSize: 44.0.sp,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static TextStyle get headline1 => GoogleFonts.oswald(
    fontSize: 32.0.sp,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static TextStyle get headline2 => GoogleFonts.oswald(
    fontSize: 28.0.sp,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static TextStyle get headline3 => GoogleFonts.poppins(
    fontSize: 24.0.sp,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get headline4 => GoogleFonts.poppins(
    fontSize: 20.0.sp,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get headline5 => GoogleFonts.oswald(
    fontSize: 18.0.sp,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get headline6 => GoogleFonts.oswald(
    fontSize: 16.0.sp,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Manrope Font Styles for Body, Buttons, and Captions
  static TextStyle get subtitle1 => GoogleFonts.poppins(
    fontSize: 16.0.sp,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get subtitle2 => GoogleFonts.poppins(
    fontSize: 14.0.sp,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Body Styles
  static TextStyle get body1 => GoogleFonts.poppins(
    fontSize: 16.0.sp,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );

  static TextStyle get body2 => GoogleFonts.poppins(
    fontSize: 14.0.sp,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );

  // Caption Styles
  static TextStyle get caption => GoogleFonts.poppins(
    fontSize: 12.0.sp,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );

  static TextStyle get textSecondary => GoogleFonts.poppins(
    fontSize: 14.0.sp,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );

  // Button Styles
  static TextStyle get button => GoogleFonts.poppins(
    fontSize: 14.0.sp,
    fontWeight: FontWeight.w600,
    color: AppColors.surfaceColor,
  );

  // Overline Styles
  static TextStyle get overline => GoogleFonts.poppins(
    fontSize: 10.0.sp,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 1.5,
  );
}
