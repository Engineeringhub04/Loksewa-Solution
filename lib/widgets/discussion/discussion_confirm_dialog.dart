// Shared AppModalShell confirm dialog for destructive discussion actions.
// Implements the standing popup-action pattern:
// action → confirm popup → loading on the action button → success → reload.
import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

class DiscussionConfirmDialog {
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) async {
    final result = await AppModalShell.show<bool>(
      context: context,
      builder: (pageContext) => _ShellBody(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        onConfirm: onConfirm,
      ),
    );
    return result == true;
  }
}

/// Wraps the confirm content in the shared AppModalShell card
/// (daily-limit popup design) — the bare Column was rendering
/// without a dialog card.
class _ShellBody extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Future<void> Function() onConfirm;

  const _ShellBody({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
  });

  @override
  State<_ShellBody> createState() => _ShellBodyState();
}

class _ShellBodyState extends State<_ShellBody> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppLanguage.tr(
            'Something went wrong. Please try again.',
            'केही गलत भयो। कृपया पुन: प्रयास गर्नुहोस्।');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const danger = Color(0xFFDC2626);
    return AppModalShell(
      accent: danger,
      accentMid: const Color(0xFFEF4444),
      accentLight: const Color(0xFFFECACA),
      tagColor: danger,
      tagLabel: AppLanguage.tr('CONFIRM', 'पुष्टि गर्नुहोस्'),
      onClose: _busy ? null : () => Navigator.of(context).pop(false),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: danger,
        ),
        child: const Icon(Icons.delete_outline_rounded,
            size: 28, color: Colors.white),
      ),
      title: Text(
        widget.title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  decoration: TextDecoration.none)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFDC2626),
                    decoration: TextDecoration.none)),
          ],
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                  style:
                      const TextStyle(decoration: TextDecoration.none)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: danger,
                  foregroundColor: Colors.white),
              onPressed: _busy ? null : _confirm,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.confirmLabel,
                      style: const TextStyle(
                          decoration: TextDecoration.none)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience for destructive confirms (delete post/comment/reply).
/// Follows the standing popup-action pattern via [DiscussionConfirmDialog].
Future<bool> confirmDiscussionDelete({
  required BuildContext context,
  required String title,
  required String message,
  required Future<void> Function() onConfirm,
}) async {
  final ok = await DiscussionConfirmDialog.show(
    context: context,
    title: title,
    message: message,
    confirmLabel: AppLanguage.tr('Delete', 'मेट्नुहोस्'),
    onConfirm: onConfirm,
  );
  return ok;
}

/// Convenience for simple yes/no confirms with no async work
/// (e.g. "Open this link?") — resolves true when the user confirms.
Future<bool> confirmDiscussionAction({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
}) {
  return DiscussionConfirmDialog.show(
    context: context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    onConfirm: () async {},
  );
}
