import 'cf_api.dart';

/// Payment brand logos (eSewa / Khalti / FonePay) whose links are managed
/// in the admin panel's Image Link Generator page and read from the worker
/// (GET /image-links), so a logo can be replaced from the panel without an
/// app update. Each logo is found by the keyword in its saved label
/// ('Esewa-Logo', 'Khalti-Logo', 'Fonepay-Logo' — first match wins).
///
/// Session cache, by design (user spec, 2026-11-04): the links are
/// fetched at most once per app run and held in static memory only —
/// nothing is written to disk. Reopening a page that shows the logos
/// reuses them instantly; closing the app clears them, so the next cold
/// start reads the panel's current links again. The logo images
/// themselves ride Flutter's in-memory ImageCache the same way.
class PaymentLogoService {
  PaymentLogoService._();

  static String? _esewaLogo;
  static String? _khaltiLogo;
  static List<String> _weAcceptLogos = const [];
  static Future<void>? _pending;

  static String? get esewaLogo => _esewaLogo;
  static String? get khaltiLogo => _khaltiLogo;

  /// The "We Accept" logos in display order (eSewa, Khalti, FonePay) —
  /// only the ones the panel currently has saved.
  static List<String> get weAcceptLogos => _weAcceptLogos;

  /// Loads the links once per app run; concurrent and repeat calls share
  /// the same fetch. Never throws — a failed load leaves the logos unset
  /// (callers fall back to their icon tiles) and clears the pending fetch
  /// so the next page open retries.
  static Future<void> ensureLoaded() {
    final pending = _pending;
    if (pending != null) return pending;
    final future = _load();
    _pending = future;
    return future;
  }

  static Future<void> _load() async {
    try {
      final rows = await CfApi.getImageLinks();
      String? find(String key) {
        for (final row in rows) {
          final label = '${row['label'] ?? ''}'
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (!label.contains(key)) continue;
          final url = '${row['imageUrl'] ?? ''}'.trim();
          if (url.startsWith('http')) return url;
        }
        return null;
      }

      _esewaLogo = find('esewa');
      _khaltiLogo = find('khalti');
      final fonepay = find('fonepay') ?? find('fone');
      _weAcceptLogos = [
        _esewaLogo,
        _khaltiLogo,
        fonepay,
      ].whereType<String>().toList(growable: false);
    } catch (_) {
      _pending = null;
    }
  }

  /// Test seam: drops the session cache so a test starts cold.
  static void debugReset() {
    _pending = null;
    _esewaLogo = null;
    _khaltiLogo = null;
    _weAcceptLogos = const [];
  }
}
