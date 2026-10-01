import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide language switch: 'en' (English) or 'ne' (Nepali / Devanagari).
///
/// GLOBAL RULE (non-negotiable): every user-facing string in the app is
/// EITHER pure English OR pure Devanagari Nepali — never a mixed-script
/// "remix", never Romanized Nepali. Each string is written as an EN/NE pair
/// and rendered through [tr]; the profile page's language converter flips
/// [current] via [setLanguage] and the whole app rebuilds.
///
/// Brand "Loksewa Solution" always stays English. Feature name "Keep Notes"
/// is transliterated as "किप नोट्स" inside Nepali strings.
class AppLanguage {
  static const String _key = 'app_language';
  static const String english = 'en';
  static const String nepali = 'ne';

  /// Notifier the app listens to (see main.dart) so a language flip
  /// rebuilds every screen.
  static final ValueNotifier<String> current = ValueNotifier<String>(english);

  static bool get isNepali => current.value == nepali;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    current.value = saved == nepali ? nepali : english;
  }

  static Future<void> setLanguage(String code) async {
    final c = code == nepali ? nepali : english;
    if (current.value == c) return;
    current.value = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, c);
  }

  /// Returns the Nepali version when the app language is Nepali,
  /// otherwise the English version. [en] must be pure English,
  /// [ne] must be pure Devanagari Nepali.
  static String tr(String en, String ne) => isNepali ? ne : en;
}
