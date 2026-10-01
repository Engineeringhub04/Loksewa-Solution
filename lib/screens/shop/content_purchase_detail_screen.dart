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
import '../../widgets/subpage_header.dart';

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
  String _title = 'Content Purchase';

  final _refCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String? _screenshotUrl;
  Uint8List? _screenshotBytes;
  bool _editing = false;
  bool _saving = false;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  Timer? _ticker;

  String _t(String en, String ne) => AppLanguage.tr(en, ne);

  @override
  void initState() {
    super.initState();
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
    _refCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  String _contentTitle(ContentPurchaseRecord r) {
    if (AppLanguage.isNepali && r.contentTitleNe.isNotEmpty) {
      return r.contentTitleNe;
    }
    return r.contentTitle;
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
            : _t('Content Purchase', 'सामग्री खरिद');
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
                // React's PageLoaderOverlay — visible on initial load and
                // while the save is in flight.
                if (_loading || _saving)
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
                              _t('Loading Subscription...',
                                  'सदस्यता लोड हुँदैछ...'),
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
      // React keeps the screen empty behind the loader on this page
      // (PageLoaderOverlay) — mirror that: a blank frame, no inline spinner.
      return const SizedBox.shrink();
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
    final statusColor = status == 'active'
        ? const Color(0xFF16A34A)
        : status == 'rejected'
            ? const Color(0xFFDC2626)
            : const Color(0xFFD97706);
    final statusLabel = status == 'active'
        ? _t('Approved', 'स्वीकृत')
        : status == 'rejected'
            ? _t('Rejected', 'अस्वीकृत')
            : _t('Pending Review', 'समीक्षा हुँदैछ');
    final statusIcon = status == 'active'
        ? Icons.check_circle
        : status == 'rejected'
            ? Icons.cancel
            : Icons.access_time;
    final canEdit = isContentPurchaseEditable(record, _nowMs);
    final remainingLabel =
        _formatDuration(contentPurchaseEditRemainingMs(record, _nowMs));
    final title = _contentTitle(record);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0x14 / 0xFF),
              border: Border.all(color: statusColor),
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, size: 22, color: statusColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: ExpoType.bodyLarge,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (status == 'pending')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      canEdit
                          ? '${_t('Edit time remaining', 'सम्पादन गर्न बाँकी समय')}: $remainingLabel'
                          : _t('The 30-minute edit window has expired.',
                              '३० मिनेटको सम्पादन समय समाप्त भयो।'),
                      style: TextStyle(
                        fontSize: ExpoType.caption,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                if (record.rejectionReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      record.rejectionReason!,
                      style: TextStyle(
                        fontSize: ExpoType.body,
                        color: statusColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),

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

          if (status == 'pending') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: !canEdit
                    ? null
                    : _editing
                        ? _save
                        : () => setState(() => _editing = true),
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

          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              border:
                  Border.all(color: palette.border, width: 0.5),
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row(palette,
                    _t('Content Purchase', 'सामग्री खरिद'), title),
                _divider(palette),
                _row(palette, _t('Content type', 'सामग्रीको प्रकार'),
                    record.contentType),
                _divider(palette),
                _row(palette, _t('Course', 'कोर्स'),
                    record.courseId ?? '—'),
                _divider(palette),
                _row(palette, _t('Subcourse', 'सबकोर्स'),
                    record.subcourseId ?? '—'),
                _divider(palette),
                _row(palette, _t('Amount', 'रकम'),
                    'Rs. ${record.amount}'),
                _divider(palette),
                _row(palette, _t('Reference', 'सन्दर्भ'),
                    record.transactionRef ?? '—'),
                if (record.customerMessage != null) ...[
                  _divider(palette),
                  _row(palette,
                      _t('Message (optional)', 'सन्देश (वैकल्पिक)'),
                      record.customerMessage!),
                ],
              ],
            ),
          ),

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

  Widget _row(ExpoPalette palette, String label, String value) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: ExpoType.bodySmall,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: ExpoType.bodyLarge,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ExpoPalette palette) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: palette.divider,
    );
  }
}
