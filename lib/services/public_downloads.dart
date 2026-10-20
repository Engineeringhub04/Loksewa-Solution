import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Saves files into the phone's REAL public Downloads folder (v1.0.120).
///
/// Until now every "save to Downloads" in the app used path_provider's
/// `getDownloadsDirectory()`, which on Android is the app-private
/// `Android/data/<pkg>/files/downloads` folder — files landed there
/// successfully but were invisible in the phone's Downloads app, so
/// users experienced "the download never saved". With the current
/// targetSdk and no storage permission, the public folder is reachable
/// only through MediaStore, which the native side of the existing
/// `loksewa_solution/media` channel implements as `saveToDownloads`.
///
/// Returns true ONLY when the file truly landed in the public Downloads
/// folder — callers use that to word their confirmation honestly and to
/// fall back to the app-folder write when it is false. Never throws.
class PublicDownloads {
  static const MethodChannel _channel =
      MethodChannel('loksewa_solution/media');

  /// Test seam: replaces the platform-channel save call.
  @visibleForTesting
  static Future<Object?> Function(Map<String, dynamic> args)? channelInvoker;

  /// Test seam: replaces the platform-channel open call. Kept separate
  /// from [channelInvoker] because the native method name differs
  /// ('openDownloadedFile') and the save seam's existing tests must
  /// keep their exact behavior.
  @visibleForTesting
  static Future<Object?> Function(Map<String, dynamic> args)? openInvoker;

  /// The one raw save call behind both public save variants. Answers
  /// whatever the native side answered — the content URI string on
  /// success, null when the device is below API 29, the insert was
  /// refused, the platform is not Android, or the call failed.
  static Future<Object?> _saveRaw(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final args = <String, dynamic>{
        'bytes': bytes,
        'fileName': fileName,
        'mimeType': mimeType,
      };
      return channelInvoker != null
          ? await channelInvoker!(args)
          : await _channel.invokeMethod<Object?>('saveToDownloads', args);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveToPublicDownloads(
    Uint8List bytes,
    String fileName, {
    String mimeType = 'application/pdf',
  }) async {
    // The native side answers the content URI on success, null when
    // the device is below API 29 or the insert was refused.
    return await _saveRaw(bytes, fileName, mimeType) != null;
  }

  /// Same save as [saveToPublicDownloads] but answers the saved file's
  /// content URI (v1.0.121) — the download-complete notification uses
  /// it as its tap payload so tapping opens THIS saved file. Null when
  /// the save did not land in the public Downloads folder.
  static Future<String?> saveToPublicDownloadsUri(
    Uint8List bytes,
    String fileName, {
    String mimeType = 'application/pdf',
  }) async {
    final result = await _saveRaw(bytes, fileName, mimeType);
    return result is String ? result : null;
  }

  /// Opens a file previously saved into the public Downloads folder
  /// (v1.0.121), via the native 'openDownloadedFile' channel method —
  /// an ACTION_VIEW intent with a read grant on the content URI.
  /// True only when the native side actually launched a viewer.
  /// Never throws.
  static Future<bool> openDownloadedFile(String uri, String mimeType) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final args = <String, dynamic>{
        'uri': uri,
        'mimeType': mimeType,
      };
      final result = openInvoker != null
          ? await openInvoker!(args)
          : await _channel.invokeMethod<Object?>('openDownloadedFile', args);
      return result == true;
    } catch (_) {
      return false;
    }
  }
}
