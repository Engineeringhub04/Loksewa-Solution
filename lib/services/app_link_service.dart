import 'firestore_rest.dart';

/// App Links configuration — the runtime source of the share URL and the app
/// domain. Read from Firestore (`app_applink_details/main`, public read) so the
/// links can change without an app update; cached in memory after the first
/// load. Falls back to the domain root until the document is seeded.
class AppLinkService {
  static const String _docPath = 'app_applink_details/main';

  /// Used when the Firestore document is not seeded yet.
  static const String fallbackShareLink = 'https://www.kbr.com.np';

  /// App domain used for App Links (host only, no scheme).
  static const String fallbackAppDomainLink = 'www.kbr.com.np';

  static Map<String, dynamic>? _doc;
  static bool _loaded = false;
  static Future<void>? _inflight;

  /// Loads (and caches) the document. Safe to call repeatedly or concurrently.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    _inflight ??= _fetch();
    return _inflight!;
  }

  static Future<void> _fetch() async {
    try {
      _doc = await FirestoreRest.getDocument(_docPath);
    } catch (_) {
      _doc = null;
    }
    _loaded = true;
  }

  static String _field(String key, String fallback) {
    final v = _doc?[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return fallback;
  }

  /// Canonical share URL (the `link` field). Falls back to the domain root.
  static String get shareLink => _field('link', fallbackShareLink);

  /// App domain for App Links (the `appDomainLink` field, host only).
  static String get appDomainLink =>
      _field('appDomainLink', fallbackAppDomainLink);

  /// Clears the in-memory cache (used in tests).
  static void resetForTest() {
    _doc = null;
    _loaded = false;
    _inflight = null;
  }
}
