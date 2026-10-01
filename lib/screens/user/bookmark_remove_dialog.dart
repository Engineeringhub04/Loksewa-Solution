import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';

/// Remove-bookmark confirm card — the shared AppModalShell global modal
/// (same modal as the daily-limit popup everywhere in the app; only the
/// content differs). Shown via `AppModalShell.show<bool>`; pops `true` on
/// Remove, `false`/null on Cancel or X.
class BookmarkRemoveDialog extends StatelessWidget {
  final Map<String, dynamic> item;
  const BookmarkRemoveDialog({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return AppModalShell(
      maxWidth: 340,
      tagLabel: AppLanguage.tr('Bookmarks', 'बुकमार्कहरू'),
      accent: const Color(0xFFDC2626),
      accentMid: const Color(0xFFF87171),
      accentLight: const Color(0xFFFECACA),
      tagColor: const Color(0xFFDC2626),
      onClose: () => Navigator.of(context).pop(false),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: pal.danger,
        ),
        child: const Icon(
          Icons.bookmark_remove_outlined,
          size: 28,
          color: Colors.white,
        ),
      ),
      title: Text(
        AppLanguage.tr('Remove this bookmark?', 'यो बुकमार्क हटाउने?'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (item['title'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF0F172A),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.tr('You can save it again any time.',
                'तपाईंले यसलाई जुनसुकै बेला फेरि सेभ गर्न सक्नुहुन्छ।'),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: pal.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(AppLanguage.tr('Remove', 'हटाउनुहोस्')),
            ),
          ),
        ],
      ),
    );
  }
}
