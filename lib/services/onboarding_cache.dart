import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Preloads and caches the onboarding slide images so the onboarding screen
/// shows instantly, like a native app.
///
/// Two slides ship as bundled assets; two come from the network. Network
/// images are downloaded once into the app support directory and reused from
/// disk on later launches, so the second launch needs no network at all.
/// All work is deadline-bounded and never throws — on any failure the
/// onboarding screen simply lazy-loads, exactly like before this cache.
class OnboardingCache {
  /// Exact image sources of the 4 hardcoded onboarding slides.
  static const localAssets = [
    'assets/images/ws-weeklytest.png',
    'assets/images/ws-leaderboard_analytics.png',
  ];
  static const networkUrls = [
    'https://i.ibb.co/hN8gtSc/dailytest-wlc.png',
    'https://i.ibb.co/9HYXh3nr/discussion-wlc.png',
  ];

  static const _perFileTimeout = Duration(seconds: 8);
  static const _totalDeadline = Duration(seconds: 10);

  /// Support-dir path captured during [warmUp]; null until then (or when
  /// warm-up could not reach the filesystem). [resolve] degrades gracefully.
  static String? _supportPath;

  /// FNV-1a 32-bit hash, hex-encoded. Stable across runs (unlike
  /// String.hashCode), so cached filenames stay valid between launches.
  static String _fnv1aHex(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static File _fileFor(String supportPath, String url) =>
      File('$supportPath/onboarding/${_fnv1aHex(url)}.png');

  /// Downloads every onboarding image into memory/disk cache. Call from the
  /// splash screen before routing to onboarding. Never throws.
  static Future<void> warmUp(BuildContext context) async {
    try {
      await _warmUpInner(context).timeout(_totalDeadline);
    } catch (_) {
      // Timeout or any error: onboarding falls back to lazy loading.
    }
  }

  static Future<void> _warmUpInner(BuildContext context) async {
    // Bundled assets are instant, but precache so the first frame is ready.
    for (final asset in localAssets) {
      if (!context.mounted) return;
      try {
        await precacheImage(AssetImage(asset), context);
      } catch (_) {}
    }

    // Network images: persist to disk, then precache from the file.
    Directory? dir;
    try {
      final support = await getApplicationSupportDirectory()
          .timeout(const Duration(seconds: 3));
      dir = Directory('${support.path}/onboarding');
      if (!await dir.exists()) await dir.create(recursive: true);
      _supportPath = support.path;
    } catch (_) {
      dir = null;
    }
    if (dir == null || !context.mounted) return;

    for (final url in networkUrls) {
      if (!context.mounted) return;
      try {
        final file = _fileFor(dir.path, url);
        if (!await file.exists()) {
          await _download(url, file).timeout(_perFileTimeout);
        }
        if (await file.exists()) {
          if (!context.mounted) return;
          await precacheImage(FileImage(file), context);
        }
      } catch (_) {
        // Per-file failure: this slide lazy-loads from the network instead.
      }
    }
  }

  static Future<void> _download(String url, File file) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return;
      final bytes = await consolidateHttpClientResponseBytes(response);
      await file.writeAsBytes(bytes, flush: true);
    } finally {
      client.close(force: true);
    }
  }

  /// Resolves a slide image to the fastest available provider: bundled asset,
  /// disk-cached file, or network. Returns null when neither source is set,
  /// so the caller can show a placeholder.
  static ImageProvider<Object>? resolve(String? assetPath, String? imageUrl) {
    if (assetPath != null && assetPath.isNotEmpty) {
      return AssetImage(assetPath);
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final path = _supportPath;
      if (path != null) {
        try {
          final file = _fileFor(path, imageUrl);
          if (file.existsSync()) return FileImage(file);
        } catch (_) {}
      }
      return NetworkImage(imageUrl);
    }
    return null;
  }
}
