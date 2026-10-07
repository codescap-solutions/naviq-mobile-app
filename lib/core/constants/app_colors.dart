import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color primaryColor = Color(0xFF0066FF); // Brand blue
  static const Color accentColor = Color(0xFF00C096);  // Green accent
  static const Color backgroundColor = Color(0xFFF7FAFC);

  // Brand Colors
  static const Color primaryBlue = Color(0xFF0066FF);
  static const Color darkNavy = Color(0xFF0C1D37);
  static const Color textMuted = Color(0xFF5F6368);

  // Text Colors
  static const Color textPrimary = Color(0xFF0C1D37);
  static const Color textSecondary = Color(0xFF5F6368);
  static const Color textHint = Color(0xFFBDBDBD);
  static const Color containerBackground = Color(0xFFF5F9FE);
  
  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF0066FF);

  // Background Colors
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color beach = Color(0xFFFFEFD5); // Light beach-sand color for map placeholder

  static const Color tripPolyline = Color(0xFFAB47BC); // Purple 400

  // Border Colors
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color dividerColor = Color(0xFFE2E8F0);

  // Onboarding Feature Cards Specific Colors
  static const Color locationBorder = Color(0xFFD2E3FC);
  static const Color locationIconBg = Color(0xFFEEF3FC);
  static const Color locationIcon = Color(0xFF1A73E8);

  static const Color geofenceBorder = Color(0xFFCEF6EC);
  static const Color geofenceIconBg = Color(0xFFE8FAF6);
  static const Color geofenceIcon = Color(0xFF00C096);

  static const Color scrollBorder = Color(0xFFFEEFC3);
  static const Color scrollIconBg = Color(0xFFFEF7E0);
  static const Color scrollIcon = Color(0xFFF9AB00);

  static const Color activityBorder = Color(0xFFE8DDFC);
  static const Color activityIconBg = Color(0xFFF3EEFD);
  static const Color activityIcon = Color(0xFF7A4AF6);

  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, Color(0xFF6F9EFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient onboardingBackgroundGradient = LinearGradient(
    colors: [
      Color(0xFFFBFCFE),
      Color(0xFFEDF4FE),
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
