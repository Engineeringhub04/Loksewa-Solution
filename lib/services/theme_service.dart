import 'package:flutter/material.dart';

/// App-wide theme mode override, driven by the Home header's theme toggle.
/// Defaults to [ThemeMode.system]; toggling pins light/dark explicitly.
class ThemeService {
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Flip between light and dark based on the *currently rendered* brightness.
  static void toggle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    mode.value = isDark ? ThemeMode.light : ThemeMode.dark;
  }
}
