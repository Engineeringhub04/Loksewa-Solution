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
