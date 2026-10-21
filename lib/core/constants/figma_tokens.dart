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
  static const danger = Color(
    0xFFDD4E47,
  ); // Figma "Danger Main": destructive actions
  static const success = Color(0xFF57BC7B); // Figma "Success main"
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

  // Figma body scale (Poppins Regular, 0.2px letter spacing). Use these
  // instead of repeating the numbers; chain `.copyWith(color: ...)`.
  /// Body Large: 20 / 28.
  static TextStyle get bodyLarge =>
      poppins(20, lineHeight: 28, letterSpacing: 0.2);

  /// Body Medium: 16 / 24.
  static TextStyle get bodyMedium =>
      poppins(16, lineHeight: 24, letterSpacing: 0.2);

  /// Body Small: 12 / 20.
  static TextStyle get bodySmall =>
      poppins(12, lineHeight: 20, letterSpacing: 0.2);

  /// SemiBold 12, line height 100% (status pills, small buttons).
  static TextStyle get labelSmall =>
      poppins(12, weight: FontWeight.w600, lineHeight: 12, letterSpacing: 0.2);

  // ── Dialogs ──────────────────────────────────────────────────────────────
  // One set of text styles for every dialog, so titles, messages and buttons
  // read the same everywhere. Pass a colour with `.copyWith(color: ...)` only
  // when the dialog needs one (e.g. a destructive action).

  /// Dialog title: Figma "Header Text", Poppins SemiBold 20 / 28.
  static TextStyle get dialogTitle => poppins(
    20,
    weight: FontWeight.w600,
    lineHeight: 28,
    color: Color(0xFF0F1320),
  );

  /// Dialog message / sub-title: Body Small, 12 / 20.
  static TextStyle get dialogBody =>
      bodySmall.copyWith(color: FigmaColors.body);

  /// Dialog button label: Body Medium, 16 / 24.
  static TextStyle get dialogAction =>
      bodyMedium.copyWith(color: FigmaColors.ink, fontWeight: FontWeight.w500);

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
