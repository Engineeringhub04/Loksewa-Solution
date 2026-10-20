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

  /// Test seam: replaces the platform-channel call.
  @visibleForTesting
  static Future<Object?> Function(Map<String, dynamic> args)? channelInvoker;

  static Future<bool> saveToPublicDownloads(
    Uint8List bytes,
    String fileName, {
    String mimeType = 'application/pdf',
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final args = <String, dynamic>{
        'bytes': bytes,
        'fileName': fileName,
        'mimeType': mimeType,
      };
      final result = channelInvoker != null
          ? await channelInvoker!(args)
          : await _channel.invokeMethod<Object?>('saveToDownloads', args);
      // The native side answers the content URI on success, null when
      // the device is below API 29 or the insert was refused.
      return result != null;
    } catch (_) {
      return false;
    }
  }
}
