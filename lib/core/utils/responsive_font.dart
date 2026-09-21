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

  double get sp {
    final scale = (_screenWidth / _designWidth).clamp(_minScale, _maxScale);
    return this * scale;
  }
}
