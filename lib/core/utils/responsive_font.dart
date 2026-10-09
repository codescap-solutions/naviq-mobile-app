import 'package:flutter/widgets.dart';

/// Scales a font size by the device's screen width relative to the Figma
/// design reference (iPhone 16/17 Pro Max frame, 428pt wide) — the same
/// technique apps commonly reach for via packages like flutter_screenutil,
/// implemented directly here to avoid pulling in a new dependency for one
/// formula.
///
/// A size that looks right on the 428pt frame the designs were built at
/// would otherwise render at that same absolute size on a 375pt iPhone SE —
/// proportionally larger there than intended, and prone to wrapping/
/// overflowing next to fixed-size icons in a header row. Scaling by width
/// keeps the same *relative* size across devices instead.
///
/// Clamped to 0.85–1.15 so text never shrinks to the point of illegibility
/// on a small phone, nor balloons unreasonably on a tablet-sized screen.
///
/// Reads the screen size from [WidgetsBinding.platformDispatcher] instead of
/// taking a `BuildContext` — this lets it be used from anywhere a font size
/// is defined (widget build methods, but also static style constants and
/// canvas/TextPainter code that has no context to hand), not just inside a
/// widget's own build method.
extension ResponsiveFont on double {
  static const double _designWidth = 428.0;
  static const double _minScale = 0.85;
  static const double _maxScale = 1.15;

  static double get _screenWidth {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return _designWidth; // scale 1.0 fallback
    final view = views.first;
    return view.physicalSize.width / view.devicePixelRatio;
  }

  /// Screen-width factor vs the 428pt Figma frame, clamped 0.85–1.15. Shared by
  /// fonts (`.sp`) and layout sizes (`.w`) so text and boxes always scale together.
  static double get scale =>
      (_screenWidth / _designWidth).clamp(_minScale, _maxScale);

  double get sp => this * scale;
}

/// Layout sizes straight from Figma (width, height, radius, padding, gap, icon
/// size), scaled by the same factor as fonts: `12.w`, `176.w`, `24.w`.
///
/// Width-based on purpose, for heights too — scaling by the width ratio keeps
/// every card's proportions identical to the design on any phone, whereas a
/// height ratio would stretch cards on tall/short screens. On a 428pt device
/// (the Figma frame) every value is exactly the Figma number.
extension ResponsiveSize on num {
  double get w => this * ResponsiveFont.scale;
}
