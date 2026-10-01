import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/trash_icon.dart';

/// Remove-bookmark confirm card — the shared AppModalShell global modal
/// (same modal as the daily-limit popup everywhere in the app; only the
/// content differs). Shown via `AppModalShell.show<bool>`; pops `true` on a
/// completed Remove, `false`/null on Cancel or X.
///
/// The actual removal is the caller's [onRemove] (the screen's own Firestore
/// delete path — the dialog never touches storage itself), but the UX runs
/// inside the dialog:
/// - Tapping Remove swaps the header tile's trash icon for a
///   CircularProgressIndicator in place (AnimatedSwitcher, same 28px box,
///   so there is no layout jump) and blocks Cancel/X meanwhile.
/// - On success the dialog pops `true` — AppModalShell.show's reverse
///   transition fades + scales the card out over 200ms; the caller refreshes
///   the list AFTER the pop future resolves.
/// - On error the spinner morphs back to the trash icon, the dialog stays
///   open, and an error toast is shown.
///
/// Copy mirrors React's `ConfirmDialog` remove (bookmarks.removeTitle /
/// removeBody / removeConfirm), with the danger accent (#DC2626) and the
/// mockup TrashIcon as the delete glyph.
class BookmarkRemoveDialog extends StatefulWidget {
  final Map<String, dynamic> item;

  /// Runs the actual removal (the caller's Firestore delete path).
  /// Success → the dialog pops `true`; throw on failure → the dialog stays
  /// open with an error toast.
  final Future<void> Function() onRemove;

  const BookmarkRemoveDialog({
    super.key,
    required this.item,
    required this.onRemove,
  });

  @override
  State<BookmarkRemoveDialog> createState() => _BookmarkRemoveDialogState();
}

class _BookmarkRemoveDialogState extends State<BookmarkRemoveDialog> {
  bool _deleting = false;

  Future<void> _confirmRemove() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.onRemove();
      if (!mounted) return;
      // Pop through the shell: AppModalShell.show is a showGeneralDialog
      // whose reverse transition fades + scales the card out over 200ms.
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      // Spinner morphs back to the delete icon; the dialog STAYS OPEN.
      setState(() => _deleting = false);
      showToast(
        context,
        AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
        ToastVariant.error,
      );
    }
  }

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
      // Cancel and the X are blocked while the delete runs (React's
      // confirmLoading behaviour); the spinner below is the progress signal.
      onClose: _deleting ? null : () => Navigator.of(context).pop(false),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: pal.danger,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: _deleting
              ? const SizedBox(
                  key: ValueKey('removing'),
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              : const TrashIcon(
                  key: ValueKey('delete'),
                  size: 28,
                  color: Colors.white,
                ),
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
            (widget.item['title'] ?? '').toString(),
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
                'फेरि कुनै पनि बेला राख्न सकिन्छ।'),
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
              onPressed:
                  _deleting ? null : () => Navigator.of(context).pop(false),
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
              onPressed: _deleting ? null : _confirmRemove,
              style: FilledButton.styleFrom(
                backgroundColor: pal.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(_deleting
                  ? AppLanguage.tr('Removing…', 'हटाउँदैछ…')
                  : AppLanguage.tr('Remove', 'हटाउनुहोस्')),
            ),
          ),
        ],
      ),
    );
  }
}
