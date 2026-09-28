import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper over SharedPreferences (mirrors AsyncStorage usage).
class PrefsService {
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static Future<String?> getString(String key) async =>
      (await _instance).getString(key);

  static Future<void> setString(String key, String value) async =>
      (await _instance).setString(key, value);

  static Future<bool?> getBool(String key) async =>
      (await _instance).getBool(key);

  static Future<void> setBool(String key, bool value) async =>
      (await _instance).setBool(key, value);

  static Future<void> remove(String key) async =>
      (await _instance).remove(key);

  // Well-known keys
  static const onboardingSeen = 'onboarding_seen';
  static const evictionNotice = 'eviction_notice_device_name';
  static const sessionKey = 'firebase_session';
}

/// Module-level routing guard — survives widget rebuilds.
/// decide() only ever routes once per app launch.
bool splashHasRouted = false;
