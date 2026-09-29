import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Question paper viewer — mirrors app/pdf/[id].tsx.
///
/// Shared in-app viewer: the header is LOCKED to the light theme (no theme
/// toggle — matching the web viewer), with a white fullscreen button on the
/// right. A floating page counter sits at the bottom-centre. Fullscreen hides
/// the header and shows a black close button at the top-right.
class PdfScreen extends StatefulWidget {
  final String id;
  final String? uri;
  final String? title;

  const PdfScreen({
    super.key,
    required this.id,
    this.uri,
    this.title,
  });

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  bool _fullscreen = false;
  bool _loading = true;
  WebViewController? _controller;

  // Page counter state (0 pages until a real renderer supplies them).
  final int _page = 1;
  final int _totalPages = 0;

  String get _resolvedTitle {
    final t = (widget.title ?? '').trim();
    return t.isNotEmpty ? t : 'Question Paper';
  }

  /// Google Docs embedded viewer — renders the PDF inside the app exactly
  /// like React's in-app pdf.js WebView does (page chrome, zoom, scroll).
  String get _viewerUrl =>
      'https://docs.google.com/viewer?url=${Uri.encodeComponent((widget.uri ?? '').trim())}&embedded=true';

  @override
  void initState() {
    super.initState();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(_viewerUrl));
    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    final uri = (widget.uri ?? '').trim();
    final hasPaper =
        uri.isNotEmpty && RegExp(r'^https?://', caseSensitive: false).hasMatch(uri);

    // No paper attached — header + not-found state, nothing else.
    if (!hasPaper) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          // SubpageHeader paints behind the status bar itself
          // (React parity) — no top inset here or the header gets pushed down.
          top: false,
          child: Column(
            children: [
              SubpageHeader(
                  title: _resolvedTitle, showThemeToggle: false),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description_outlined,
                            size: 46,
                            color: Color(0xFF9CA3AF)),
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
                                fontSize: 13,
                                color: Color(0xFF6B7280))),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF2563EB)),
                          child: const Text('Go Back',
                              style:
                                  TextStyle(color: Colors.white)),
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
                        onTap: () => setState(
                            () => _fullscreen = false),
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
                  // Floating page counter — bottom centre.
                  if (_totalPages > 0)
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xD9000000),
                            borderRadius:
                                BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.layers_outlined,
                                  size: 15,
                                  color: Colors.white),
                              const SizedBox(width: 6),
                              Text('$_page / $_totalPages',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.bold,
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
        child: const Icon(Icons.open_in_full,
            size: 19, color: Colors.white),
      ),
    );
  }

  /// In-app PDF body — Google Docs embedded viewer inside a WebView,
  /// mirroring React's in-app pdf.js viewer (same chrome, zoom + scroll).
  Widget _body() {
    final controller = _controller;
    return Stack(
      children: [
        if (controller != null) WebViewWidget(controller: controller),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                child: PreloadingWidget(
                  tinted: false,
                  label: 'Loading paper...',
                  hint: 'Preparing your pages',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
