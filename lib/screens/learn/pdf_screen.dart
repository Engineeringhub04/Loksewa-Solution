import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
/// at the bottom-centre.
///
/// Loading state is deliberately minimal: only the "Loading Pdf" label with
/// the app's preloader — no download progress UI. Fullscreen is animated:
/// the header slides up and away (~250 ms easeOut) while a floating close
/// button fades in; tapping it slides the header back down and fades the
/// button out.
class PdfScreen extends StatefulWidget {
  final String id;
  final String? uri;
  final String? title;

  /// Present when this paper is a Theory Desk set — enables the
  /// "Upload your Answer" footer (React: allowUpload === '1' && examSetId).
  final String? examSetId;
  final bool allowUpload;
  final String? sectionName;

  /// Test seam: overrides the network download (production uses http).
  final Future<Uint8List> Function(String url)? downloadBytes;

  const PdfScreen({
    super.key,
    required this.id,
    this.uri,
    this.title,
    this.examSetId,
    this.allowUpload = false,
    this.sectionName,
    this.downloadBytes,
  });

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen>
    with SingleTickerProviderStateMixin {
  bool _fullscreen = false;
  bool _loading = true;
  String? _error; // non-null => error state; the value is the hint message
  PdfControllerPinch? _pdfController;
  int _page = 1;
  int _totalPages = 0;

  /// Drives the fullscreen transition: header slides up / collapses while
  /// the close button fades in (forward), and reverses on exit.
  late final AnimationController _fsController;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _headerShrink;
  late final Animation<double> _crossFade;

  String get _resolvedTitle {
    final t = (widget.title ?? '').trim();
    return t.isNotEmpty ? t : 'Question Paper';
  }

  bool get _showUploadFooter =>
      widget.allowUpload &&
      (widget.examSetId ?? '').isNotEmpty &&
      !_fullscreen;

  void _openUpload() {
    final examSetId = widget.examSetId!;
    context.push(
      '/exam-answer/upload'
      '?examSetId=${Uri.encodeComponent(examSetId)}'
      '&examSetTitle=${Uri.encodeComponent(_resolvedTitle)}'
      '&sectionName=${Uri.encodeComponent(widget.sectionName ?? '')}',
    );
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

  /// Streams the PDF. Only the *connection* has a hard timeout (30 s); the
  /// body itself may take as long as a slow network needs — a stream stalled
  /// with no data for 90 s aborts as a timeout.
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
      final chunks = <List<int>>[];
      var received = 0;
      await for (final chunk
          in res.stream.timeout(const Duration(seconds: 90))) {
        chunks.add(chunk);
        received += chunk.length;
        onProgress(received,
            (res.contentLength != null && res.contentLength! > 0)
                ? res.contentLength
                : null);
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

  /// Tries each candidate URL until one returns bytes that actually start
  /// with the PDF magic bytes — this transparently gets past Google Drive
  /// share links (HTML preview page) and its virus-scan interstitial.
  /// (Dart port of the React app's fetchPdfAsBase64 candidate loop.)
  static Future<Uint8List> _downloadPdf(String url) async {
    final candidates = PdfSource.candidateUrls(url);
    Object? lastError;
    for (final candidate in candidates) {
      try {
        final bytes =
            await _downloadWithProgress(candidate, (_, __) {});
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
    _fsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    final eased =
        CurvedAnimation(parent: _fsController, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1),
    ).animate(eased);
    _headerShrink =
        Tween<double>(begin: 1, end: 0).animate(eased);
    _crossFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fsController, curve: Curves.easeIn),
    );
    if (_hasPaper) _openDocument();
  }

  Future<void> _openDocument() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
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
        final bytes = await (widget.downloadBytes != null
            ? widget.downloadBytes!(_uri)
            : _downloadPdf(_uri));
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
      _error = hint;
    });
  }

  void _enterFullscreen() {
    if (_fullscreen) return;
    setState(() => _fullscreen = true);
    _fsController.forward();
  }

  void _exitFullscreen() {
    if (!_fullscreen) return;
    setState(() => _fullscreen = false);
    _fsController.reverse();
  }

  @override
  void dispose() {
    _fsController.dispose();
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

    // Only ONE PdfViewPinch instance ever exists on this screen — toggling
    // fullscreen just slides the header away and fades in the close button
    // instead of remounting the viewer (a second instance would re-render
    // the whole document from scratch).
    //
    // Light-locked body: the PDF paper is always read on a white page.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // SubpageHeader paints behind the status bar itself
        // (React parity) — no top inset here or the header gets pushed down.
        top: false,
        child: Column(
          children: [
            // Animated header: slides up and collapses away on fullscreen,
            // slides back down on exit (~250 ms easeOut). It stays mounted
            // so the reverse animation has something to play on.
            ClipRect(
              child: SizeTransition(
                sizeFactor: _headerShrink,
                axis: Axis.vertical,
                alignment: Alignment.topCenter,
                child: SlideTransition(
                  position: _headerSlide,
                  child: SubpageHeader(
                    title: _resolvedTitle,
                    showThemeToggle: false,
                    actions: [
                      _fullscreenButton(),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  _body(),
                  // Fullscreen close button — fades in floating at the top
                  // right (below the status bar); fades out on exit.
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    right: 16,
                    child: FadeTransition(
                      key: const ValueKey('pdf-fullscreen-close'),
                      opacity: _crossFade,
                      child: IgnorePointer(
                        ignoring: !_fullscreen,
                        child: GestureDetector(
                          onTap: _exitFullscreen,
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
                    ),
                  ),
                  // Floating page counter — bottom centre (real page numbers
                  // now, driven by the native renderer). Lifted when the
                  // upload footer is showing (React parity).
                  if (_totalPages > 0 && !_loading && _error == null)
                    Positioned(
                      bottom: _showUploadFooter ? 84 : 24,
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
            // "Upload your Answer" footer — Theory Desk sets only
            // (React: app/pdf/[id].tsx showUploadFooter).
            if (_showUploadFooter)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openUpload,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text(
                      'Upload your Answer',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fullscreenButton() {
    return GestureDetector(
      onTap: _enterFullscreen,
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

  /// In-app PDF body — native renderer (pdfx), no web viewer involved.
  Widget _body() {
    if (_loading) {
      // Minimal loading state: label + preloader only, no download
      // progress UI.
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: PreloadingWidget(
            tinted: false,
            label: 'Loading Pdf',
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
                Text(_error!,
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
