// Content purchase request detail.
// Mirrors app/purchase-details/content/[id].tsx: same pattern as the exam
// purchase detail (status box, 30-minute edit window, admin message, details
// card, screenshot preview) with content-specific fields (content title,
// content type, course/subcourse ids) and a language-aware title.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
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
import 'package:loksewa_solution/services/exam_service.dart';

class ContentPurchaseDetailScreen extends StatefulWidget {
  final String id;
  final String? source;
  const ContentPurchaseDetailScreen(
      {super.key, required this.id, this.source});

  @override
  State<ContentPurchaseDetailScreen> createState() =>
      _ContentPurchaseDetailScreenState();
}

class _ContentPurchaseDetailScreenState
    extends State<ContentPurchaseDetailScreen> {
  ContentPurchaseRecord? _record;
  bool _loading = true;
  Object? _error;
  String _title = 'Subject Purchase';

  final _refCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String? _screenshotUrl;
  Uint8List? _screenshotBytes;
  bool _editing = false;
  bool _saving = false;
  // Problem 7: original values snapshotted when edit mode is entered — the
  // Save button stays disabled until the form actually differs from them.
  String _origRef = '';
  String _origMsg = '';
  String? _origScreenshotUrl;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  Timer? _ticker;
  // Best-effort display names for the "Subject - Unit - Chapter" title.
  String? _subjectName;
  String? _unitName;
  // The item's own resolved name (when the stored contentTitle is a raw ID).
  String? _ownName;

  String _t(String en, String ne) => AppLanguage.tr(en, ne);

  @override
  void initState() {
    super.initState();
    // Problem 7: re-evaluate the Save button's enabled state on every
    // keystroke while editing.
    _refCtrl.addListener(_onEditFieldChanged);
    _msgCtrl.addListener(_onEditFieldChanged);
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_record?.submittedAt != null) {
        setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
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

  String _contentTitle(ContentPurchaseRecord r) {
    if (AppLanguage.isNepali && r.contentTitleNe.isNotEmpty) {
      return r.contentTitleNe;
    }
    return r.contentTitle;
  }

  /// "Subject - Chapter" / "Subject - Unit - Chapter" display title.
  /// Subject/unit names are enriched best-effort in _load; falls back to the
  /// item's own title when the names can't be resolved — never a raw doc ID.
  String _displayTitle(ContentPurchaseRecord r) {
    var own = _contentTitle(r);
    if ((_ownName ?? '').isNotEmpty) own = _ownName!;
    if (r.contentType == 'subject') {
      if (own.isEmpty) return _t('Subject', 'विषय');
      return _looksLikeDocId(own) ? _cleanIdName(own) : own;
    }
    final parts = <String>[];
    if ((_subjectName ?? '').isNotEmpty) parts.add(_subjectName!);
    if (r.contentType == 'chapter' && (_unitName ?? '').isNotEmpty) {
      parts.add(_unitName!);
    }
    if (own.isNotEmpty) {
      parts.add(_looksLikeDocId(own) ? _cleanIdName(own) : own);
    } else {
      parts.add(_t('Subject Purchase', 'विषय खरिद'));
    }
    return parts.join(' - ');
  }

  /// Best-effort: resolve subject/unit/chapter display names for the title.
  /// Reads the REAL production fields: the subject detail collections use
  /// `name`/`nameNe` (NOT `title` — that was the raw-doc-ID bug). Also
  /// resolves the item's own name from its detail doc when the stored
  /// contentTitle is itself a raw doc ID (older gateway purchases).
  /// Fail-soft — falls back to a cleaned human-readable name, never a raw ID.
  Future<void> _enrichNames(ContentPurchaseRecord record) async {
    var changed = false;

    /// Language-aware name pick from a detail doc.
    String? docName(Map<String, dynamic>? doc) {
      if (doc == null) return null;
      final ne = doc['nameNe']?.toString().trim();
      final en = doc['name']?.toString().trim();
      final t = doc['title']?.toString().trim();
      String? pick;
      if (AppLanguage.isNepali) {
        pick = (ne != null && ne.isNotEmpty) ? ne : en;
      } else {
        pick = (en != null && en.isNotEmpty) ? en : ne;
      }
      if (pick == null || pick.isEmpty) pick = t;
      return (pick != null && pick.isNotEmpty) ? pick : null;
    }

    /// Detail-doc path for the purchased item itself.
    String? itemDocPath() {
      final id = record.contentId;
      if (id.isEmpty) return null;
      switch (record.contentType) {
        case 'subject':
          return 'app_subjects_details/$id';
        case 'unit':
          return 'app_subjects_units_details/$id';
        case 'chapter':
        default:
          return (record.unitId ?? '').isNotEmpty
              ? 'app_subjects_unit-chapters_details/$id'
              : 'app_subjects_chapter_details/$id';
      }
    }

    try {
      // Subject name (for chapter/unit items).
      if (record.contentType != 'subject' && record.subjectId.isNotEmpty) {
        final doc =
            await ExamRest.getDoc('app_subjects_details/${record.subjectId}');
        final name = docName(doc);
        if (name != null) {
          _subjectName = name;
          changed = true;
        }
      }
      // Unit name (for chapters inside a unit).
      if (record.contentType == 'chapter' &&
          (record.unitId ?? '').isNotEmpty) {
        final doc = await ExamRest.getDoc(
            'app_subjects_units_details/${record.unitId}');
        final name = docName(doc);
        if (name != null) {
          _unitName = name;
          changed = true;
        }
      }
      // The item's own name — only when the stored title is a raw doc ID.
      final own = _contentTitle(record);
      if (_looksLikeDocId(own)) {
        final path = itemDocPath();
        if (path != null) {
          final doc = await ExamRest.getDoc(path);
          final name = docName(doc);
          if (name != null) {
            _ownName = name;
            changed = true;
          }
        }
      }
    } catch (_) {}
    if (changed && mounted) {
      setState(() => _title = _displayTitle(record));
    }
  }

  /// A raw Firestore doc ID (segments joined by __) — never show these.
  bool _looksLikeDocId(String s) => s.contains('__');

  /// Fail-soft: turn a raw doc ID into something human-readable.
  String _cleanIdName(String s) {
    if (!_looksLikeDocId(s)) return s;
    final last = s.split('__').lastWhere((p) => p.isNotEmpty, orElse: () => '');
    return last.replaceAll('-', ' ').replaceAll('_', ' ').trim();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await fetchContentPurchaseById(widget.id);
      if (!mounted) return;
      final title = record != null ? _contentTitle(record) : '';
      setState(() {
        _record = record;
        _loading = false;
        _title = title.isNotEmpty
            ? title
            : _t('Subject Purchase', 'विषय खरिद');
        _subjectName = null;
        _unitName = null;
        _ownName = null;
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
      if (record != null) _enrichNames(record);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _handleBack() {
    // React: source === 'content' | 'chapter' replaces onto the subjects page.
    if (widget.source == 'content' || widget.source == 'chapter') {
      context.go('/subjects');
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
    if (record == null || !isContentPurchaseEditable(record, _nowMs)) {
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
      final screenshotUrl = _screenshotBytes != null
          ? await CloudinaryUploader.uploadImage(_screenshotBytes!)
          : _screenshotUrl ?? '';
      await updateMyContentPurchaseDetails(
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
                // Single loading state: the body shows PreloadingWidget while
                // loading; this overlay is ONLY for the in-flight save.
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
        label: _t('Loading Subject Purchase...', 'विषय खरिद लोड हुँदैछ...'),
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
    final canEdit = !isGateway && isContentPurchaseEditable(record, _nowMs);
    final remainingLabel =
        _formatDuration(contentPurchaseEditRemainingMs(record, _nowMs));
    final itemName = _displayTitle(record);

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
            title: itemName,
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
                record: _ContentProblemRecord(record),
                purchaseType: 'content',
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
                  icon: Icons.book_outlined,
                  label: _t('Item', 'वस्तु'),
                  value: Text(itemName,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                ),
                RequestInfoRow(
                  icon: Icons.layers_outlined,
                  label: _t('Type', 'प्रकार'),
                  value: Text(_typeLabel(record.contentType),
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

  String _typeLabel(String contentType) {
    switch (contentType) {
      case 'subject':
        return _t('Subject', 'विषय');
      case 'unit':
        return _t('Unit', 'युनिट');
      case 'chapter':
      default:
        return _t('Chapter', 'अध्याय');
    }
  }
}

class _ContentProblemRecord implements PaymentProblemRecord {
  final ContentPurchaseRecord record;
  _ContentProblemRecord(this.record);

  @override
  String get method => record.method;

  @override
  String get transactionRef => record.transactionRef ?? '';

  @override
  String? get failureReason => record.failureReason;

  @override
  bool get isFraud => record.isFraud;

  @override
  String get successTitle => record.contentTitle;
}
