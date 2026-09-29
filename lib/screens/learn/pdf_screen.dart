import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../../services/pdf_source.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Question paper viewer — mirrors app/pdf/[id].tsx.
///
/// Native in-app PDF viewer (pdfx): the PDF is downloaded once into a local
/// cache and rendered by the phone's own native PDF engine
/// (Android PdfRenderer) — no Google Docs / Drive / third-party web viewer.
/// Share links (Drive `/file/d/<id>/view`, Dropbox) are rewritten into
/// direct-download URLs first (Dart port of the React app's
/// `src/core/media/pdfSource.ts`) — a raw share link serves an HTML page,
/// not PDF bytes. The header is LOCKED to the light theme (no theme toggle),
/// with a white fullscreen button on the right. A floating page counter sits
/// at the bottom-centre. Fullscreen hides the header and shows a black close
/// button at the top-right.
class PdfScreen extends StatefulWidget {
  final String id;
  final String? uri;
  final String? title;

  /// Test seam: overrides the network download (production uses http).
  final Future<Uint8List> Function(String url)? downloadBytes;

  const PdfScreen({
    super.key,
    required this.id,
    this.uri,
    this.title,
    this.downloadBytes,
  });

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  bool _fullscreen = false;
  bool _loading = true;
  String? _error; // non-null => error state; the value is the hint message
  bool _downloading = false;
  int _dlReceived = 0;
  int? _dlTotal;
  int _lastProgressUi = 0;
  PdfControllerPinch? _pdfController;
  int _page = 1;
  int _totalPages = 0;

  String get _resolvedTitle {
    final t = (widget.title ?? '').trim();
    return t.isNotEmpty ? t : 'Question Paper';
  }

  String get _uri => (widget.uri ?? '').trim();

  bool get _hasPaper =>
      _uri.isNotEmpty &&
      RegExp(r'^https?://', caseSensitive: false).hasMatch(_uri);

  /// Cache file for this paper — repeat opens are instant and offline-safe.
  String get _cacheName {
    final safe =
        widget.id.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return '${safe.isEmpty ? 'doc' : safe}.pdf';
  }

  /// Streams the PDF with live progress. Only the *connection* has a hard
  /// timeout (30 s); the body itself may take as long as a slow network
  /// needs — a stream stalled with no data for 90 s aborts as a timeout.
  /// (The old pdf.js viewer rendered page 1 progressively; the native
  /// renderer needs the whole file first, so on slow mobile data the user
  /// must see progress instead of a blind spinner + 60 s cutoff.)
  static Future<Uint8List> _downloadWithProgress(
    String url,
    void Function(int received, int? total) onProgress,
  ) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('download failed (${res.statusCode})');
      }
      final declared = res.contentLength;
      final total = (declared != null && declared > 0) ? declared : null;
      final chunks = <List<int>>[];
      var received = 0;
      await for (final chunk
          in res.stream.timeout(const Duration(seconds: 90))) {
        chunks.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      final out = Uint8List(received);
      var offset = 0;
      for (final c in chunks) {
        out.setRange(offset, offset + c.length, c);
        offset += c.length;
      }
      if (out.isEmpty) throw Exception('empty pdf');
      return out;
    } finally {
      client.close();
    }
  }

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  /// Tries each candidate URL until one returns bytes that actually start
  /// with the PDF magic bytes — this transparently gets past Google Drive
  /// share links (HTML preview page) and its virus-scan interstitial.
  /// (Dart port of the React app's fetchPdfAsBase64 candidate loop.)
  static Future<Uint8List> _downloadPdf(
    String url,
    void Function(int received, int? total) onProgress,
  ) async {
    final candidates = PdfSource.candidateUrls(url);
    Object? lastError;
    for (final candidate in candidates) {
      try {
        final bytes = await _downloadWithProgress(candidate, onProgress);
        if (PdfSource.looksLikePdf(bytes)) return bytes;
        lastError = Exception('not a pdf');
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('download failed');
  }

  /// A cached file is only reusable when it is a real PDF. Older builds
  /// cached Drive's HTML preview page (the raw share link was downloaded
  /// as-is) — those stale entries must re-download, not be reused forever.
  static bool _isCachedPdf(File file) {
    try {
      if (!file.existsSync() || file.lengthSync() < 5) return false;
      final raf = file.openSync(mode: FileMode.read);
      final head = raf.readSync(5);
      raf.closeSync();
      return PdfSource.looksLikePdf(Uint8List.fromList(head));
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_hasPaper) _openDocument();
  }

  Future<void> _openDocument() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _downloading = false;
      _dlReceived = 0;
      _dlTotal = null;
    });
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/pdf_cache');
      // Sync fs ops: a tiny cache dir costs microseconds, and async fs
      // calls are unreliable under flutter_test's fake-async zone.
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$_cacheName');

      // Drop a stale cache entry (e.g. an HTML preview page cached by an
      // older build that downloaded the raw share link) so this open
      // re-downloads through the direct-download candidates.
      if (file.existsSync() && !_isCachedPdf(file)) {
        try {
          file.deleteSync();
        } catch (_) {}
      }

      // Download once; reuse the cached file afterwards.
      if (!file.existsSync() || file.lengthSync() == 0) {
        setState(() => _downloading = true);
        final bytes = await (widget.downloadBytes != null
            ? widget.downloadBytes!(_uri)
            : _downloadPdf(_uri, (received, total) {
                if (!mounted) return;
                // Throttle UI updates: chunks can arrive hundreds per
                // second on fast networks.
                final now = DateTime.now().millisecondsSinceEpoch;
                _dlReceived = received;
                _dlTotal = total;
                if (now - _lastProgressUi < 150) return;
                _lastProgressUi = now;
                setState(() {});
              }));
        if (mounted) setState(() => _downloading = false);
        await file.writeAsBytes(bytes, flush: true);
      }

      final documentFuture = PdfDocument.openFile(file.path);
      final controller = PdfControllerPinch(document: documentFuture);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _pdfController?.dispose();
        _pdfController = controller;
        _page = 1;
        _loading = false;
      });
    } on TimeoutException {
      await _failDownload('The download is taking too long on this '
          'connection.\nPlease try again on a faster network.');
    } catch (_) {
      await _failDownload('Please check your connection and try again.');
    }
  }

  /// Drops a partial/corrupt download so retry starts clean, then shows the
  /// error state with the given hint.
  Future<void> _failDownload(String hint) async {
    try {
      final tmp = await getTemporaryDirectory();
      final f = File('${tmp.path}/pdf_cache/$_cacheName');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      _downloading = false;
      _error = hint;
    });
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No paper attached — header + not-found state, nothing else.
    if (!_hasPaper) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          // SubpageHeader paints behind the status bar itself
          // (React parity) — no top inset here or the header gets pushed down.
          top: false,
          child: Column(
            children: [
              SubpageHeader(title: _resolvedTitle, showThemeToggle: false),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description_outlined,
                            size: 46, color: Color(0xFF9CA3AF)),
                        const SizedBox(height: 14),
                        const Text('No paper attached',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A))),
                        const SizedBox(height: 8),
                        const Text(
                            'This set does not have a question paper uploaded yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF6B7280))),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB)),
                          child: const Text('Go Back',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Light-locked body: the PDF paper is always read on a white page.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // SubpageHeader paints behind the status bar itself
        // (React parity) — no top inset here or the header gets pushed down.
        top: false,
        child: Column(
          children: [
            if (!_fullscreen)
              SubpageHeader(
                title: _resolvedTitle,
                showThemeToggle: false,
                actions: [
                  _fullscreenButton(),
                ],
              ),
            Expanded(
              child: Stack(
                children: [
                  _body(),
                  // Fullscreen close button — top right below the status bar.
                  if (_fullscreen)
                    Positioned(
                      top: 12,
                      right: 16,
                      child: GestureDetector(
                        onTap: () => setState(() => _fullscreen = false),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0xD9000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 22, color: Colors.white),
                        ),
                      ),
                    ),
                  // Floating page counter — bottom centre (real page numbers
                  // now, driven by the native renderer).
                  if (_totalPages > 0 && !_loading && _error == null)
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xD9000000),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.layers_outlined,
                                  size: 15, color: Colors.white),
                              const SizedBox(width: 6),
                              Text('$_page / $_totalPages',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fullscreenButton() {
    return GestureDetector(
      onTap: () => setState(() => _fullscreen = true),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.open_in_full, size: 19, color: Colors.white),
      ),
    );
  }

  /// Download progress UI — shown instead of the blind spinner while the
  /// PDF streams in. Matters on slow mobile data: the old pdf.js viewer
  /// rendered page 1 progressively, the native renderer needs the whole
  /// file first, so the user must see % + MB instead of nothing.
  Widget _downloadProgress() {
    final total = _dlTotal;
    final progress = (total != null && total > 0)
        ? (_dlReceived / total).clamp(0.0, 1.0)
        : null;
    final sizeLabel = total != null && total > 0
        ? '${_mb(_dlReceived)} / ${_mb(total)} MB'
        : '${_mb(_dlReceived)} MB downloaded';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PreloadingWidget(
            tinted: false,
            label: 'Downloading paper...',
            hint: 'One-time download, then it opens instantly',
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            progress != null
                ? '$sizeLabel  •  ${(progress * 100).toStringAsFixed(0)}%'
                : sizeLabel,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  /// In-app PDF body — native renderer (pdfx), no web viewer involved.
  Widget _body() {
    if (_loading) {
      return ColoredBox(
        color: Colors.white,
        child: Center(
          child: _downloading
              ? _downloadProgress()
              : const PreloadingWidget(
                  tinted: false,
                  label: 'Loading paper...',
                  hint: 'Preparing your pages',
                ),
        ),
      );
    }
    if (_error != null) {
      return ColoredBox(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 46, color: Color(0xFF9CA3AF)),
                const SizedBox(height: 14),
                const Text("Couldn't load paper",
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF6B7280))),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _openDocument,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB)),
                  child: const Text('Retry',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final controller = _pdfController;
    if (controller == null) return const SizedBox.shrink();
    return PdfViewPinch(
      controller: controller,
      // Native pinch-zoom: re-renders the page texture on zoom so text
      // stays sharp (no quality loss like the old web viewer).
      onDocumentLoaded: (document) {
        if (mounted) {
          setState(() {
            _totalPages = document.pagesCount;
            _page = 1;
          });
        }
      },
      onPageChanged: (page) {
        if (mounted) setState(() => _page = page);
      },
      onDocumentError: (_) {
        if (mounted) {
          setState(() {
            _error = 'Please check your connection and try again.';
            _loading = false;
          });
        }
      },
    );
  }
}
