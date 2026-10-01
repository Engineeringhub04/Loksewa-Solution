// Subscription → Your requests → one request.
//
// Mirrors app/subscription/[id].tsx. Answers three questions in order:
//   1. A STATUS CROWN stating the outcome in the status's own colour, with the
//      amount as the hero number.
//   2. A TIMELINE — "pending" means something once it sits between
//      "submitted" and "approved".
//   3. An EDIT WINDOW BAR that drains in real time (30-minute correction
//      window).
//
// Motion rule: only two things animate on a loop — the pulse on the step the
// request is sitting at, and the draining edit bar. Everything else animates
// once on entry (SyllabusEntrance) and then holds still.
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/services/subscription_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';

const int _editWindowMs = 30 * 60 * 1000;

/// Crown gradient per outcome — the page's colour is the request's colour.
const Map<SubscriptionStatus, List<Color>> _statusGradient = {
  SubscriptionStatus.pending: [Color(0xFFB45309), Color(0xFFD97706)],
  SubscriptionStatus.active: [Color(0xFF047857), Color(0xFF0D9488)],
  SubscriptionStatus.rejected: [Color(0xFFB91C1C), Color(0xFFDC2626)],
  SubscriptionStatus.expired: [Color(0xFF475569), Color(0xFF334155)],
};

const Color _onGradient = Colors.white;

class SubscriptionDetailScreen extends StatefulWidget {
  final String id;

  /// Test seam: overrides the record fetch.
  final Future<SubscriptionRecord?> Function(String id)? loader;

  /// Test seam: overrides the screenshot picker.
  final Future<Uint8List?> Function()? pickImage;

  const SubscriptionDetailScreen(
      {super.key, required this.id, this.loader, this.pickImage});

  @override
  State<SubscriptionDetailScreen> createState() =>
      _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen> {
  final _refCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  SubscriptionRecord? _record;
  bool _loading = true;
  bool _loadingError = false;
  bool _editing = false;
  bool _saving = false;

  /// The screenshot URL on the record; replaced by [_pickedBytes] when the
  /// user picks a new image in the edit form.
  String _screenshotUri = '';
  Uint8List? _pickedBytes;

  Timer? _timer;
  double _barPercent = 100;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _refCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadingError = false;
    });
    try {
      final record = widget.loader != null
          ? await widget.loader!(widget.id)
          : await SubscriptionService.fetchSubscriptionById(widget.id);
      if (!mounted) return;
      setState(() {
        _record = record;
        _loading = false;
        if (record != null && !_editing) {
          _refCtrl.text = record.transactionRef ?? '';
          _msgCtrl.text = record.customerMessage ?? '';
          _screenshotUri = record.screenshotUrl;
          _pickedBytes = null;
        }
      });
      _armTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingError = true;
      });
    }
  }

  DateTime? get _editDeadline {
    final submitted = _record?.submittedAt;
    if (submitted == null) return null;
    return submitted.add(const Duration(milliseconds: _editWindowMs));
  }

  int get _remainingMs {
    final deadline = _editDeadline;
    if (deadline == null) return 0;
    return maxInt(0, deadline.difference(DateTime.now()).inMilliseconds);
  }

  /// Mirrors the React canEdit: any non-active request still inside the
  /// 30-minute window (rejected requests are editable too).
  bool get _canEdit =>
      _record != null &&
      _record!.status != SubscriptionStatus.active &&
      _remainingMs > 0;

  // The timer stops itself the moment the window closes, so a settled
  // request costs nothing per second.
  void _armTimer() {
    _timer?.cancel();
    final deadline = _editDeadline;
    if (deadline == null || !deadline.isAfter(DateTime.now())) return;
    _barPercent = _remainingMs / _editWindowMs * 100;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _remainingMs;
      final canEdit = _record != null &&
          _record!.status != SubscriptionStatus.active &&
          remaining > 0;
      setState(() {
        _barPercent = remaining / _editWindowMs * 100;
        // Leaving edit mode open past the deadline would show a Save button
        // that can only ever fail, so the window closing closes the form.
        if (_editing && !canEdit && !_saving) {
          _editing = false;
        }
      });
      if (remaining <= 0) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  Future<void> _pickScreenshot() async {
    try {
      final bytes = widget.pickImage != null
          ? await widget.pickImage!()
          : await _pickImageFile();
      if (bytes == null || !mounted) return;
      setState(() => _pickedBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr(
              'Attach a screenshot of your payment as proof — required.',
              'प्रमाणको रूपमा आफ्नो भुक्तानीको स्क्रिनसट संलग्न गर्नुहोस् — आवश्यक।'),
          ToastVariant.warning);
    }
  }

  static Future<Uint8List?> _pickImageFile() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.bytes;
  }

  bool get _hasScreenshot =>
      _pickedBytes != null || _screenshotUri.startsWith('http');

  Future<void> _saveEdits() async {
    final record = _record;
    if (record == null || !_canEdit) {
      showToast(
          context,
          AppLanguage.tr('The 30-minute edit window has expired.',
              '३० मिनेटको सम्पादन समय समाप्त भयो।'),
          ToastVariant.warning);
      return;
    }
    if (_refCtrl.text.trim().isEmpty || !_hasScreenshot) {
      showToast(
          context,
          AppLanguage.tr(
              'Transaction ID / Reference and Payment Screenshot are required.',
              'ट्रान्जेक्सन आईडी / सन्दर्भ र भुक्तानी स्क्रिनसट आवश्यक छन्।'),
          ToastVariant.error);
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.loader != null) {
        // Test seam path: the fake loader owns persistence; mirror the
        // production update on the in-memory record instead (no upload).
        _record = _recordFromEdits(
            record, _pickedBytes != null ? 'picked-upload' : _screenshotUri);
      } else {
        var screenshotUrl = _screenshotUri;
        if (_pickedBytes != null) {
          screenshotUrl = await CloudinaryUploader.uploadImage(_pickedBytes!);
        }
        await SubscriptionService.updateMySubscriptionDetails(
          record.id,
          transactionRef: _refCtrl.text.trim(),
          screenshotUrl: screenshotUrl,
          customerMessage:
              _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr(
              'Subscription request updated.', 'सदस्यता अनुरोध अपडेट भयो।'),
          ToastVariant.success);
      setState(() {
        _editing = false;
        _pickedBytes = null;
      });
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr('Could not update your request. Please try again.',
              'अनुरोध अपडेट गर्न सकिएन। फेरि प्रयास गर्नुहोस्।'),
          ToastVariant.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SubscriptionRecord _recordFromEdits(
      SubscriptionRecord record, String screenshotUrl) {
    return SubscriptionRecord(
      id: record.id,
      uid: record.uid,
      planId: record.planId,
      planName: record.planName,
      billingCycle: record.billingCycle,
      amount: record.amount,
      currency: record.currency,
      method: record.method,
      status: record.status,
      transactionRef: _refCtrl.text.trim(),
      screenshotUrl: screenshotUrl,
      customerMessage:
          _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      adminMessage: record.adminMessage,
      submittedAt: record.submittedAt,
      reviewedAt: record.reviewedAt,
      rejectionReason: record.rejectionReason,
      startDate: record.startDate,
      expiryDate: record.expiryDate,
      couponCode: record.couponCode,
      userName: record.userName,
      userEmail: record.userEmail,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              SubpageHeader(
                  title: AppLanguage.tr('View Details', 'विवरण हेर्नुहोस्')),
              Expanded(child: _body()),
            ],
          ),
          // Saving overlay — mirrors PageLoaderOverlay.
          if (_saving)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0x66 / 0xFF),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 12),
                    Text(
                      AppLanguage.tr(
                          'Loading Subscription...', 'सदस्यता लोड हुँदैछ...'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return PreloadingWidget(
        tinted: false,
        label:
            AppLanguage.tr('Loading Subscription...', 'सदस्यता लोड हुँदैछ...'),
        hint: AppLanguage.tr(
            'Fetching your purchase history', 'खरिद इतिहास ल्याउँदै'),
      );
    }
    if (_loadingError || _record == null) {
      return _LoadError(onRetry: _refresh);
    }
    final record = _record!;
    final showEditBar = record.status != SubscriptionStatus.active &&
        record.status != SubscriptionStatus.expired;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(ExpoSpacing.screenPadding),
        children: [
          SyllabusEntrance(delayMs: 0, child: _StatusCrown(record: record)),
          if (showEditBar) ...[
            const SizedBox(height: ExpoSpacing.md),
            SyllabusEntrance(
              delayMs: 60,
              child: _EditWindowBar(
                remainingMs: _remainingMs,
                barPercent: _barPercent,
                canEdit: _canEdit,
                editing: _editing,
                saving: _saving,
                onToggle: () =>
                    _editing ? _saveEdits() : setState(() => _editing = true),
              ),
            ),
          ],
          if ((record.adminMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: ExpoSpacing.md),
            SyllabusEntrance(
              delayMs: 120,
              child: _QuotePanel(
                tone: ExpoPalette.of(context).info,
                icon: Icons.chat_bubble_outline,
                caption:
                    AppLanguage.tr('Message from Admin', 'एड्मिनको सन्देश'),
                child: Text(record.adminMessage!,
                    style: const TextStyle(fontSize: ExpoType.body)),
              ),
            ),
          ],
          if (record.status == SubscriptionStatus.rejected &&
              (record.rejectionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: ExpoSpacing.md),
            SyllabusEntrance(
              delayMs: 180,
              child: _QuotePanel(
                tone: ExpoPalette.of(context).danger,
                icon: Icons.error_outline,
                caption: AppLanguage.tr('Rejected', 'अस्वीकृत'),
                child: Text(record.rejectionReason!,
                    style: const TextStyle(fontSize: ExpoType.body)),
              ),
            ),
          ],
          const SizedBox(height: ExpoSpacing.md),
          SyllabusEntrance(
            delayMs: 240,
            child: _SectionCard(
              icon: Icons.commit_outlined,
              tone: ExpoPalette.of(context).info,
              title: AppLanguage.tr('Request Timeline', 'अनुरोधको क्रम'),
              child: _RequestTimeline(record: record),
            ),
          ),
          if (_editing) ...[
            const SizedBox(height: ExpoSpacing.md),
            SyllabusEntrance(
              delayMs: 0,
              child: _EditForm(
                refCtrl: _refCtrl,
                msgCtrl: _msgCtrl,
                pickedBytes: _pickedBytes,
                screenshotUri: _screenshotUri,
                saving: _saving,
                onPickScreenshot: _pickScreenshot,
                onPreview: _openZoom,
                onCancel:
                    _saving ? null : () => setState(() => _editing = false),
              ),
            ),
          ],
          const SizedBox(height: ExpoSpacing.md),
          SyllabusEntrance(
            delayMs: 300,
            child: _SectionCard(
              icon: Icons.receipt_long_outlined,
              tone: ExpoPalette.of(context).primary,
              title: AppLanguage.tr('Payment Summary', 'भुक्तानी विवरण'),
              child: _PaymentSummary(record: record),
            ),
          ),
          if (record.screenshotUrl.isNotEmpty) ...[
            const SizedBox(height: ExpoSpacing.md),
            SyllabusEntrance(
              delayMs: 360,
              child: _SectionCard(
                icon: Icons.image_outlined,
                tone: ExpoPalette.of(context).accent,
                title: AppLanguage.tr('Payment Receipt', 'भुक्तानी रसिद'),
                trailing: StatusPill(
                  label: AppLanguage.tr('Tap to view full screen and zoom',
                      'पूर्ण स्क्रिनमा हेर्न तथा जुम गर्न थिच्नुहोस्'),
                  color: ExpoPalette.of(context).textDisabled,
                  icon: Icons.crop_free_outlined,
                ),
                child: _ReceiptPreview(
                  url: record.screenshotUrl,
                  onTap: _openZoom,
                ),
              ),
            ),
          ],
          const SizedBox(height: ExpoSpacing.md),
          SyllabusEntrance(
            delayMs: 420,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.replace('/subscription'),
                    child: Text(AppLanguage.tr(
                        'Back to Plans', 'योजनाहरूमा फर्कनुहोस्')),
                  ),
                ),
                const SizedBox(width: ExpoSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push('/contact-us'),
                    child: Text(AppLanguage.tr(
                        'Contact Support', 'सहयोगमा सम्पर्क गर्नुहोस्')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ExpoSpacing.lg),
        ],
      ),
    );
  }

  void _openZoom() {
    // Global image viewer: pinch-to-zoom only (no +/- zoom buttons).
    final ImageProvider provider;
    if (_pickedBytes != null) {
      provider = MemoryImage(_pickedBytes!);
    } else if (_screenshotUri.startsWith('http')) {
      provider = NetworkImage(_screenshotUri);
    } else {
      return;
    }
    showImageViewer(context, provider);
  }
}

int maxInt(int a, int b) => a > b ? a : b;

// ===================== Status crown =====================

class _StatusCrown extends StatelessWidget {
  final SubscriptionRecord record;
  const _StatusCrown({required this.record});

  @override
  Widget build(BuildContext context) {
    final gradient = _statusGradient[record.status]!;
    final label = _statusTag(record.status);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0x33 / 0xFF),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(ExpoSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _onGradient.withValues(alpha: 0x33 / 0xFF),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(_statusIcon(record.status),
                          size: 22, color: _onGradient),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label.toUpperCase(),
                            style: TextStyle(
                              fontSize: ExpoType.overline,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: _onGradient.withValues(alpha: 0x99 / 0xFF),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            record.planName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: ExpoType.h3,
                              fontWeight: FontWeight.bold,
                              color: _onGradient,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ExpoSpacing.md),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(
                      'Rs. ${_money(record.amount)}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: _onGradient,
                        height: 1.1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        record.method.toUpperCase(),
                        style: TextStyle(
                          fontSize: ExpoType.bodySmall,
                          color: _onGradient.withValues(alpha: 0xDB / 0xFF),
                        ),
                      ),
                    ),
                  ],
                ),
                if (record.submittedAt != null) ...[
                  const SizedBox(height: ExpoSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _onGradient.withValues(alpha: 0x33 / 0xFF),
                        borderRadius: BorderRadius.circular(ExpoRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 12, color: _onGradient),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _fmtDateTime(record.submittedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: ExpoType.caption,
                                fontWeight: FontWeight.w600,
                                color: _onGradient,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ExpoRadius.lg),
                  border: Border.all(
                    color: _onGradient.withValues(alpha: 0x38 / 0xFF),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== Edit window =====================

/// The 30-minute correction window, drawn as a draining bar.
///
/// The bar's fill glides instead of stepping a second at a time: every tick
/// retargets a tween from the previous percent to the new one.
class _EditWindowBar extends StatefulWidget {
  final int remainingMs;
  final double barPercent;
  final bool canEdit;
  final bool editing;
  final bool saving;
  final VoidCallback onToggle;
  const _EditWindowBar({
    required this.remainingMs,
    required this.barPercent,
    required this.canEdit,
    required this.editing,
    required this.saving,
    required this.onToggle,
  });

  @override
  State<_EditWindowBar> createState() => _EditWindowBarState();
}

class _EditWindowBarState extends State<_EditWindowBar> {
  late double _from = widget.barPercent;
  late double _to = widget.barPercent;

  @override
  void didUpdateWidget(covariant _EditWindowBar old) {
    super.didUpdateWidget(old);
    if (widget.barPercent != _to) {
      _from = _to;
      _to = widget.barPercent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final tone = widget.canEdit ? pal.warning : pal.textDisabled;
    return Container(
      padding: const EdgeInsets.all(ExpoSpacing.md),
      decoration: BoxDecoration(
        color: pal.surface,
        border:
            Border.all(color: tone.withValues(alpha: 0x55 / 0xFF), width: 0.5),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0x1F / 0xFF),
                  border: Border.all(
                      color: tone.withValues(alpha: 0x33 / 0xFF), width: 0.5),
                  borderRadius: BorderRadius.circular(ExpoRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                    widget.canEdit
                        ? Icons.hourglass_empty_outlined
                        : Icons.lock_outline,
                    size: 17,
                    color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.canEdit
                          ? AppLanguage.tr('You can still edit this request',
                              'तपाईं अझै यो अनुरोध सम्पादन गर्न सक्नुहुन्छ')
                          : AppLanguage.tr(
                              'The 30-minute edit window has expired.',
                              '३० मिनेटको सम्पादन समय समाप्त भयो।'),
                      style: const TextStyle(
                          fontSize: ExpoType.bodySmall,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.canEdit
                          ? '${AppLanguage.tr('Edit time remaining', 'सम्पादन गर्न बाँकी समय')} · ${_fmtDuration(widget.remainingMs)}'
                          : AppLanguage.tr(
                              'Approve or reject premium subscription payments.',
                              'प्रिमियम सदस्यता भुक्तानी स्वीकृत वा अस्वीकृत गर्नुहोस्।'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: ExpoType.caption, color: pal.textSecondary),
                    ),
                  ],
                ),
              ),
              if (widget.canEdit)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0x1F / 0xFF),
                    border: Border.all(
                        color: tone.withValues(alpha: 0x33 / 0xFF), width: 0.5),
                    borderRadius: BorderRadius.circular(ExpoRadius.md),
                  ),
                  child: Text(
                    _fmtDuration(widget.remainingMs),
                    style: TextStyle(
                      fontSize: ExpoType.bodySmall,
                      fontWeight: FontWeight.bold,
                      color: tone,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          if (widget.canEdit) ...[
            const SizedBox(height: ExpoSpacing.sm),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: _from, end: _to),
              duration: const Duration(milliseconds: 950),
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(ExpoRadius.pill),
                child: Container(
                  height: 6,
                  color: pal.surfaceAlt,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (value.clamp(0, 100)) / 100,
                    child: Container(color: tone),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: ExpoSpacing.sm),
          ElevatedButton.icon(
            onPressed:
                (!widget.canEdit || widget.saving) ? null : widget.onToggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: pal.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  pal.textDisabled.withValues(alpha: 0x33 / 0xFF),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ExpoRadius.md),
              ),
            ),
            icon: widget.saving
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    widget.editing ? Icons.check_outlined : Icons.edit_outlined,
                    size: 17),
            label: Text(widget.editing
                ? AppLanguage.tr('Save Request', 'अनुरोध सुरक्षित गर्नुहोस्')
                : AppLanguage.tr('Edit Request', 'अनुरोध सम्पादन गर्नुहोस्')),
          ),
        ],
      ),
    );
  }
}

// ===================== Timeline =====================

enum _StepState { done, current, upcoming, failed }

class _TimelineStep {
  final String key;
  final String title;
  final DateTime? timestamp;
  final IconData icon;
  final _StepState state;
  final Color tone;
  const _TimelineStep({
    required this.key,
    required this.title,
    required this.timestamp,
    required this.icon,
    required this.state,
    required this.tone,
  });
}

List<_TimelineStep> _buildSteps(SubscriptionRecord record, ExpoPalette pal) {
  final reviewed =
      record.reviewedAt != null || record.status != SubscriptionStatus.pending;
  late final _TimelineStep finalStep;
  switch (record.status) {
    case SubscriptionStatus.active:
      finalStep = _TimelineStep(
        key: 'approved',
        title: AppLanguage.tr('Approved & activated', 'स्वीकृत तथा सक्रिय'),
        timestamp: record.startDate ?? record.reviewedAt,
        icon: Icons.check_circle_outline,
        state: _StepState.done,
        tone: pal.success,
      );
    case SubscriptionStatus.rejected:
      finalStep = _TimelineStep(
        key: 'rejected',
        title: AppLanguage.tr('Rejected by admin', 'एड्मिनद्वारा अस्वीकृत'),
        timestamp: record.reviewedAt,
        icon: Icons.cancel_outlined,
        state: _StepState.failed,
        tone: pal.danger,
      );
    case SubscriptionStatus.expired:
      finalStep = _TimelineStep(
        key: 'expired',
        title: AppLanguage.tr('Subscription expired', 'सदस्यता समाप्त भयो'),
        timestamp: record.expiryDate,
        icon: Icons.schedule_outlined,
        state: _StepState.done,
        tone: pal.textDisabled,
      );
    case SubscriptionStatus.pending:
      finalStep = _TimelineStep(
        key: 'approved',
        title: AppLanguage.tr('Approved & activated', 'स्वीकृत तथा सक्रिय'),
        timestamp: null,
        icon: Icons.check_circle_outline,
        state: _StepState.upcoming,
        tone: pal.textDisabled,
      );
  }
  return [
    _TimelineStep(
      key: 'submitted',
      title: AppLanguage.tr('Payment submitted', 'भुक्तानी पेस भयो'),
      timestamp: record.submittedAt,
      icon: Icons.send_outlined,
      state: _StepState.done,
      tone: pal.info,
    ),
    _TimelineStep(
      key: 'review',
      title: AppLanguage.tr(
          'Waiting for admin review', 'एड्मिन समीक्षाको प्रतीक्षामा'),
      timestamp: record.reviewedAt,
      icon: Icons.search_outlined,
      state: reviewed ? _StepState.done : _StepState.current,
      tone: reviewed ? pal.info : pal.warning,
    ),
    finalStep,
  ];
}

class _RequestTimeline extends StatelessWidget {
  final SubscriptionRecord record;
  const _RequestTimeline({required this.record});

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps(record, ExpoPalette.of(context));
    return Column(
      children: steps.asMap().entries.map((entry) {
        return _TimelineRow(
          step: entry.value,
          last: entry.key == steps.length - 1,
        );
      }).toList(),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final _TimelineStep step;
  final bool last;
  const _TimelineRow({required this.step, required this.last});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final dim = step.state == _StepState.upcoming;
    final node = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: dim ? pal.surfaceAlt : step.tone.withValues(alpha: 0x1F / 0xFF),
        border: Border.all(
          color: dim ? pal.border : step.tone.withValues(alpha: 0x33 / 0xFF),
          width: 0.5,
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child:
          Icon(step.icon, size: 15, color: dim ? pal.textDisabled : step.tone),
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                step.state == _StepState.current ? _Pulse(child: node) : node,
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: pal.divider,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : ExpoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      fontSize: ExpoType.body,
                      fontWeight: dim ? FontWeight.normal : FontWeight.w600,
                      color: dim ? pal.textDisabled : pal.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (step.timestamp != null)
                    Text(
                      _fmtDateTime(step.timestamp),
                      style: TextStyle(
                          fontSize: ExpoType.caption, color: pal.textSecondary),
                    )
                  else if (step.state == _StepState.current)
                    StatusPill(label: '•••', color: pal.warning),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one looping animation on the page: it marks the step the request is
/// actually sitting at.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1, end: 1.16).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

// ===================== Edit form =====================

class _EditForm extends StatelessWidget {
  final TextEditingController refCtrl;
  final TextEditingController msgCtrl;
  final Uint8List? pickedBytes;
  final String screenshotUri;
  final bool saving;
  final VoidCallback onPickScreenshot;
  final VoidCallback onPreview;
  final VoidCallback? onCancel;
  const _EditForm({
    required this.refCtrl,
    required this.msgCtrl,
    required this.pickedBytes,
    required this.screenshotUri,
    required this.saving,
    required this.onPickScreenshot,
    required this.onPreview,
    required this.onCancel,
  });

  bool get _hasPreview =>
      pickedBytes != null || screenshotUri.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final tone = pal.warning;
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
      ),
      padding: const EdgeInsets.all(ExpoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0x1F / 0xFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.edit_outlined, size: 18, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.tr(
                          'Edit Request', 'अनुरोध सम्पादन गर्नुहोस्'),
                      style: const TextStyle(
                          fontSize: ExpoType.body, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      AppLanguage.tr(
                          'Approve or reject premium subscription payments.',
                          'प्रिमियम सदस्यता भुक्तानी स्वीकृत वा अस्वीकृत गर्नुहोस्।'),
                      style: TextStyle(
                          fontSize: ExpoType.caption, color: pal.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ExpoSpacing.md),
          TextField(
            controller: refCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: AppLanguage.tr(
                  'Transaction ID / Reference', 'ट्रान्जेक्सन आईडी / सन्दर्भ'),
              helperText: AppLanguage.tr(
                  'Enter the transaction ID or remarks shown after your payment.',
                  'तपाईंको भुक्तानी पछि देखिएको ट्रान्जेक्सन आईडी वा रिमार्क्स प्रविष्ट गर्नुहोस्।'),
              hintText:
                  AppLanguage.tr('e.g. TXN123456789', 'जस्तै TXN123456789'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: ExpoSpacing.md),
          Text(
            AppLanguage.tr('Payment Screenshot', 'भुक्तानी स्क्रिनसट'),
            style: const TextStyle(
                fontSize: ExpoType.bodySmall, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            AppLanguage.tr(
                'Attach a screenshot of your payment as proof — required.',
                'प्रमाणको रूपमा आफ्नो भुक्तानीको स्क्रिनसट संलग्न गर्नुहोस् — आवश्यक।'),
            style:
                TextStyle(fontSize: ExpoType.caption, color: pal.textSecondary),
          ),
          if (_hasPreview) ...[
            const SizedBox(height: ExpoSpacing.xs),
            GestureDetector(
              onTap: onPreview,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ExpoRadius.md),
                child: pickedBytes != null
                    ? Image.memory(pickedBytes!,
                        height: 200, width: double.infinity, fit: BoxFit.cover)
                    : Image.network(screenshotUri,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            color: pal.surfaceAlt,
                            alignment: Alignment.center,
                            child: Icon(Icons.broken_image_outlined,
                                color: pal.textDisabled))),
              ),
            ),
          ],
          const SizedBox(height: ExpoSpacing.xs),
          OutlinedButton.icon(
            onPressed: onPickScreenshot,
            icon: const Icon(Icons.image_outlined, size: 17),
            label: Text(_hasPreview
                ? AppLanguage.tr('Edit', 'सम्पादन गर्नुहोस्')
                : AppLanguage.tr('Payment Screenshot', 'भुक्तानी स्क्रिनसट')),
          ),
          const SizedBox(height: ExpoSpacing.md),
          TextField(
            controller: msgCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText:
                  AppLanguage.tr('Message (optional)', 'सन्देश (वैकल्पिक)'),
              hintText: AppLanguage.tr(
                  'Add a note for the admin, e.g. paid from a family member\'s account',
                  'एड्मिनको लागि नोट थप्नुहोस्, जस्तै परिवारको सदस्यको खाताबाट तिरेको'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: ExpoSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: saving ? null : onCancel,
              child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== Payment summary =====================

class _PaymentSummary extends StatelessWidget {
  final SubscriptionRecord record;
  const _PaymentSummary({required this.record});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Column(
      children: [
        _InfoRow(
          icon: Icons.diamond_outlined,
          label: AppLanguage.tr('Plan', 'योजना'),
          value: Text(record.planName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        _InfoRow(
          icon: Icons.payments_outlined,
          label: AppLanguage.tr('Amount', 'रकम'),
          tone: pal.success,
          value: Text('Rs. ${_money(record.amount)}',
              style:
                  TextStyle(fontWeight: FontWeight.w600, color: pal.success)),
        ),
        _InfoRow(
          icon: Icons.credit_card_outlined,
          label: AppLanguage.tr('Payment Method', 'भुक्तानी विधि'),
          value: Text(record.method.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        _InfoRow(
          icon: Icons.qr_code_outlined,
          label: AppLanguage.tr('Reference', 'सन्दर्भ'),
          value: Text(record.transactionRef ?? '—',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          last: record.couponCode == null && record.customerMessage == null,
        ),
        if (record.couponCode != null)
          _InfoRow(
            icon: Icons.local_offer_outlined,
            label:
                AppLanguage.tr('Coupon Code (optional)', 'कुपन कोड (वैकल्पिक)'),
            value: StatusPill(
              label: record.couponCode!,
              color: pal.accent,
              icon: Icons.local_offer,
            ),
            last: record.customerMessage == null,
          ),
        if (record.customerMessage != null)
          _InfoRow(
            icon: Icons.chat_bubble_outline,
            label: AppLanguage.tr('Message (optional)', 'सन्देश (वैकल्पिक)'),
            stacked: true,
            last: true,
            value: Text(record.customerMessage!),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;
  final Color? tone;
  final bool stacked;
  final bool last;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
    this.stacked = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final iconColor = tone ?? pal.textSecondary;
    final content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: ExpoType.caption, color: pal.textSecondary)),
              const SizedBox(height: 4),
              value,
            ],
          )
        : Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: ExpoType.bodySmall,
                        color: pal.textSecondary)),
              ),
              Flexible(
                child: DefaultTextStyle(
                  style: TextStyle(
                      fontSize: ExpoType.bodySmall, color: pal.textPrimary),
                  textAlign: TextAlign.end,
                  child: value,
                ),
              ),
            ],
          );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: last ? Colors.transparent : pal.divider,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(child: content),
        ],
      ),
    );
  }
}

// ===================== Receipt =====================

class _ReceiptPreview extends StatelessWidget {
  final String url;
  final VoidCallback onTap;
  const _ReceiptPreview({required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(ExpoRadius.md),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: pal.border, width: 0.5),
                borderRadius: BorderRadius.circular(ExpoRadius.md),
              ),
              child: Image.network(
                url,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: pal.surfaceAlt,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_outlined,
                        color: pal.textDisabled)),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0x99 / 0xFF),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child:
                  const Icon(Icons.open_in_full, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== Shared bits =====================

/// Tinted quote panel with a tone spine. Mirrors QuotePanel.
class _QuotePanel extends StatelessWidget {
  final Color tone;
  final IconData icon;
  final String? caption;
  final Widget child;
  const _QuotePanel({
    required this.tone,
    required this.icon,
    this.caption,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0x14 / 0xFF),
        border:
            Border.all(color: tone.withValues(alpha: 0x33 / 0xFF), width: 0.5),
        borderRadius: BorderRadius.circular(ExpoRadius.md),
      ),
      // Clip the spine to the card's curve: the spine's square inner
      // corners would otherwise poke ~2px past the rounded corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ExpoRadius.md),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(ExpoRadius.md),
                    bottomLeft: Radius.circular(ExpoRadius.md),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(ExpoSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 15, color: tone),
                          if (caption != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              caption!,
                              style: TextStyle(
                                fontSize: ExpoType.caption,
                                fontWeight: FontWeight.bold,
                                color: tone,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      child,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium section card: tone-tinted icon box + title (+ optional trailing)
/// over a bordered surface. Mirrors SectionCard.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String title;
  final Widget? trailing;
  final Widget child;
  const _SectionCard({
    required this.icon,
    required this.tone,
    required this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
      ),
      padding: const EdgeInsets.all(ExpoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0x1F / 0xFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: ExpoType.body, fontWeight: FontWeight.bold),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: ExpoSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ExpoSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: pal.textDisabled),
            const SizedBox(height: ExpoSpacing.sm),
            Text(
              AppLanguage.tr(
                  'Could not load this request.', 'यो अनुरोध लोड गर्न सकिएन।'),
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textSecondary),
            ),
            const SizedBox(height: ExpoSpacing.md),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(AppLanguage.tr('Try again', 'पुनः प्रयास गर्नुहोस्')),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusTag(SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.active:
      return AppLanguage.tr('Approved', 'स्वीकृत');
    case SubscriptionStatus.rejected:
      return AppLanguage.tr('Rejected', 'अस्वीकृत');
    case SubscriptionStatus.expired:
      return AppLanguage.tr('Expired', 'म्याद सकिएको');
    case SubscriptionStatus.pending:
      return AppLanguage.tr('New', 'नयाँ');
  }
}

IconData _statusIcon(SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.active:
      return Icons.check_circle_outline;
    case SubscriptionStatus.rejected:
      return Icons.cancel_outlined;
    case SubscriptionStatus.expired:
      return Icons.schedule_outlined;
    case SubscriptionStatus.pending:
      return Icons.auto_awesome_outlined;
  }
}

String _money(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

const List<String> _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

String _fmtDate(DateTime? dt) {
  if (dt == null) return '—';
  final d = dt.toLocal();
  return '${d.day.toString().padLeft(2, '0')} ${_monthShort[d.month - 1]} ${d.year}';
}

String _fmtDateTime(DateTime? dt) {
  if (dt == null) return '—';
  final d = dt.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${_fmtDate(d)}, $hh:$mm';
}

String _fmtDuration(int milliseconds) {
  final totalSeconds = maxInt(0, milliseconds ~/ 1000);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
