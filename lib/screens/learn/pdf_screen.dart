import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Question paper viewer — mirrors app/pdf/[id].tsx.
///
/// Native in-app PDF viewer (pdfx): the PDF is downloaded once into a local
/// cache and rendered by the phone's own native PDF engine
/// (Android PdfRenderer) — no Google Docs / Drive / third-party web viewer.
/// The header is LOCKED to the light theme (no theme toggle), with a white
/// fullscreen button on the right. A floating page counter sits at the
/// bottom-centre. Fullscreen hides the header and shows a black close button
/// at the top-right.
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
  String? _error;
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

  static Future<Uint8List> _download(String url) async {
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('download failed (${res.statusCode})');
    }
    return res.bodyBytes;
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
    });
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/pdf_cache');
      // Sync fs ops: a tiny cache dir costs microseconds, and async fs
      // calls are unreliable under flutter_test's fake-async zone.
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$_cacheName');

      // Download once; reuse the cached file afterwards.
      if (!file.existsSync() || file.lengthSync() == 0) {
        final bytes = await (widget.downloadBytes != null
            ? widget.downloadBytes!(_uri)
            : _download(_uri));
        if (bytes.isEmpty) throw Exception('empty pdf');
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
    } catch (_) {
      // Drop a partial/corrupt download so retry starts clean.
      try {
        final tmp = await getTemporaryDirectory();
        final f = File('${tmp.path}/pdf_cache/$_cacheName');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'load';
      });
    }
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

  /// In-app PDF body — native renderer (pdfx), no web viewer involved.
  Widget _body() {
    if (_loading) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: PreloadingWidget(
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
                const Text(
                    'Please check your connection and try again.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
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
            _error = 'load';
            _loading = false;
          });
        }
      },
    );
  }
}
