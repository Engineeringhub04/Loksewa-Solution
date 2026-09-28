import 'package:flutter/material.dart';

/// Brand colors carried over from the Expo app.
class AppColors {
  static const navy = Color(0xFF03145C);
  static const deepNavy = Color(0xFF000030);
  static const accent = Color(0xFFDE6E00);
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.navy),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          brightness: Brightness.dark,
        ),
      );
}

/// Expo design-token palette (mirrors src/core/theme/tokens.ts).
/// Home and its widgets read colors from here via [ExpoPalette.of].
class ExpoPalette {
  final Color primary;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color border;
  final Color divider;

  const ExpoPalette({
    required this.primary,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.border,
    required this.divider,
  });

  static const light = ExpoPalette(
    primary: Color(0xFF1D4ED8),
    background: Color(0xFFF5F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF1F6),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textDisabled: Color(0xFF94A3B8),
    border: Color(0xFFE2E8F0),
    divider: Color(0xFFE5EAF4),
  );

  static const dark = ExpoPalette(
    primary: Color(0xFF3B82F6),
    background: Color(0xFF0B1120),
    surface: Color(0xFF151D2E),
    surfaceAlt: Color(0xFF1E293B),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textDisabled: Color(0xFF64748B),
    border: Color(0xFF263349),
    divider: Color(0xFF1F2937),
  );

  static ExpoPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Spacing scale from the Expo tokens (4dp grid).
class ExpoSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double screenPadding = 16;
}

/// Radius scale from the Expo tokens.
class ExpoRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double pill = 999;
}

/// Type scale from the Expo tokens.
class ExpoType {
  static const double h3 = 17;
  static const double bodyLarge = 16;
  static const double body = 14;
  static const double bodySmall = 12;
  static const double caption = 11;
  static const double overline = 10;
}
