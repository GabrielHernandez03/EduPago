import 'package:flutter/material.dart';

/// Paleta EduPago: dashboard claro y navegación azul marino.
class AppColors {
  static const Color primaryBlue = Color(0xFF246BFA);
  static const Color primaryDark = Color(0xFF1958D8);
  static const Color primaryLight = Color(0xFFEDF4FF);
  static const Color darkNavy = Color(0xFF10234C);
  static const Color textDark = Color(0xFF10234C);
  static const Color textMuted = Color(0xFF526C98);
  static const Color backgroundLight = Color(0xFFF7FAFF);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color cardBorder = Color.fromARGB(255, 193, 200, 211);
  static const Color securityBg = Color(0xFF0A0E1A);
  static const Color sidebarTop = Color(0xFF152F5B);
  static const Color sidebarBottom = Color(0xFF0C1934);
  static const Color successGreen = Color(0xFF087A49);
  static const Color errorRed = Color(0xFFB91C1C);
  static const Color warningAmber = Color(0xFF9A5600);
  static const Color violet = Color(0xFF6044CE);
  static const Color lavender = Color(0xFFF1EFFF);
  static const Color mint = Color(0xFFE5F8F0);

  static Color tint(Color state, [double alpha = 0.12]) =>
      state.withValues(alpha: alpha);

  static const Color onDarkMuted = Color(0xFFD7E3FA);
  static const Color onDarkSubtle = Color(0xFFB1C3E4);
}

class AppSizes {
  static const double minTarget = 44;
  static const double control = 48;
  static const double radiusControl = 12;
  static const double radiusCard = 16;
}
