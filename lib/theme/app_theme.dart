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
