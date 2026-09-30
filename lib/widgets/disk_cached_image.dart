import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Network image with a persistent disk cache, so remote images show
/// INSTANTLY on repeat launches and after app resume — no blank gaps while
/// re-downloading.
///
/// The file lives at `<appSupportDir>/imgcache/<fnv1a-hex(url)>`. While the
/// file is missing it is downloaded in the background (30s timeout) over a
/// subtle placeholder; once saved, later builds render `Image.file`
/// synchronously. Never throws — on any failure the caller-provided
/// [errorBuilder] runs (or an empty box is shown).
class DiskCachedImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const DiskCachedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
  });

  /// FNV-1a 32-bit hash, hex-encoded. Stable across runs (unlike
  /// String.hashCode), so cached filenames stay valid between launches.
  static String fnv1aHex(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Ensures [url] is in the disk cache, downloading it if missing.
  /// Use before revealing a screen so its photos paint instantly instead of
  /// popping in one by one. Never throws. [timeout] bounds the whole wait.
  static Future<void> warm(String url,
      {Duration timeout = const Duration(seconds: 8)}) async {
    if (url.isEmpty) return;
    try {
      await (() async {
        final support = await getApplicationSupportDirectory();
        final file = File('${support.path}/imgcache/${fnv1aHex(url)}');
        if (await file.exists()) return;
        await _download(url, file).timeout(const Duration(seconds: 30));
      })()
          .timeout(timeout);
    } catch (_) {
      // Best-effort: the widget falls back to its placeholder/error UI.
    }
  }

  static Future<void> _download(String url, File file) async {
    final client = HttpClient();
    try {
      await file.parent.create(recursive: true);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return;
      final bytes = await consolidateHttpClientResponseBytes(response);
      await file.writeAsBytes(bytes, flush: true);
    } finally {
      client.close(force: true);
    }
  }

  @override
  State<DiskCachedImage> createState() => _DiskCachedImageState();
}

class _DiskCachedImageState extends State<DiskCachedImage> {
  static const _downloadTimeout = Duration(seconds: 30);

  File? _file;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DiskCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _file = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final support = await getApplicationSupportDirectory()
          .timeout(const Duration(seconds: 3));
      final file =
          File('${support.path}/imgcache/${DiskCachedImage.fnv1aHex(widget.url)}');
      if (await file.exists()) {
        if (mounted) setState(() => _file = file);
        return;
      }
      await DiskCachedImage._download(widget.url, file)
          .timeout(_downloadTimeout);
      if (await file.exists() && mounted) setState(() => _file = file);
    } catch (_) {
      // Falls through to _failed below.
    }
    if (_file == null && mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_file != null) {
      return Image.file(
        _file!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: widget.errorBuilder ??
            (_, __, ___) =>
                SizedBox(width: widget.width, height: widget.height),
      );
    }
    if (_failed) {
      final eb = widget.errorBuilder;
      return eb != null
          ? eb(context, Exception('image load failed'), null)
          : SizedBox(width: widget.width, height: widget.height);
    }
    // Subtle placeholder while the first download runs.
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
