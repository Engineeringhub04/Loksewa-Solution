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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/request_timeline.dart';
import '../../widgets/request_info_row.dart';
import '../../widgets/request_section_card.dart';
import '../../widgets/payment_problem_section.dart';

const int _editWindowMs = 30 * 60 * 1000;

/// Crown gradient per outcome — the page's colour is the request's colour.
const Map<SubscriptionStatus, List<Color>> _statusGradient = {
  SubscriptionStatus.pending: [Color(0xFFB45309), Color(0xFFD97706)],
  SubscriptionStatus.active: [Color(0xFF047857), Color(0xFF0D9488)],
  SubscriptionStatus.rejected: [Color(0xFFB91C1C), Color(0xFFDC2626)],
  SubscriptionStatus.expired: [Color(0xFF475569), Color(0xFF334155)],
  SubscriptionStatus.cancelled: [Color(0xFF475569), Color(0xFF334155)],
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

  /// Whether the loaded record is the user's currently-active
  /// subscription. Resolved best-effort in [_refresh] (falls back to
  /// treating an active record as current when the history can't load,
  /// e.g. in widget tests).
  bool _isCurrentActive = false;

  /// The screenshot URL on the record; replaced by [_pickedBytes] when the
  /// user picks a new image in the edit form.
  String _screenshotUri = '';
  Uint8List? _pickedBytes;

  /// Problem 7: original values snapshotted when edit mode is entered — the
  /// Save button stays disabled until the form actually differs from them.
  String _origRef = '';
  String _origMsg = '';
  String _origScreenshotUri = '';

  Timer? _timer;
  double _barPercent = 100;

  /// Live-update ticker: re-reads the subscription doc every few seconds
  /// while this screen is open, so an admin approve / reject / expire
  /// reflects instantly with no manual refresh. The app talks to Firestore
  /// over hand-rolled REST (no cloud_firestore snapshots stream), so this
  /// short-interval poll is the realtime mechanism — one small doc read
  /// per tick, cancelled the moment the screen closes.
  Timer? _liveTimer;
  static const _liveInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    // Problem 7: re-evaluate the Save button's enabled state on every
    // keystroke while editing.
    _refCtrl.addListener(_onEditFieldChanged);
    _msgCtrl.addListener(_onEditFieldChanged);
    _refresh();
    _startLiveUpdates();
  }

  /// True once the edit form differs from the values it opened with.
  bool get _editDirty {
    if (!_editing) return false;
    if (_refCtrl.text.trim() != _origRef) return true;
    if (_msgCtrl.text.trim() != _origMsg) return true;
    if (_pickedBytes != null) return true;
    if (_screenshotUri != _origScreenshotUri) return true;
    return false;
  }

  void _onEditFieldChanged() {
    if (_editing && mounted) setState(() {});
  }

  /// Enter edit mode, snapshotting the current values for the dirty check.
  void _enterEdit() {
    _origRef = _refCtrl.text.trim();
    _origMsg = _msgCtrl.text.trim();
    _origScreenshotUri = _screenshotUri;
    setState(() => _editing = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _liveTimer?.cancel();
    _refCtrl.removeListener(_onEditFieldChanged);
    _msgCtrl.removeListener(_onEditFieldChanged);
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
      _resolveCurrentActive(record);
      _armTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingError = true;
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
  /// _refresh picks it up instead).
  Future<void> _pollRecord() async {
    if (!mounted || _editing || _saving) return;
    try {
      final record = widget.loader != null
          ? await widget.loader!(widget.id)
          : await SubscriptionService.fetchSubscriptionById(widget.id);
      if (!mounted || record == null) return;
      if (_sameRecord(_record, record)) return;
      setState(() {
        _record = record;
        _refCtrl.text = record.transactionRef ?? '';
        _msgCtrl.text = record.customerMessage ?? '';
        _screenshotUri = record.screenshotUrl;
        _pickedBytes = null;
      });
      _resolveCurrentActive(record);
      _armTimer();
    } catch (_) {
      // Transient network error — the next tick retries; never break the
      // screen over a background refresh.
    }
  }

  /// Field-by-field comparison of everything this screen renders.
  /// SubscriptionRecord has no operator==, so compare explicitly.
  bool _sameRecord(SubscriptionRecord? a, SubscriptionRecord b) {
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
        a.startDate == b.startDate &&
        a.expiryDate == b.expiryDate &&
        a.verifiedBy == b.verifiedBy &&
        a.platform == b.platform &&
        a.expiredReason == b.expiredReason &&
        a.amount == b.amount &&
        a.planName == b.planName;
  }

  /// Best-effort: determines whether the loaded record is the user's
  /// currently-active subscription (for the "Approved and Currently
  /// Active" label). Falls back to treating an active record as current
  /// when the history can't be loaded.
  Future<void> _resolveCurrentActive(SubscriptionRecord? record) async {
    final isActive = record?.status == SubscriptionStatus.active;
    if (record == null) {
      if (mounted) setState(() => _isCurrentActive = false);
      return;
    }
    try {
      final history =
          await SubscriptionService.fetchMySubscriptionHistory(record.uid);
      final current = SubscriptionService.currentActiveRecord(history);
      if (!mounted) return;
      setState(() => _isCurrentActive =
          current != null ? current.id == record.id : isActive);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCurrentActive = isActive);
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
  /// Gateway (eSewa/Khalti) payments are NEVER editable — editing a
  /// completed gateway payment is meaningless.
  bool get _canEdit =>
      _record != null &&
      !_record!.isGateway &&
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
          !_record!.isGateway &&
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
      gatewayStatus: record.gatewayStatus,
      failureReason: record.failureReason,
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
    // Gateway payments never show the edit bar — editing a completed
    // gateway payment is meaningless (user requirement).
    final showEditBar = !record.isGateway &&
        record.status != SubscriptionStatus.active &&
        record.status != SubscriptionStatus.expired;
    return RefreshIndicator.adaptive(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(ExpoSpacing.screenPadding),
        children: [
          SyllabusEntrance(
              delayMs: 0,
              child: _StatusCrown(record: record, isCurrent: _isCurrentActive)),
          if (record.isGateway &&
              record.status == SubscriptionStatus.pending &&
              record.needsPaymentRecovery) ...[
            const SizedBox(height: ExpoSpacing.md),
            SyllabusEntrance(
              delayMs: 40,
              child: _VerificationPendingBanner(),
            ),
          ],
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
                // Problem 7: Save stays disabled until the form differs from
                // the values it opened with.
                dirty: _editDirty,
                onToggle: () =>
                    _editing ? _saveEdits() : _enterEdit(),
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
            child: RequestSectionCard(
              icon: Icons.commit_outlined,
              tone: ExpoPalette.of(context).info,
              title: AppLanguage.tr('Request Timeline', 'अनुरोधको क्रम'),
              child: RequestTimeline(
                  steps: _buildSteps(record, ExpoPalette.of(context))),
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
          // Payment Problem section: for EVERY initiated gateway payment
          // (money may have arrived, status unknown) — offers
          // "Check My Payment" immediately, with no 15-minute wait.
          // Fraud cases keep their admin-only message (no button).
          // Definitive failures (payment_not_completed) get a plain
          // "no money was charged" notice — no button.
          if (record.needsPaymentRecovery || record.isFraud) ...[
            const SizedBox(height: ExpoSpacing.md),
            SyllabusEntrance(
              delayMs: 280,
              child: RequestSectionCard(
                icon: Icons.error_outline,
                tone: ExpoPalette.of(context).danger,
                title: AppLanguage.tr('Payment Problem', 'भुक्तानी समस्या'),
                child: PaymentProblemSection(
                  record: _SubscriptionProblemRecord(record),
                  purchaseType: 'subscription',
                  onRechecked: _refresh,
                ),
              ),
            ),
          ],
          if (record.hasDefinitiveFailure) ...[
            const SizedBox(height: ExpoSpacing.md),
            SyllabusEntrance(
              delayMs: 280,
              child: RequestSectionCard(
                icon: Icons.info_outline,
                tone: ExpoPalette.of(context).info,
                title: AppLanguage.tr('Payment Not Completed',
                    'भुक्तानी पूरा भएन'),
                child: Text(
                  AppLanguage.tr(
                    'The payment was not completed at the gateway. No amount was charged.',
                    'गेटवैमा भुक्तानी पूरा भएन। कुनै रकम काटिएन।',
                  ),
                  style: TextStyle(
                      fontSize: ExpoType.bodySmall,
                      color: ExpoPalette.of(context).textPrimary,
                      height: 1.5,
                      decoration: TextDecoration.none),
                ),
              ),
            ),
          ],
          const SizedBox(height: ExpoSpacing.md),
          SyllabusEntrance(
            delayMs: 300,
            child: RequestSectionCard(
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
              child: RequestSectionCard(
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

  /// Whether this record is the user's currently-active subscription.
  final bool isCurrent;

  const _StatusCrown({required this.record, this.isCurrent = false});

  @override
  Widget build(BuildContext context) {
    final gradient = _statusGradient[record.status]!;
    final label = _statusTag(record, isCurrent: isCurrent);
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
  final bool dirty;
  final VoidCallback onToggle;
  const _EditWindowBar({
    required this.remainingMs,
    required this.barPercent,
    required this.canEdit,
    required this.editing,
    required this.saving,
    required this.dirty,
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
            onPressed: (!widget.canEdit ||
                    widget.saving ||
                    (widget.editing && !widget.dirty))
                ? null
                : widget.onToggle,
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
// (Shared widgets live in lib/widgets/request_timeline.dart — same visual
// language on the exam/content request pages.)

List<RequestTimelineStep> _buildSteps(SubscriptionRecord record, ExpoPalette pal) {
  if (record.isGateway) return _buildGatewaySteps(record, pal);
  final reviewed =
      record.reviewedAt != null || record.status != SubscriptionStatus.pending;
  late final RequestTimelineStep finalStep;
  switch (record.status) {
    case SubscriptionStatus.active:
      finalStep = RequestTimelineStep(
        key: 'approved',
        title: AppLanguage.tr('Approved & activated', 'स्वीकृत तथा सक्रिय'),
        timestamp: record.startDate ?? record.reviewedAt,
        icon: Icons.check_circle_outline,
        state: RequestStepState.done,
        tone: pal.success,
      );
    case SubscriptionStatus.rejected:
      finalStep = RequestTimelineStep(
        key: 'rejected',
        title: AppLanguage.tr('Rejected by admin', 'एड्मिनद्वारा अस्वीकृत'),
        timestamp: record.reviewedAt,
        icon: Icons.cancel_outlined,
        state: RequestStepState.failed,
        tone: pal.danger,
      );
    case SubscriptionStatus.expired:
      finalStep = RequestTimelineStep(
        key: 'expired',
        title: AppLanguage.tr('Subscription expired', 'सदस्यता समाप्त भयो'),
        timestamp: record.expiryDate,
        icon: Icons.schedule_outlined,
        state: RequestStepState.done,
        tone: pal.textDisabled,
      );
    case SubscriptionStatus.pending:
      finalStep = RequestTimelineStep(
        key: 'approved',
        title: AppLanguage.tr('Approved & activated', 'स्वीकृत तथा सक्रिय'),
        timestamp: null,
        icon: Icons.check_circle_outline,
        state: RequestStepState.upcoming,
        tone: pal.textDisabled,
      );
    case SubscriptionStatus.cancelled:
      finalStep = RequestTimelineStep(
        key: 'cancelled',
        title: AppLanguage.tr('Cancelled', 'रद्द गरिएको'),
        timestamp: null,
        icon: Icons.cancel_outlined,
        state: RequestStepState.upcoming,
        tone: pal.textDisabled,
      );
  }
  return [
    RequestTimelineStep(
      key: 'submitted',
      title: AppLanguage.tr('Payment submitted', 'भुक्तानी पेस भयो'),
      timestamp: record.submittedAt,
      icon: Icons.send_outlined,
      state: RequestStepState.done,
      tone: pal.info,
    ),
    RequestTimelineStep(
      key: 'review',
      title: AppLanguage.tr(
          'Waiting for admin review', 'एड्मिन समीक्षाको प्रतीक्षामा'),
      timestamp: record.reviewedAt,
      icon: Icons.search_outlined,
      state: reviewed ? RequestStepState.done : RequestStepState.current,
      tone: reviewed ? pal.info : pal.warning,
    ),
    finalStep,
  ];
}

/// Gateway (eSewa/Khalti) timeline — no admin review step; the worker
/// verifies server-side.
List<RequestTimelineStep> _buildGatewaySteps(
    SubscriptionRecord record, ExpoPalette pal) {
  final submitted = RequestTimelineStep(
    key: 'submitted',
    title: AppLanguage.tr('Payment submitted', 'भुक्तानी पेस भयो'),
    timestamp: record.submittedAt,
    icon: Icons.send_outlined,
    state: RequestStepState.done,
    tone: pal.info,
  );
  final verified = record.gatewayStatus == 'verified' ||
      record.status == SubscriptionStatus.active;
  if (verified) {
    // v1.0.110: who verified is recorded in `verifiedBy` ('gateway' |
    // 'user' | 'admin'). A manual step is inserted so the user (and the
    // admin panel) can tell HOW this payment was verified.
    final verifiedBy = (record.verifiedBy ?? 'gateway').toLowerCase();
    final steps = <RequestTimelineStep>[
      submitted,
      RequestTimelineStep(
        key: 'verification',
        title: AppLanguage.tr('Payment Verification', 'भुक्तानी प्रमाणीकरण'),
        timestamp: record.reviewedAt,
        icon: Icons.verified_outlined,
        state: RequestStepState.done,
        tone: pal.info,
      ),
    ];
    if (verifiedBy == 'user') {
      steps.add(RequestTimelineStep(
        key: 'manual_verification',
        title: AppLanguage.tr(
            'Manual Verification By User', 'प्रयोगकर्ताद्वारा म्यानुअल प्रमाणीकरण'),
        timestamp: record.reviewedAt,
        icon: Icons.touch_app_outlined,
        state: RequestStepState.done,
        tone: pal.info,
      ));
    } else if (verifiedBy == 'admin') {
      steps.add(RequestTimelineStep(
        key: 'admin_review',
        title: AppLanguage.tr(
            'Waiting for admin review', 'एड्मिन समीक्षाको प्रतीक्षामा'),
        timestamp: record.reviewedAt,
        icon: Icons.search_outlined,
        state: RequestStepState.done,
        tone: pal.info,
      ));
    }
    steps.add(RequestTimelineStep(
      key: 'activated',
      title: AppLanguage.tr('Verified & Activated', 'प्रमाणित तथा सक्रिय'),
      timestamp: record.startDate ?? record.reviewedAt,
      icon: Icons.check_circle_outline,
      state: RequestStepState.done,
      tone: pal.success,
    ));
    return steps;
  }
  if (record.gatewayStatus == 'cancelled') {
    return [
      submitted,
      RequestTimelineStep(
        key: 'verification',
        title: AppLanguage.tr('Payment Verification', 'भुक्तानी प्रमाणीकरण'),
        timestamp: null,
        icon: Icons.search_outlined,
        state: RequestStepState.upcoming,
        tone: pal.textDisabled,
      ),
      RequestTimelineStep(
        key: 'cancelled',
        title: AppLanguage.tr('Payment cancelled', 'भुक्तानी रद्द गरियो'),
        timestamp: null,
        icon: Icons.cancel_outlined,
        state: RequestStepState.failed,
        tone: pal.textDisabled,
      ),
    ];
  }
  // Pending verification: fresh initiated is still in progress; stale
  // initiated or failed means verification failed.
  final failed =
      record.gatewayStatus == 'failed' || record.isStaleInitiated;
  return [
    submitted,
    RequestTimelineStep(
      key: 'verification',
      title: failed
          ? AppLanguage.tr(
              'Payment Verification Failed', 'भुक्तानी प्रमाणीकरण असफल')
          : AppLanguage.tr('Payment Verification', 'भुक्तानी प्रमाणीकरण'),
      timestamp: null,
      icon: failed ? Icons.error_outline : Icons.search_outlined,
      state: failed ? RequestStepState.failed : RequestStepState.current,
      tone: failed ? pal.danger : pal.warning,
    ),
    RequestTimelineStep(
      key: 'review',
      title: AppLanguage.tr(
          'Waiting for admin review', 'एड्मिन समीक्षाको प्रतीक्षामा'),
      timestamp: null,
      icon: Icons.search_outlined,
      state: RequestStepState.upcoming,
      tone: pal.textDisabled,
    ),
    RequestTimelineStep(
      key: 'activated',
      title: AppLanguage.tr('Verified & Activated', 'प्रमाणित तथा सक्रिय'),
      timestamp: null,
      icon: Icons.check_circle_outline,
      state: RequestStepState.upcoming,
      tone: pal.textDisabled,
    ),
  ];
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

// ===================== Payment problem (gateway recovery) =====================

/// Banner shown when a gateway payment is stuck pending verification.
class _VerificationPendingBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: pal.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ExpoRadius.md),
        border: Border.all(color: pal.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: pal.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLanguage.tr(
                'Payment Verification Pending! Pls Contact Admin',
                'भुक्तानी प्रमाणीकरण बाँकी छ! कृपया Admin लाई सम्पर्क गर्नुहोस्',
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: pal.warning,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== Payment summary =====================

/// Transaction reference with stable wrapping + tap-to-copy (long gateway
/// ids like txn_xxx_xxx_xxx used to break mid-string).
// The copy-enabled Reference value now lives in the shared row widget
// (RequestReferenceValue in widgets/request_info_row.dart) so its value
// column aligns with every other summary row.

class _PaymentSummary extends StatelessWidget {
  final SubscriptionRecord record;
  const _PaymentSummary({required this.record});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Column(
      children: [
        RequestInfoRow(
          icon: Icons.diamond_outlined,
          label: AppLanguage.tr('Plan', 'योजना'),
          value: Text(record.planName),
        ),
        RequestInfoRow(
          icon: Icons.payments_outlined,
          label: AppLanguage.tr('Amount', 'रकम'),
          tone: pal.success,
          value: Text('Rs. ${_money(record.amount)}',
              style: TextStyle(color: pal.success)),
        ),
        RequestInfoRow(
          icon: Icons.credit_card_outlined,
          label: AppLanguage.tr('Payment Method', 'भुक्तानी विधि'),
          value: Text(record.method.toUpperCase(),
              style: TextStyle(
                  color: requestMethodColor(context, record.method))),
        ),
        // v1.0.110: where the payment was made — "App - eSewa" etc.
        RequestInfoRow(
          icon: Icons.smartphone_outlined,
          label: AppLanguage.tr('Platform', 'प्लेटफर्म'),
          value: Text(record.platformLabel),
        ),
        RequestInfoRow(
          // Gateway payments never involve a QR — use a reference icon.
          icon: record.isGateway ? Icons.link_outlined : Icons.qr_code_outlined,
          label: AppLanguage.tr('Reference', 'सन्दर्भ'),
          value: RequestReferenceValue(ref: record.transactionRef),
          last: record.couponCode == null && record.customerMessage == null,
        ),
        if (record.couponCode != null)
          RequestInfoRow(
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
          RequestInfoRow(
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

/// Adapter: exposes a SubscriptionRecord through the shared
/// PaymentProblemSection's record interface.
class _SubscriptionProblemRecord implements PaymentProblemRecord {
  final SubscriptionRecord record;
  _SubscriptionProblemRecord(this.record);

  @override
  String get method => record.method;

  @override
  String get transactionRef => record.transactionRef ?? '';

  @override
  String? get failureReason => record.failureReason;

  @override
  bool get isFraud => record.isFraud;

  @override
  String get successTitle => record.planName;
}

/// Premium section card: tone-tinted icon box + title (+ optional trailing)
/// over a bordered surface. Mirrors SectionCard.

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

/// User-facing status label — same mapping as the Your-Request list.
/// "New" is admin language and never shown to users.
String _statusTag(SubscriptionRecord record, {required bool isCurrent}) {
  final status = record.status;
  if (status == SubscriptionStatus.active) {
    return isCurrent
        ? AppLanguage.tr(
            'Approved and Currently Active', 'स्वीकृत र हाल सक्रिय')
        : AppLanguage.tr('Approved', 'स्वीकृत');
  }
  if (status == SubscriptionStatus.expired) {
    return record.expiredReason == 'plan_change'
        ? AppLanguage.tr('Expired (User Change Plan)',
            'म्याद सकिएको (योजना परिवर्तन)')
        : AppLanguage.tr('Expired', 'म्याद सकिएको');
  }
  if (status == SubscriptionStatus.rejected) {
    return AppLanguage.tr('Rejected', 'अस्वीकृत');
  }
  if (status == SubscriptionStatus.cancelled) {
    return AppLanguage.tr('Cancelled', 'रद्द गरिएको');
  }
  // pending
  if (record.isFraud) {
    return AppLanguage.tr('Verification Failed', 'प्रमाणीकरण असफल');
  }
  if (record.hasDefinitiveFailure) {
    return AppLanguage.tr('Payment Not Completed', 'भुक्तानी पूरा भएन');
  }
  if (record.isGateway && record.gatewayStatus == 'initiated') {
    return AppLanguage.tr(
        'Verification Not Confirmed', 'प्रमाणीकरण पुष्टि भएको छैन');
  }
  return AppLanguage.tr('Pending Review', 'समीक्षा बाँकी');
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
    case SubscriptionStatus.cancelled:
      return Icons.cancel_outlined;
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
