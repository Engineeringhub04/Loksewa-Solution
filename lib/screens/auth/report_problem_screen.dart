import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';

/// Report a Problem — mirrors `app/settings/report-problem.tsx`.
///
/// - Hero intro banner, single-column category list card with an animated
///   accent spine per row, custom "Other" field, description field,
///   dashed screenshot drop-zone, determinate upload progress, submit.
/// - Screenshot: picked through [ScreenshotPicker] (platform channel — see
///   `lib/services/report_service.dart` for the native wiring note), uploaded
///   to Cloudinary (unsigned preset, same as the Expo app), and its URL rides
///   inside the Google Form message body. A failed upload never fails the
///   report — the marker text goes in instead.
class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _Category {
  final String value;
  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  const _Category(this.value, this.label, this.desc, this.icon, this.color);
}

const _categories = [
  _Category('bug', 'Bug or error', 'Something crashes, freezes or will not open',
      Icons.bug_report_outlined, Color(0xFFEF4444)),
  _Category('content', 'Content problem', 'Wrong answer, typo or outdated material',
      Icons.description_outlined, Color(0xFF0EA5E9)),
  _Category('payment', 'Payment or access', 'Purchase not showing, billing or refund',
      Icons.credit_card_outlined, Color(0xFF10B981)),
  _Category('other', 'Something else', 'Anything that does not fit the options above',
      Icons.more_horiz, Color(0xFF8B5CF6)),
];

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  String? _category;
  final _customCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Uint8List? _imageBytes;
  bool _submitting = false;
  int _uploadPct = 0;
  bool? _offline;
  bool _attachPressed = false;

  @override
  void initState() {
    super.initState();
    _checkOnline();
  }

  Future<void> _checkOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(() => _offline = results.every(
          (r) => r == ConnectivityResult.none));
    } catch (_) {
      if (mounted) setState(() => _offline = false);
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _isOther => _category == 'other';
  bool get _categoryReady =>
      _category != null &&
      (!_isOther || _customCtrl.text.trim().isNotEmpty);
  bool get _canSubmit =>
      _categoryReady && _descCtrl.text.trim().isNotEmpty && !_submitting;

  Future<void> _pickScreenshot() async {
    try {
      final bytes = await ScreenshotPicker.pickImage();
      if (bytes != null && mounted) setState(() => _imageBytes = bytes);
    } on ScreenshotPickerUnavailable {
      if (!mounted) return;
      showToast(context, 'Image picker is not available in this build yet',
          ToastVariant.error);
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Could not pick the image', ToastVariant.error);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _category == null) return;
    setState(() {
      _submitting = true;
      _uploadPct = 0;
    });
    try {
      final category =
          _isOther ? _customCtrl.text.trim() : _category!;
      await ReportService.submitProblemReport(
        category: category,
        description: _descCtrl.text,
        screenshotBytes: _imageBytes,
        onUploadProgress: (f) {
          if (mounted) setState(() => _uploadPct = (f * 100).round());
        },
      );
      if (!mounted) return;
      showToast(
          context, 'Problem reported — thank you', ToastVariant.success);
      context.pop();
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Something went wrong', ToastVariant.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          const SubpageHeader(title: 'Report a Problem'),
          Expanded(
            child: _offline == true ? _offlineBody(pal) : _formBody(pal),
          ),
        ],
      ),
    );
  }

  Widget _offlineBody(ExpoPalette pal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.warning.withAlpha(0x14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined, size: 24, color: pal.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This requires an internet connection',
                    style: TextStyle(fontSize: 12, color: pal.warning),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              setState(() => _offline = null);
              _checkOnline();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _formBody(ExpoPalette pal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero — same pattern as the Report Question screen.
          _Entrance(
            delayMs: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.primary.withAlpha(0x14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pal.primary,
                    ),
                    child: const Icon(Icons.campaign,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Send us the details and we will look into it.',
                      style: TextStyle(
                        fontSize: 12,
                        color: pal.textSecondary,
                        height: 16 / 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ===== Category =====
          _Entrance(
            delayMs: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Category',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: pal.textPrimary)),
                      Text('Pick the closest match',
                          style: TextStyle(
                              fontSize: 11, color: pal.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: pal.surface,
                    border: Border.all(color: pal.border, width: 0.75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < _categories.length; i++) ...[
                        if (i > 0)
                          Container(
                            height: 0.75,
                            margin: const EdgeInsets.only(left: 16),
                            color: pal.divider,
                          ),
                        _CategoryRow(
                          item: _categories[i],
                          selected: _category == _categories[i].value,
                          pal: pal,
                          onTap: () =>
                              setState(() => _category = _categories[i].value),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Manual category — only while "Other" is selected.
          if (_isOther) ...[
            const SizedBox(height: 12),
            _Entrance(
              delayMs: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _customCtrl,
                    maxLength: 60,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Other',
                      prefixIcon:
                          const Icon(Icons.sell_outlined, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Text('Describe it below',
                        style: TextStyle(
                            fontSize: 11, color: pal.textSecondary)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ===== Description =====
          _Entrance(
            delayMs: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _descCtrl,
                  minLines: 5,
                  maxLines: 8,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Describe the problem',
                    alignLabelWithHint: true,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text('Add any detail that helps us fix it faster',
                      style:
                          TextStyle(fontSize: 11, color: pal.textSecondary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== Screenshot =====
          _Entrance(delayMs: 180, child: _screenshotSection(pal)),
          const SizedBox(height: 16),

          // ===== Submit =====
          _Entrance(
            delayMs: 240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_submitting && _imageBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 4,
                      color: pal.surfaceAlt,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: max(0.04, _uploadPct / 100),
                        child: Container(color: pal.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text('Uploading screenshot... $_uploadPct%',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11, color: pal.textSecondary)),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pal.primary,
                      disabledBackgroundColor:
                          pal.textDisabled.withAlpha(0x66),
                      foregroundColor: Colors.white,
                      disabledForegroundColor:
                          Colors.white.withAlpha(0xAA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Submit',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _screenshotSection(ExpoPalette pal) {
    if (_imageBytes != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: pal.surface,
          border: Border.all(color: pal.border, width: 0.75),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _imageBytes!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Screenshot attached',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: pal.textPrimary),
                  ),
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: () => setState(() => _imageBytes = null),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline,
                            size: 14, color: pal.danger),
                        const SizedBox(width: 4),
                        Text('Remove screenshot',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: pal.danger)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Dashed drop-zone — signals "add something here".
    return GestureDetector(
      onTap: _pickScreenshot,
      onTapDown: (_) => setState(() => _attachPressed = true),
      onTapUp: (_) => setState(() => _attachPressed = false),
      onTapCancel: () => setState(() => _attachPressed = false),
      child: CustomPaint(
        painter: _DashedBorderPainter(
            color: pal.border, radius: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _attachPressed ? pal.surfaceAlt : pal.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pal.primary.withAlpha(0x14),
                ),
                child: Icon(Icons.image_outlined,
                    size: 18, color: pal.primary),
              ),
              const SizedBox(width: 10),
              Text(
                'Attach Screenshot (optional)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: pal.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One category choice. The selection cue is an accent spine that grows from
/// the centre of the row's left edge, plus a washed tint, a filling icon chip
/// and a radio ring — all driven by one 0→1 selection tween.
class _CategoryRow extends StatefulWidget {
  final _Category item;
  final bool selected;
  final ExpoPalette pal;
  final VoidCallback onTap;
  const _CategoryRow(
      {required this.item,
      required this.selected,
      required this.pal,
      required this.onTap});

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final pal = widget.pal;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.72 : 1,
        duration: const Duration(milliseconds: 120),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: widget.selected ? 1 : 0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            return Stack(
              children: [
                // Washed accent layer (opacity is cheap to animate).
                Positioned.fill(
                  child: Opacity(
                    opacity: t * 0.1,
                    child: Container(color: item.color),
                  ),
                ),
                // Accent spine growing from the row's left edge.
                Positioned(
                  left: 0,
                  top: 12,
                  bottom: 12,
                  child: Opacity(
                    opacity: t,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(
                          1, t <= 0 ? 0.001 : t, 1),
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(
                              item.color.withAlpha(0x1F), item.color, t),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: 1 - t,
                              child: Icon(item.icon,
                                  size: 17, color: item.color),
                            ),
                            Opacity(
                              opacity: t,
                              child: Icon(item.icon,
                                  size: 17, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: pal.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: pal.textSecondary,
                                  height: 15 / 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                Color.lerp(pal.border, item.color, t)!,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Transform.scale(
                            scale: t <= 0 ? 0.001 : t,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: item.color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Staggered entrance: fade + slide down (mirrors `FadeInDown`).
class _Entrance extends StatefulWidget {
  final int delayMs;
  final Widget child;
  const _Entrance({required this.delayMs, required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  bool _go = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _go = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _go ? 1 : 0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _go ? Offset.zero : const Offset(0, -0.12),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Dashed rounded-rectangle border (Flutter has no dashed border natively).
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    const dashW = 6.0;
    const dashS = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final end = min(dist + dashW, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist = end + dashS;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
