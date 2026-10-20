// Exam purchase request detail.
// Mirrors app/subscription/exam-purchase/[id].tsx: a status box (status tag
// + live 30-minute edit countdown + rejection reason), the admin-message box,
// the edit-request flow (transaction ref / screenshot picker uploaded to
// Cloudinary / message) gated on the 30-minute edit window, a details card,
// and the receipt screenshot preview.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/exam_purchases.dart';
import 'package:loksewa_solution/services/purchase_refresh.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/request_timeline.dart';
import '../../widgets/payment_problem_section.dart';
import '../../widgets/request_crown.dart';
import '../../widgets/request_section_card.dart';
import '../../widgets/request_info_row.dart';
import '../../widgets/verification_pending_banner.dart';

class SubscriptionExamPurchaseScreen extends StatefulWidget {
  final String id;
  final String? source;
  const SubscriptionExamPurchaseScreen(
      {super.key, required this.id, this.source});

  @override
  State<SubscriptionExamPurchaseScreen> createState() =>
      _SubscriptionExamPurchaseScreenState();
}

class _SubscriptionExamPurchaseScreenState
    extends State<SubscriptionExamPurchaseScreen> {
  ExamPurchaseRecord? _record;
  bool _loading = true;
  Object? _error;
  String _title = 'Exam Purchase';

  final _refCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String? _screenshotUrl; // remote URL from the record
  Uint8List? _screenshotBytes; // newly picked, not yet uploaded
  bool _editing = false;
  bool _saving = false;
  // Problem 7: original values snapshotted when edit mode is entered — the
  // Save button stays disabled until the form actually differs from them.
  String _origRef = '';
  String _origMsg = '';
  String? _origScreenshotUrl;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  Timer? _ticker;
  // Pending-status live poll (same pattern as subscription_detail_screen):
  // while the record is still pending, re-read the doc every 5 seconds so
  // an admin approval or a verification lands without a manual refresh.
  Timer? _liveTimer;
  static const _liveInterval = Duration(seconds: 5);

  String _t(String en, String ne) => AppLanguage.tr(en, ne);

  @override
  void initState() {
    super.initState();
    // Problem 7: re-evaluate the Save button's enabled state on every
    // keystroke while editing.
    _refCtrl.addListener(_onEditFieldChanged);
    _msgCtrl.addListener(_onEditFieldChanged);
    _load();
    // React ticks `now` every second so the remaining edit time counts down
    // live on screen.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_record?.submittedAt != null) {
        setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
      }
    });
    _startLiveUpdates();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _liveTimer?.cancel();
    _refCtrl.removeListener(_onEditFieldChanged);
    _msgCtrl.removeListener(_onEditFieldChanged);
    _refCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  /// True once the edit form differs from the values it opened with.
  bool get _editDirty {
    if (!_editing) return false;
    if (_refCtrl.text.trim() != _origRef) return true;
    if (_msgCtrl.text.trim() != _origMsg) return true;
    if (_screenshotBytes != null) return true;
    if ((_screenshotUrl ?? '') != (_origScreenshotUrl ?? '')) return true;
    return false;
  }

  void _onEditFieldChanged() {
    if (_editing && mounted) setState(() {});
  }

  /// Enter edit mode, snapshotting the current values for the dirty check.
  void _enterEdit() {
    _origRef = _refCtrl.text.trim();
    _origMsg = _msgCtrl.text.trim();
    _origScreenshotUrl = _screenshotUrl;
    setState(() => _editing = true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await fetchExamPurchaseById(widget.id);
      if (!mounted) return;
      setState(() {
        _record = record;
        _loading = false;
        _title = (record != null && record.examTitle.isNotEmpty)
            ? record.examTitle
            : _t('Exam Details', 'परीक्षा विवरण');
        if (!_editing) {
          _refCtrl.text = record?.transactionRef ?? '';
          _msgCtrl.text = record?.customerMessage ?? '';
          _screenshotUrl =
              (record?.screenshotUrl.isNotEmpty ?? false)
                  ? record!.screenshotUrl
                  : null;
          _screenshotBytes = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _startLiveUpdates() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(_liveInterval, (_) => _pollRecord());
  }

  /// One quiet re-read of the doc. Never shows the loading spinner and
  /// never touches the edit form — it only swaps the record when something
  /// actually changed. Skipped while the user is editing or saving, so a
  /// background change can't clobber the form mid-edit (the post-save
  /// _load picks it up instead). The poll stops once the status leaves
  /// 'pending' — after that nothing can change anymore.
  Future<void> _pollRecord() async {
    if (!mounted || _editing || _saving) return;
    final cur = _record;
    if (cur == null) {
      // Initial load still in flight (or failed) — leave the timer alone.
      return;
    }
    if (cur.status != 'pending') {
      _liveTimer?.cancel();
      return;
    }
    try {
      final record = await fetchExamPurchaseById(widget.id);
      if (!mounted || record == null) return;
      if (_sameRecord(_record, record)) return;
      final flipped = record.status != 'pending';
      setState(() {
        _record = record;
        if (record.status != 'pending') {
          _title = record.examTitle.isNotEmpty
              ? record.examTitle
              : _t('Exam Details', 'परीक्षा विवरण');
        }
        if (!_editing) {
          _refCtrl.text = record.transactionRef ?? '';
          _msgCtrl.text = record.customerMessage ?? '';
          _screenshotUrl =
              record.screenshotUrl.isNotEmpty ? record.screenshotUrl : null;
          _screenshotBytes = null;
        }
      });
      if (flipped) {
        // Status left pending (admin approval / verification) — tell the
        // exam tab and subject pages to re-read their data, no manual
        // refresh, and stop watching this record.
        PurchaseRefreshBus.bump();
        _liveTimer?.cancel();
      }
    } catch (_) {
      // Transient network error — the next tick retries; never break the
      // screen over a background refresh.
    }
  }

  /// Field-by-field comparison of everything this screen renders.
  bool _sameRecord(ExamPurchaseRecord? a, ExamPurchaseRecord b) {
    if (a == null) return false;
    return a.status == b.status &&
        a.gatewayStatus == b.gatewayStatus &&
        a.failureReason == b.failureReason &&
        a.transactionRef == b.transactionRef &&
        a.screenshotUrl == b.screenshotUrl &&
        a.customerMessage == b.customerMessage &&
        a.adminMessage == b.adminMessage &&
        a.rejectionReason == b.rejectionReason &&
        a.reviewedAt == b.reviewedAt &&
        a.verifiedBy == b.verifiedBy &&
        a.platform == b.platform &&
        a.amount == b.amount &&
        a.examTitle == b.examTitle;
  }

  void _handleBack() {
    // React: source === 'exam' replaces onto the exam tab.
    if (widget.source == 'exam') {
      context.go('/exam');
    } else {
      context.pop();
    }
  }

  Future<void> _pickScreenshot() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      try {
        bytes = await File(picked.path!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null) {
      if (!mounted) return;
      showToast(
          context,
          _t('Attach a screenshot of your payment as proof — required.',
              'प्रमाणको रूपमा आफ्नो भुक्तानीको स्क्रिनसट संलग्न गर्नुहोस् — आवश्यक।'),
          ToastVariant.warning);
      return;
    }
    setState(() => _screenshotBytes = bytes);
  }

  Future<void> _save() async {
    final record = _record;
    if (record == null || !isExamPurchaseEditable(record, _nowMs)) {
      showToast(
          context,
          _t('The 30-minute edit window has expired.',
              '३० मिनेटको सम्पादन समय समाप्त भयो।'),
          ToastVariant.warning);
      return;
    }
    final ref = _refCtrl.text.trim();
    final hasScreenshot =
        _screenshotBytes != null || (_screenshotUrl?.isNotEmpty ?? false);
    if (ref.isEmpty || !hasScreenshot) {
      showToast(
          context,
          _t(
              'Transaction ID / Reference and Payment Screenshot are required.',
              'ट्रान्जेक्सन आईडी / सन्दर्भ र भुक्तानी स्क्रिनसट आवश्यक छ।'),
          ToastVariant.error);
      return;
    }
    setState(() => _saving = true);
    try {
      // React: keep the existing http(s) URL, upload only a newly picked file.
      final screenshotUrl = _screenshotBytes != null
          ? await CloudinaryUploader.uploadImage(_screenshotBytes!)
          : _screenshotUrl ?? '';
      await updateMyExamPurchaseDetails(
        record.id,
        transactionRef: ref,
        screenshotUrl: screenshotUrl,
        customerMessage:
            _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      );
      if (!mounted) return;
      showToast(
          context,
          _t('Subscription request updated.', 'सदस्यता अनुरोध अपडेट भयो।'),
          ToastVariant.success);
      setState(() {
        _editing = false;
        _saving = false;
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      showToast(
          context,
          _t('Could not update your request. Please try again.',
              'अनुरोध अपडेट गर्न सकिएन। फेरि प्रयास गर्नुहोस्।'),
          ToastVariant.error);
      setState(() => _saving = false);
    }
  }

  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 1 << 31);
    final m = totalSeconds ~/ 60;
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: _title, onBackPress: _handleBack),
          Expanded(
            child: Stack(
              children: [
                _buildBody(palette),
                // React's PageLoaderOverlay while the save is in flight.
                if (_saving)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                                color: Colors.white),
                            const SizedBox(height: 12),
                            Text(
                              _t('Saving...', 'सेभ हुँदैछ...'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
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
    );
  }

  Widget _buildBody(ExpoPalette palette) {
    if (_loading) {
      return PreloadingWidget(
        tinted: false,
        label: _t('Loading Exam Purchase...', 'परीक्षा खरिद लोड हुँदैछ...'),
        hint: _t('Fetching your purchase details',
            'तपाईंको खरिद विवरण ल्याउँदैछ'),
      );
    }
    if (_error != null || _record == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _t('Could not load this purchase.',
                    'यो खरिद लोड गर्न सकिएन।'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child:
                    Text(_t('Retry', 'पुनः प्रयास गर्नुहोस्')),
              ),
            ],
          ),
        ),
      );
    }
    final record = _record!;
    final status = record.status;
    final isGateway = record.isGateway;
    // Edit features exist ONLY for manual-QR purchases: a worker-verified
    // gateway payment must never be editable (user requirement).
    final canEdit = !isGateway && isExamPurchaseEditable(record, _nowMs);
    final remainingLabel =
        _formatDuration(examPurchaseEditRemainingMs(record, _nowMs));
    final examName = record.examTitle.isNotEmpty
        ? record.examTitle
        : _t('Exam Details', 'परीक्षा विवरण');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Payment crown — status-driven colors, the same card as the
          // subscription request page.
          RequestCrown(
            status: status,
            isFraud: record.isFraud,
            gatewayInitiated: isGateway &&
                status == 'pending' &&
                (record.gatewayStatus ?? '') == 'initiated',
            title: examName,
            amount: record.amount,
            method: record.method,
            submittedAt: record.submittedAtDate,
          ),

          // Pending verification message — gateway recovery only.
          if (isGateway &&
              status == 'pending' &&
              record.needsPaymentRecovery) ...[
            const SizedBox(height: 12),
            const VerificationPendingBanner(),
          ],

          // Edit request — manual QR only, never for gateway payments.
          if (!isGateway && status == 'pending') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                // Problem 7: Save stays disabled until the form actually
                // differs from the values it opened with.
                onPressed: !canEdit
                    ? null
                    : _editing
                        ? ((_editDirty && !_saving) ? _save : null)
                        : _enterEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(
                        _editing
                            ? Icons.check_outlined
                            : Icons.edit_outlined,
                        size: 17,
                        color: Colors.white),
                label: Text(_editing
                    ? _t('Save Request', 'अनुरोध सुरक्षित गर्नुहोस्')
                    : _t('Edit Request', 'अनुरोध सम्पादन गर्नुहोस्')),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              canEdit
                  ? '${_t('Edit time remaining', 'सम्पादन गर्न बाँकी समय')}: $remainingLabel'
                  : _t('The 30-minute edit window has expired.',
                      '३० मिनेटको सम्पादन समय समाप्त भयो।'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ExpoType.caption,
                color: palette.textSecondary,
              ),
            ),
          ],

          // Admin message.
          if (record.adminMessage != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.primary
                    .withValues(alpha: 0x14 / 0xFF),
                border: Border.all(color: palette.primary),
                borderRadius: BorderRadius.circular(ExpoRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 18, color: palette.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _t('Message from Admin', 'एड्मिनको सन्देश'),
                          style: TextStyle(
                            fontSize: ExpoType.bodySmall,
                            fontWeight: FontWeight.bold,
                            color: palette.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(record.adminMessage!,
                      style: const TextStyle(fontSize: ExpoType.body)),
                ],
              ),
            ),

          // Rejection reason.
          if (status == 'rejected' &&
              (record.rejectionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    palette.danger.withValues(alpha: 0x14 / 0xFF),
                border: Border.all(color: palette.danger),
                borderRadius: BorderRadius.circular(ExpoRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: palette.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _t('Rejected', 'अस्वीकृत'),
                          style: TextStyle(
                            fontSize: ExpoType.bodySmall,
                            fontWeight: FontWeight.bold,
                            color: palette.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(record.rejectionReason!,
                      style: const TextStyle(fontSize: ExpoType.body)),
                ],
              ),
            ),
          ],

          // Request timeline — same component and step logic as the
          // subscription request page, for gateway AND manual purchases.
          const SizedBox(height: 12),
          RequestSectionCard(
            icon: Icons.commit_outlined,
            tone: palette.info,
            title: _t('Request Timeline', 'अनुरोधको क्रम'),
            child: RequestTimeline(
              steps: isGateway
                  ? buildGatewayRequestSteps(
                      pal: palette,
                      submittedAt: record.submittedAtDate,
                      gatewayStatus: record.gatewayStatus ?? '',
                      status: record.status,
                      verifiedBy: record.verifiedBy,
                      reviewedAt: record.reviewedAt == null
                          ? null
                          : DateTime.tryParse(record.reviewedAt!),
                      isStaleInitiated: record.isStaleInitiated,
                    )
                  : buildManualRequestSteps(
                      pal: palette,
                      submittedAt: record.submittedAtDate,
                      status: record.status,
                      reviewedAt: record.reviewedAt == null
                          ? null
                          : DateTime.tryParse(record.reviewedAt!),
                    ),
            ),
          ),

          // Edit box.
          if (_editing) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                border: Border.all(
                    color: palette.border, width: 0.5),
                borderRadius: BorderRadius.circular(ExpoRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _refCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: _t('Transaction ID / Reference',
                          'ट्रान्जेक्सन आईडी / सन्दर्भ'),
                      hintText:
                          _t('e.g. TXN123456789', 'जस्तै TXN123456789'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _t('Payment Screenshot', 'भुक्तानी स्क्रिनसट'),
                    style: TextStyle(
                      fontSize: ExpoType.bodySmall,
                      fontWeight: FontWeight.w500,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_screenshotBytes != null)
                    GestureDetector(
                      onTap: () => showImageViewer(
                          context, MemoryImage(_screenshotBytes!)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_screenshotBytes!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover),
                      ),
                    )
                  else if (_screenshotUrl != null)
                    GestureDetector(
                      onTap: () => showImageViewer(
                          context, NetworkImage(_screenshotUrl!)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(_screenshotUrl!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                height: 120,
                                color: Colors.black12,
                                child: const Center(
                                    child: Icon(Icons.broken_image)))),
                      ),
                    ),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: _pickScreenshot,
                    child: Text(_t(
                        'Payment Screenshot', 'भुक्तानी स्क्रिनसट')),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _msgCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: _t(
                          'Message (optional)', 'सन्देश (वैकल्पिक)'),
                      hintText: _t(
                          "Add a note for the admin, e.g. paid from a family member's account",
                          'एड्मिनको लागि नोट थप्नुहोस्, जस्तै परिवारको सदस्यको खाताबाट तिरेको'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _editing = false),
                    child: Text(
                        _t('Cancel', 'रद्द गर्नुहोस्')),
                  ),
                ],
              ),
            ),
          ],

          // Payment problem — Check My Payment re-verifies via the worker.
          if (record.needsPaymentRecovery || record.isFraud) ...[
            const SizedBox(height: 12),
            RequestSectionCard(
              icon: Icons.error_outline,
              tone: palette.danger,
              title: _t('Payment Problem', 'भुक्तानी समस्या'),
              child: PaymentProblemSection(
                record: _ExamProblemRecord(record),
                purchaseType: 'exam',
                onRechecked: _load,
              ),
            ),
          ],

          // Payment summary — subscription-style card.
          const SizedBox(height: 12),
          RequestSectionCard(
            icon: Icons.receipt_long_outlined,
            tone: palette.primary,
            title: _t('Payment Summary', 'भुक्तानी विवरण'),
            child: Column(
              children: [
                RequestInfoRow(
                  icon: Icons.description_outlined,
                  label: _t('Exam', 'परीक्षा'),
                  value: Text(examName,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                ),
                RequestInfoRow(
                  icon: Icons.payments_outlined,
                  label: _t('Amount', 'रकम'),
                  tone: palette.success,
                  value: Text('Rs. ${requestMoney(record.amount)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: palette.success)),
                ),
                RequestInfoRow(
                  icon: Icons.credit_card_outlined,
                  label: _t('Payment Method', 'भुक्तानी विधि'),
                  value: Text(record.method.toUpperCase(),
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                ),
                RequestInfoRow(
                  icon: Icons.smartphone_outlined,
                  label: _t('Platform', 'प्लेटफर्म'),
                  value: Text(
                      requestPlatformLabel(
                          record.platform, record.method),
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                ),
                RequestInfoRow(
                  icon: record.isGateway
                      ? Icons.link_outlined
                      : Icons.qr_code_outlined,
                  label: _t('Reference', 'सन्दर्भ'),
                  value: Text(
                      (record.transactionRef ?? '').isNotEmpty
                          ? record.transactionRef!
                          : '—',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  last: record.customerMessage == null,
                ),
                if (record.customerMessage != null)
                  RequestInfoRow(
                    icon: Icons.chat_bubble_outline,
                    label: _t('Message (optional)', 'सन्देश (वैकल्पिक)'),
                    stacked: true,
                    last: true,
                    value: Text(record.customerMessage!),
                  ),
              ],
            ),
          ),

          // Receipt screenshot preview.
          if (record.screenshotUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _t('Payment Screenshot', 'भुक्तानी स्क्रिनसट'),
              style: TextStyle(
                fontSize: ExpoType.bodySmall,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => showImageViewer(
                  context, NetworkImage(record.screenshotUrl)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(record.screenshotUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: Colors.black12,
                        child: const Center(
                            child: Icon(Icons.broken_image)))),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Adapter: exposes an ExamPurchaseRecord through the shared
/// PaymentProblemSection's record interface.
class _ExamProblemRecord implements PaymentProblemRecord {
  final ExamPurchaseRecord record;
  _ExamProblemRecord(this.record);

  @override
  String get method => record.method;

  @override
  String get transactionRef => record.transactionRef ?? '';

  @override
  String? get failureReason => record.failureReason;

  @override
  bool get isFraud => record.isFraud;

  @override
  String get successTitle => record.examTitle;
}
