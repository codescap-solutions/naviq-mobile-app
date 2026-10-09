import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/responsive_font.dart';

/// Colours used by the Figma file. Prefer these over inline `Color(0xFF…)`.
class FigmaColors {
  FigmaColors._();

  static const ink = Color(0xFF16181A); // headings, primary text
  static const body = Color(0xFF4A5267); // secondary text, labels
  static const hint = Color(0xFF6B7280); // input placeholder
  static const primary = Color(0xFF0069F9); // CTA, links, selection
  static const border = Color(0xFFDDE1EA); // hairlines, idle tile borders
  static const fieldBorder = Color(0xFF404040); // outlined text fields
}

/// Poppins type scale from Figma. Sizes and line heights are the Figma px
/// values; font size scales with the device (`.sp`) and line height is kept as
/// the Figma ratio, so text boxes stay proportional to the design.
class FigmaText {
  FigmaText._();

  static TextStyle poppins(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = FigmaColors.ink,
    double? lineHeight,
    double? letterSpacing,
  }) => GoogleFonts.poppins(
    fontSize: size.sp,
    fontWeight: weight,
    color: color,
    height: lineHeight == null ? null : lineHeight / size,
    letterSpacing: letterSpacing,
  );

  /// Screen title in the app bar (Figma Header): Regular 20 / 28, 0.2 spacing.
  static TextStyle get appBarTitle =>
      poppins(20, color: Color(0xFF0F1320), lineHeight: 28, letterSpacing: 0.2);

  /// "CHILD DETAILS" style overline above a page title.
  static TextStyle get eyebrow => poppins(
    12,
    color: FigmaColors.primary,
    lineHeight: 20,
    letterSpacing: 0.2,
  );

  static TextStyle get pageTitle =>
      poppins(24, weight: FontWeight.w700, lineHeight: 28);

  static TextStyle get caption => poppins(
    12,
    weight: FontWeight.w500,
    color: FigmaColors.body,
    lineHeight: 18,
  );

  /// Bold 12px caption that introduces a group ("Choose Avatar").
  static TextStyle get sectionLabel =>
      poppins(12, weight: FontWeight.w600, lineHeight: 18);

  /// 16px label above a field ("Age").
  static TextStyle get fieldLabel => poppins(
    16,
    weight: FontWeight.w500,
    color: FigmaColors.body,
    lineHeight: 22,
  );

  static TextStyle get input => poppins(16, lineHeight: 24);

  static TextStyle get inputHint => input.copyWith(color: FigmaColors.hint);

  static TextStyle get buttonLabel =>
      poppins(20, color: Colors.white, lineHeight: 28);
}
