import 'dart:typed_data';

/// Dart port of the React app's `src/core/media/pdfSource.ts`.
///
/// Share links (Google Drive `/file/d/<id>/view`, Dropbox) don't serve PDF
/// bytes directly — they return an HTML page. The native renderer (pdfx)
/// can't open HTML, so the link must be rewritten into a direct-download
/// URL first, and the bytes validated as a real PDF (Drive's virus-scan
/// interstitial is also HTML).
class PdfSource {
  PdfSource._();

  static final _driveIdPatterns = <RegExp>[
    RegExp(r'/file/d/([a-zA-Z0-9_-]+)'), // /file/d/<id>/view
    RegExp(r'[?&]id=([a-zA-Z0-9_-]+)'), // ?id=<id>
    RegExp(r'/d/([a-zA-Z0-9_-]+)'), // /d/<id>
  ];

  /// Extracts a Google Drive file id from any of its common link shapes.
  static String? driveFileId(String url) {
    for (final pattern in _driveIdPatterns) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Rewrites share links into direct-file links.
  ///
  /// A Drive "/view" link returns an HTML page, not a PDF, so it must be
  /// converted to the `uc?export=download` form before the bytes can be
  /// read. Dropbox needs the same treatment via `?dl=1`.
  static String toDirectPdfUrl(String url) {
    final trimmed = url.trim();
    if (RegExp(r'drive\.google\.com', caseSensitive: false)
        .hasMatch(trimmed)) {
      final id = driveFileId(trimmed);
      if (id != null) {
        return 'https://drive.google.com/uc?export=download&id=$id';
      }
    }
    if (RegExp(r'dropbox\.com', caseSensitive: false).hasMatch(trimmed)) {
      final noDl0 = trimmed.replaceAll(RegExp(r'[?&]dl=0'), '');
      return '$noDl0${noDl0.contains('?') ? '&' : '?'}dl=1';
    }
    return trimmed;
  }

  /// Download URLs to try in order for a Drive file.
  ///
  /// `drive.usercontent.google.com/download?...&confirm=t` serves the bytes
  /// directly and skips the virus-scan interstitial; the older `uc?export`
  /// forms are kept as fallbacks.
  static List<String> driveCandidates(String id) => [
        'https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t',
        'https://drive.google.com/uc?export=download&id=$id&confirm=t',
        'https://drive.google.com/uc?export=download&id=$id',
      ];

  /// All URLs worth attempting for a given share link, best first.
  static List<String> candidateUrls(String url) {
    final trimmed = url.trim();
    if (RegExp(r'drive\.google\.com|drive\.usercontent\.google\.com',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      final id = driveFileId(trimmed);
      if (id != null) return driveCandidates(id);
    }
    return [toDirectPdfUrl(trimmed)];
  }

  /// Every PDF begins with the bytes "%PDF-".
  ///
  /// This is how Google Drive's HTML responses (share-link preview page,
  /// virus-scan interstitial) are detected, so the next candidate URL can
  /// be tried instead of handing HTML to the renderer.
  static bool looksLikePdf(Uint8List bytes) {
    return bytes.length >= 5 &&
        bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46 && // F
        bytes[4] == 0x2D; // -
  }
}
