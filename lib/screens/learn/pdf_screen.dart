import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// PDF viewer placeholder — mirrors app/pdf/[id].tsx.
/// The route id is the URL-encoded PDF URL (or ?uri=... / ?title=...).
/// Real pdf.js-style rendering lands in a later batch; this keeps the
/// navigation contract (page indicator, fullscreen toggle) in place.
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
  int _page = 1;
  final int _totalPages = 0; // filled by the real viewer later

  @override
  Widget build(BuildContext context) {
    final source =
        widget.uri ?? (widget.id.isEmpty ? null : Uri.decodeComponent(widget.id));
    final isValid = source != null && source.startsWith(RegExp(r'https?://', caseSensitive: false));

    if (!isValid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Question Paper')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No paper attached',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('This set does not have a question paper uploaded yet.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _fullscreen
          ? null
          : AppBar(
              title: Text(widget.title ?? 'Question Paper'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () => setState(() => _fullscreen = true),
                ),
              ],
            ),
      body: Stack(
        children: [
          // Placeholder body — replaced by the real PDF renderer later.
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.picture_as_pdf_outlined,
                      size: 72, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(widget.title ?? 'Question Paper',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'PDF rendering arrives in a later batch.\nThe paper URL is ready below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(source,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.blue)),
                ],
              ),
            ),
          ),
          if (_totalPages > 0)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers_outlined,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('$_page / $_totalPages',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          if (_fullscreen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: GestureDetector(
                onTap: () => setState(() => _fullscreen = false),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
