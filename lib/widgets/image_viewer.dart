import 'package:flutter/material.dart';

import '../services/app_language.dart';

/// Global image viewer (user item 10): tap any image → dimmed popup with
/// pinch-to-zoom (no +/- buttons), a black-circle X close icon top-right
/// (always visible whatever the image colors), and a small hint at the bottom.
///
/// Usage: `showImageViewer(context, someImageProvider)`.
/// Do NOT use for the edit-profile photo picker flow.
Future<void> showImageViewer(BuildContext context, ImageProvider image) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (_) => _ImageViewerDialog(image: image),
  );
}

class _ImageViewerDialog extends StatelessWidget {
  final ImageProvider image;

  const _ImageViewerDialog({required this.image});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Image(
                image: image,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Text(
              AppLanguage.tr('Pinch to zoom', 'दुई औंलाले जुम गर्नुहोस्'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
