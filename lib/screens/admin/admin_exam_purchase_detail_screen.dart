import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/admin_notify_service.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
import 'admin_review_dialogs.dart' show showAdminDecisionConfirmDialog;

/// Admin → review one exam purchase request. Mirrors
/// app/admin/exam-purchases/[id].tsx. Approve tags it active; reject tags it
/// rejected with a reason. Collection: app_exam_purchases. The record is
/// never deleted — it stays in the admin list as an audit trail.
class AdminExamPurchaseDetailScreen extends StatefulWidget {
  final String id;
  const AdminExamPurchaseDetailScreen({super.key, required this.id});

  @override
  State<AdminExamPurchaseDetailScreen> createState() =>
      _AdminExamPurchaseDetailScreenState();
}

class _Denied implements Exception {}

class _AdminExamPurchaseDetailScreenState
    extends State<AdminExamPurchaseDetailScreen> {
  Future<Map<String, dynamic>?>? _future;
  // Latest loaded record (cached in _load so _save can ping the buyer
  // without an extra read or an async gap before using context).
  Map<String, dynamic>? _record;
  final _adminMessage = TextEditingController();
  final _customReason = TextEditingController();
  String? _decision; // 'reject' | 'approve' | 'other'

  @override
  void initState() {
    super.initState();
    _adminMessage.addListener(_onInputChanged);
    _customReason.addListener(_onInputChanged);
    _future = _load();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _adminMessage.dispose();
    _customReason.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _load() async {
    final user = AuthService.currentUser;
    if (user == null) throw _Denied();
    final token = await AuthService.getValidIdToken();
    final profile =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
    if (profile?['isAdmin'] != true) throw _Denied();
    final record = await FirestoreRest.getDocument(
        'app_exam_purchases/${widget.id}',
        idToken: token);
    if (record == null) return null;
    // Best-effort user profile for the photo/name.
    try {
      final uid = record['uid'];
      if (uid is String && uid.isNotEmpty) {
        record['_profile'] =
            await FirestoreRest.getDocument('users/$uid', idToken: token);
      }
    } catch (_) {}
    _record = record;
    return record;
  }

  void _refresh() => setState(() => _future = _load());

  /// Save is enabled only when every required field is filled: a decision
  /// picked, the message to the user, and the custom reason when "Other"
  /// is the decision.
  bool get _canSave {
    if (_decision == null) return false;
    if (_adminMessage.text.trim().isEmpty) return false;
    if (_decision == 'other' && _customReason.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  /// ONE Save button → AppModalShell confirm popup → the popup's Save button
  /// shows loading while the write runs → success reloads the page. The
  /// Firestore writes are IDENTICAL to the old approve/reject pair:
  /// app_exam_purchases, status 'active'/'rejected', rejectionReason, the
  /// default 'Payment could not be verified.' reason.
  Future<void> _save() async {
    final decision = _decision;
    if (decision == null || !_canSave) return;
    final reviewer = AuthService.currentUser;
    if (reviewer == null) return;
    final message = _adminMessage.text.trim();
    final customReason = _customReason.text.trim();

    final palette = ExpoPalette.of(context);
    final isApprove = decision == 'approve';
    final accent = isApprove
        ? palette.success
        : decision == 'other'
            ? palette.warning
            : palette.danger;
    final decisionWord = isApprove
        ? AppLanguage.tr('Approve', 'स्वीकृत')
        : decision == 'other'
            ? customReason
            : AppLanguage.tr('Reject', 'अस्वीकार');
    final titleText = isApprove
        ? AppLanguage.tr('Approve exam purchase', 'परीक्षा खरिद स्वीकृत गर्नुहोस्')
        : decision == 'other'
            ? AppLanguage.tr(
                'Reject with custom reason', 'आफ्नै कारणसहित अस्वीकार गर्नुहोस्')
            : AppLanguage.tr('Reject exam purchase', 'परीक्षा खरिद अस्वीकार गर्नुहोस्');
    final questionText = isApprove
        ? AppLanguage.tr(
            'Approve this exam purchase? The user gets access, and your message will be shown to them.',
            'यो परीक्षा खरिद स्वीकृत गर्ने हो? प्रयोगकर्ताले पहुँच पाउनेछ र तपाईंको सन्देश देखाइनेछ।')
        : decision == 'other'
            ? AppLanguage.tr(
                'Reject this exam purchase with your custom reason? It and your message will be shown to the user.',
                'यो परीक्षा खरिद तपाईंको आफ्नै कारणसहित अस्वीकार गर्ने हो? त्यो कारण र तपाईंको सन्देश प्रयोगकर्तालाई देखाइनेछ।')
            : AppLanguage.tr(
                'Reject this exam purchase? The reason "Payment could not be verified." and your message will be shown to the user.',
                'यो परीक्षा खरिद अस्वीकार गर्ने हो? "Payment could not be verified." भन्ने कारण र तपाईंको सन्देश प्रयोगकर्तालाई देखाइनेछ।');

    final ok = await showAdminDecisionConfirmDialog(
      context,
      titleText: titleText,
      questionText: questionText,
      summary: [
        (
          AppLanguage.tr('Decision', 'निर्णय'),
          decisionWord,
        ),
        (
          AppLanguage.tr('Message to user', 'प्रयोगकर्तालाई सन्देश'),
          message,
        ),
      ],
      confirmText: AppLanguage.tr('Save', 'सेभ गर्नुहोस्'),
      accent: accent,
      accentMid: Color.lerp(accent, Colors.white, 0.45) ?? accent,
      accentLight: Color.lerp(accent, Colors.white, 0.8) ?? accent,
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: accent,
        ),
        child: Icon(
            isApprove ? Icons.check_circle : Icons.cancel,
            size: 28,
            color: Colors.white),
      ),
      onConfirm: () async {
        final token = await AuthService.getValidIdToken();
        await FirestoreRest.updateDocument(
          'app_exam_purchases/${widget.id}',
          {
            'status': isApprove ? 'active' : 'rejected',
            'reviewedAt': DateTime.now().toIso8601String(),
            'reviewedBy': reviewer.uid,
            'adminMessage': message,
            'rejectionReason': isApprove
                ? null
                : decision == 'other'
                    ? customReason
                    : 'Payment could not be verified.',
            'updatedAt': FirestoreRest.serverTimestamp(),
          },
          idToken: token,
        );
      },
    );
    if (!mounted) return;
    if (ok == true) {
      // Fire-and-forget push to the BUYER's devices — the decision is
      // already saved; never blocks the admin UI.
      final rec = _record;
      final buyerUid = rec?['uid']?.toString() ?? '';
      if (buyerUid.isNotEmpty) {
        final examTitle = (rec!['examTitle'] ?? '').toString();
        final reason = isApprove
            ? ''
            : (decision == 'other'
                ? customReason
                : 'Payment could not be verified.');
        unawaited(AdminNotifyService.notifyUser(
          uid: buyerUid,
          title: isApprove ? 'खरिद स्वीकृत ✅' : 'खरिद अस्वीकृत ❌',
          body: isApprove
              ? 'तपाईंको खरिद "$examTitle" स्वीकृत भयो। अब तपाईंले सामग्री प्रयोग गर्न सक्नुहुन्छ।'
              : 'तपाईंको खरिद "$examTitle" अस्वीकृत भयो। कारण: $reason',
          deepLink: '/subscription/exam-purchase/${widget.id}',
        ));
      }
      showToast(
          context,
          isApprove
              ? AppLanguage.tr(
                  'Subscription approved.', 'सदस्यता स्वीकृत भयो।')
              : AppLanguage.tr(
                  'Subscription rejected.', 'सदस्यता अस्वीकृत भयो।'),
          ToastVariant.success);
      _refresh();
    } else if (ok == false) {
      showToast(
          context,
          AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
          ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Exam Details', 'परीक्षा विवरण')),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr(
                        'Loading Subscription...', 'सदस्यता लोड हुँदैछ...'),
                    hint: AppLanguage.tr('Fetching your purchase history',
                        'खरिद इतिहास ल्याउँदै'),
                  );
                }
                if (snap.hasError) {
                  if (snap.error is _Denied) {
                    return Center(
                        child: Text(AppLanguage.tr(
                            'Access denied', 'पहुँच अस्वीकृत')));
                  }
                  return Center(
                    child: ElevatedButton(
                        onPressed: _refresh,
                        child:
                            Text(AppLanguage.tr('Retry', 'पुनः प्रयास'))),
                  );
                }
                final record = snap.data;
                if (record == null) {
                  return Center(
                      child: Text(AppLanguage.tr(
                          'This purchase request was not found.',
                          'यो खरिद अनुरोध भेटिएन।')));
                }
                return _body(record);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Map<String, dynamic> record) {
    final status = '${record['status'] ?? 'pending'}';
    final Color color = status == 'active'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : Colors.orange;
    final label = status == 'active'
        ? AppLanguage.tr('Approved', 'स्वीकृत')
        : status == 'rejected'
            ? AppLanguage.tr('Rejected', 'अस्वीकृत')
            : AppLanguage.tr('New', 'नयाँ');
    final icon = status == 'active'
        ? Icons.check_circle
        : status == 'rejected'
            ? Icons.cancel
            : Icons.schedule;
    final profile = record['_profile'] as Map<String, dynamic>?;
    final screenshotUrl = (record['screenshotUrl'] as String?) ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SyllabusEntrance(
          delayMs: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(width: 8),
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                if (record['adminMessage'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${record['adminMessage']}',
                        style: TextStyle(color: color, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SyllabusEntrance(
          delayMs: 60,
          child: Card(
            child: ListTile(
              leading: (profile?['photoURL'] as String?)?.isNotEmpty == true
                  ? CircleAvatar(
                      backgroundImage:
                          NetworkImage(profile!['photoURL'] as String))
                  : const CircleAvatar(child: Icon(Icons.person)),
              title: Text('${profile?['name'] ?? record['userName'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${profile?['email'] ?? record['userEmail'] ?? '—'}'),
                  Text(
                    '${record['courseName'] ?? '—'} · ${record['subcourseName'] ?? '—'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              isThreeLine: true,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SyllabusEntrance(delayMs: 120, child: _reviewCard()),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _row(AppLanguage.tr('Exam Details', 'परीक्षा विवरण'),
                  '${record['examTitle'] ?? '—'}'),
              _row(AppLanguage.tr('User', 'प्रयोगकर्ता'),
                  '${record['userName'] ?? '—'}'),
              _row(AppLanguage.tr('Email', 'इमेल'),
                  '${record['userEmail'] ?? '—'}'),
              _row(AppLanguage.tr('Course', 'कोर्स'),
                  '${record['courseName'] ?? '—'}'),
              _row(AppLanguage.tr('Subcourse', 'सबकोर्स'),
                  '${record['subcourseName'] ?? '—'}'),
              _row(AppLanguage.tr('Amount', 'रकम'),
                  'Rs. ${record['amount'] ?? '—'}'),
              _row(AppLanguage.tr('Reference', 'सन्दर्भ'),
                  '${record['transactionRef'] ?? '—'}'),
              if (record['customerMessage'] != null)
                _row(AppLanguage.tr('Message (optional)', 'सन्देश (वैकल्पिक)'),
                    '${record['customerMessage']}'),
              if (record['rejectionReason'] != null)
                _row(AppLanguage.tr('Reject reason', 'अस्वीकारको कारण'),
                    '${record['rejectionReason']}'),
            ],
          ),
        ),
        if (screenshotUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _fullscreen(screenshotUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(screenshotUrl,
                  height: 230, width: double.infinity, fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text(
                AppLanguage.tr('Tap to view full screen and zoom',
                    'Full screen मा हेर्न र zoom गर्न थिच्नुहोस्'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  /// Review decision card: the Reject / Approve / Other segmented toggle
  /// sits just above the (now required) message field; "Other" reveals a
  /// free-text reason input. ONE Save button, enabled only when every
  /// required field is filled.
  Widget _reviewCard() {
    final palette = ExpoPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              Icons.how_to_vote_outlined,
              AppLanguage.tr('Review decision', 'समीक्षा निर्णय')),
          const SizedBox(height: 12),
          _requiredLabel(AppLanguage.tr('Decision', 'निर्णय')),
          const SizedBox(height: 8),
          _decisionToggle(),
          if (_decision == 'other') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customReason,
              style:
                  TextStyle(color: palette.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: palette.surfaceAlt,
                labelText: _requiredLabelText(AppLanguage.tr(
                    'Custom reason', 'आफ्नै कारण')),
                hintText: AppLanguage.tr(
                    'e.g. Duplicate, Fake', 'जस्तै Duplicate, Fake'),
                hintStyle: TextStyle(
                    color: palette.textDisabled, fontSize: 13),
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: palette.info, width: 1.5)),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _requiredLabel(
              AppLanguage.tr('Message to user', 'प्रयोगकर्तालाई सन्देश')),
          const SizedBox(height: 8),
          TextField(
            controller: _adminMessage,
            maxLines: 3,
            minLines: 3,
            style:
                TextStyle(color: palette.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: palette.surfaceAlt,
              hintText: AppLanguage.tr(
                  'e.g. Thanks! Your payment matched perfectly.',
                  'जस्तै धन्यवाद! तपाईंको भुक्तानी सही मिल्यो।'),
              hintStyle: TextStyle(
                  color: palette.textDisabled, fontSize: 13),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: palette.info, width: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.tr(
                'Shown back to the user alongside the approval/rejection.',
                'स्वीकृति/अस्वीकृतिसँगै प्रयोगकर्तालाई देखाइनेछ।'),
            style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
                height: 1.4),
          ),
          const SizedBox(height: 14),
          _saveButton(),
        ],
      ),
    );
  }

  Widget _requiredLabel(String text) {
    return Text.rich(
      TextSpan(
        text: text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ExpoPalette.of(context).textSecondary),
        children: const [
          TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
        ],
      ),
    );
  }

  String _requiredLabelText(String text) => '$text *';

  Widget _sectionHeader(IconData icon, String title) {
    final palette = ExpoPalette.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.info.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: palette.info),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary)),
        ),
      ],
    );
  }

  Widget _decisionToggle() {
    final palette = ExpoPalette.of(context);
    final items = [
      (
        'reject',
        AppLanguage.tr('Reject', 'अस्वीकार'),
        palette.danger,
      ),
      (
        'approve',
        AppLanguage.tr('Approve', 'स्वीकृत'),
        palette.success,
      ),
      (
        'other',
        AppLanguage.tr('Other', 'अन्य'),
        palette.warning,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final item in items) Expanded(child: _decisionSegment(item)),
        ],
      ),
    );
  }

  Widget _decisionSegment((String, String, Color) item) {
    final selected = _decision == item.$1;
    final palette = ExpoPalette.of(context);
    return GestureDetector(
      onTap: () => setState(() => _decision = item.$1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? item.$3 : Colors.transparent,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: item.$3.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          item.$2,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white : palette.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _saveButton() {
    final palette = ExpoPalette.of(context);
    final decision = _decision;
    final canSave = _canSave;
    final tone = decision == 'approve'
        ? palette.success
        : decision == null
            ? palette.textDisabled
            : palette.danger;
    final deep = Color.lerp(tone, Colors.black, 0.18) ?? tone;
    return Opacity(
      opacity: canSave ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: canSave
                ? LinearGradient(
                    colors: [tone, deep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: canSave ? null : palette.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            boxShadow: canSave
                ? [
                    BoxShadow(
                      color: tone.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: canSave ? _save : null,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save_outlined,
                      color: canSave ? Colors.white : palette.textDisabled,
                      size: 20),
                  const SizedBox(width: 8),
                  Text(
                    AppLanguage.tr('Save', 'सेभ गर्नुहोस्'),
                    style: TextStyle(
                        color: canSave
                            ? Colors.white
                            : palette.textDisabled,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(ExpoRadius.lg),
      border: Border.all(color: palette.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 105,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.grey))),
          Expanded(
              child: Text(value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _fullscreen(String url) {
    showImageViewer(context, NetworkImage(url));
  }
}
