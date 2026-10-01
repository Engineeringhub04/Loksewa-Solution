import 'package:flutter/material.dart';

import '../../services/app_language.dart';
import '../../widgets/app_modal_shell.dart';

/// Content title in the app's current language — mirrors
/// `language === 'ne' ? record.contentTitleNe || record.contentTitle : record.contentTitle`.
String adminContentTitle(Map<String, dynamic> record) {
  final en = '${record['contentTitle'] ?? ''}';
  final ne = '${record['contentTitleNe'] ?? ''}';
  if (AppLanguage.isNepali) return ne.isNotEmpty ? ne : en;
  return en;
}

/// Shared admin review dialogs — the global AppModalShell modal used by the
/// subscription / exam-purchase / content-purchase review screens. Mirrors
/// ConfirmDialog + RejectReasonDialog from the Expo admin desk.
///
/// [showAdminReviewApproveDialog] pops `true` on Approve, `false`/null on
/// Cancel or X. [showAdminReviewRejectDialog] pops the trimmed rejection
/// reason on Reject, null on Cancel or X.
Future<bool> showAdminReviewApproveDialog(
  BuildContext context, {
  required String approveMessage,
}) async {
  final ok = await AppModalShell.show<bool>(
    context: context,
    builder: (c) => AppModalShell(
      maxWidth: 360,
      tagLabel: AppLanguage.tr('Review', 'समीक्षा'),
      accent: const Color(0xFF16A34A),
      accentMid: const Color(0xFF4ADE80),
      accentLight: const Color(0xFFBBF7D0),
      tagColor: const Color(0xFF16A34A),
      onClose: () => Navigator.of(c).pop(false),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF16A34A),
        ),
        child:
            const Icon(Icons.check_circle, size: 28, color: Colors.white),
      ),
      title: Text(
        AppLanguage.tr('Approve', 'स्वीकृत गर्नुहोस्'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Text(
        approveMessage,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF475569),
          height: 1.5,
          decoration: TextDecoration.none,
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(c).pop(false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child:
                  Text(AppLanguage.tr('Approve', 'स्वीकृत गर्नुहोस्')),
            ),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

Future<String?> showAdminReviewRejectDialog(BuildContext context) {
  final reason = TextEditingController();
  return AppModalShell.show<String>(
    context: context,
    builder: (c) => AppModalShell(
      maxWidth: 360,
      tagLabel: AppLanguage.tr('Review', 'समीक्षा'),
      accent: const Color(0xFFDC2626),
      accentMid: const Color(0xFFF87171),
      accentLight: const Color(0xFFFECACA),
      tagColor: const Color(0xFFDC2626),
      onClose: () => Navigator.of(c).pop(),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFFDC2626),
        ),
        child: const Icon(Icons.cancel, size: 28, color: Colors.white),
      ),
      title: Text(
        AppLanguage.tr('Reject Subscription', 'सदस्यता अस्वीकार गर्नुहोस्'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Material(
        type: MaterialType.transparency,
        child: TextField(
          controller: reason,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: AppLanguage.tr(
                'Reason for rejection (shown to the user)',
                'असवीकारको कारण (प्रयोगकर्तालाई देखाइनेछ)'),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(c).pop(),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(c).pop(reason.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child:
                  Text(AppLanguage.tr('Reject', 'अस्वीकार गर्नुहोस्')),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Decision confirm popup for the purchase-request review flow (Reject /
/// Approve / Other): an AppModalShell whose footer Save button flips into a
/// loading spinner while [onConfirm] runs the Firestore write — the global
/// popup-action pattern (confirm → loading on the popup's action button →
/// success → caller reloads).
///
/// Pops `true` when the write succeeded, `false` when it threw (caller shows
/// the error toast), null on Cancel / X / barrier tap.
Future<bool?> showAdminDecisionConfirmDialog(
  BuildContext context, {
  required String titleText,
  required String questionText,
  required List<(String, String)> summary,
  required String confirmText,
  required Color accent,
  required Color accentMid,
  required Color accentLight,
  required Widget icon,
  required Future<void> Function() onConfirm,
}) {
  var settled = false;
  return AppModalShell.show<bool?>(
    context: context,
    builder: (c) => _DecisionConfirmBody(
      titleText: titleText,
      questionText: questionText,
      summary: summary,
      confirmText: confirmText,
      accent: accent,
      accentMid: accentMid,
      accentLight: accentLight,
      icon: icon,
      onClose: () {
        if (!settled) Navigator.of(c).pop(null);
      },
      onConfirm: () async {
        settled = true;
        try {
          await onConfirm();
          if (c.mounted) Navigator.of(c).pop(true);
        } catch (_) {
          if (c.mounted) Navigator.of(c).pop(false);
        }
      },
    ),
  );
}

class _DecisionConfirmBody extends StatefulWidget {
  final String titleText;
  final String questionText;
  final List<(String, String)> summary;
  final String confirmText;
  final Color accent;
  final Color accentMid;
  final Color accentLight;
  final Widget icon;
  final VoidCallback onClose;
  final Future<void> Function() onConfirm;

  const _DecisionConfirmBody({
    required this.titleText,
    required this.questionText,
    required this.summary,
    required this.confirmText,
    required this.accent,
    required this.accentMid,
    required this.accentLight,
    required this.icon,
    required this.onClose,
    required this.onConfirm,
  });

  @override
  State<_DecisionConfirmBody> createState() => _DecisionConfirmBodyState();
}

class _DecisionConfirmBodyState extends State<_DecisionConfirmBody> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.onConfirm();
    // onConfirm always pops (true/false); this state is only still mounted
    // if something unexpected happened.
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      maxWidth: 360,
      tagLabel: AppLanguage.tr('Review', 'समीक्षा'),
      accent: widget.accent,
      accentMid: widget.accentMid,
      accentLight: widget.accentLight,
      tagColor: widget.accent,
      onClose: widget.onClose,
      icon: widget.icon,
      title: Text(
        widget.titleText,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.questionText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
              height: 1.5,
              decoration: TextDecoration.none,
            ),
          ),
          for (final row in widget.summary) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.$1,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.4,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      height: 1.4,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : widget.onClose,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(widget.confirmText),
            ),
          ),
        ],
      ),
    );
  }
}
