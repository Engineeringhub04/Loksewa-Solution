// My purchases — one list of everything the student has bought individually:
// exam papers plus subject / unit / chapter content. Filter by track, tap
// through to the request detail.
//
// Mirrors app/purchase-details/index.tsx: a hero band tallying the records
// (total / pending / approved), a track filter with counts, and purchase
// cards that route to /subscription/exam-purchase/:id and
// /purchase-details/content/:id. Records come from the purchase services
// (server-side uid filter, newest first).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/exam_purchases.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';

class PurchaseDetailsScreen extends StatefulWidget {
  const PurchaseDetailsScreen({super.key});

  @override
  State<PurchaseDetailsScreen> createState() => _PurchaseDetailsScreenState();
}

class _PurchaseDetailsScreenState extends State<PurchaseDetailsScreen> {
  late Future<_Purchases> _future = _load();
  // Cached so refetches keep the current list on screen instead of blanking
  // it — React's useAsyncData behaves the same way.
  _Purchases? _purchases;
  Object? _error;
  String _filter = 'all'; // all | exam | content

  String _t(String en, String ne) => AppLanguage.tr(en, ne);

  Future<_Purchases> _load() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return _Purchases(const [], const []);
    }
    final results = await Future.wait([
      fetchMyExamPurchases(uid),
      fetchMyContentPurchases(uid),
    ]);
    return _Purchases(
        results[0] as List<ExamPurchaseRecord>,
        results[1] as List<ContentPurchaseRecord>);
  }

  Future<void> _refresh() async {
    try {
      final p = await _load();
      if (!mounted) return;
      setState(() {
        _purchases = p;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${m[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: _t('Purchase Details', 'खरिद विवरण')),
          Expanded(
            child: FutureBuilder<_Purchases>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.done) {
                  if (snap.hasError) {
                    _error = snap.error;
                  } else if (snap.hasData) {
                    _purchases = snap.data;
                    _error = null;
                  }
                }
                final p = _purchases;
                if (p == null) {
                  // First load in flight: blank behind nothing — React hides
                  // the hero too until the first load settles.
                  if (_error != null) return _errorBody(palette);
                  return PreloadingWidget(
                    tinted: false,
                    label: _t('Loading Subscription...',
                        'सदस्यता लोड हुँदैछ...'),
                    hint: _t('Fetching your purchase history',
                        'खरिद इतिहास ल्याउँदै'),
                  );
                }
                if (_error != null) return _errorBody(palette);
                return _contentBody(palette, p);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBody(ExpoPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _t('Could not load your purchases.',
                  'तपाईंका खरिदहरू लोड गर्न सकिएन।'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () =>
                  setState(() => _future = _load()),
              child: Text(_t('Retry', 'पुनः प्रयास गर्नुहोस्')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentBody(ExpoPalette palette, _Purchases p) {
    final exams = _filter == 'content' ? <ExamPurchaseRecord>[] : p.exams;
    final contents =
        _filter == 'exam' ? <ContentPurchaseRecord>[] : p.contents;

    final statuses = [
      ...p.exams.map((r) => r.status),
      ...p.contents.map((r) => r.status),
    ];
    final total = statuses.length;
    final pending = statuses.where((s) => s == 'pending').length;
    final active = statuses.where((s) => s == 'active').length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroBand(palette, total, pending, active),
            const SizedBox(height: 12),
            // Track filter with counts (React's FilterTrack).
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'all',
                    label: Text(
                        '${_t('All', 'सबै')} (${p.exams.length + p.contents.length})')),
                ButtonSegment(
                    value: 'exam',
                    label: Text(
                        '${_t('Exam Details', 'परीक्षा विवरण')} (${p.exams.length})')),
                ButtonSegment(
                    value: 'content',
                    label: Text(
                        '${_t('Content Details', 'सामग्री विवरण')} (${p.contents.length})')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) =>
                  setState(() => _filter = s.first),
            ),
            const SizedBox(height: 12),
            if (exams.isEmpty && contents.isEmpty)
              _emptyPurchases(palette)
            else ...[
              for (final r in exams) ...[
                _ExamPurchaseCard(
                  record: r,
                  date: _fmtDate(r.submittedAt),
                  onPress: () => context.push(
                      '/subscription/exam-purchase/${r.id}'),
                ),
                const SizedBox(height: 12),
              ],
              for (final r in contents) ...[
                _ContentPurchaseCard(
                  record: r,
                  date: _fmtDate(r.submittedAt),
                  onPress: () => context
                      .push('/purchase-details/content/${r.id}'),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // Mirrors React's HeroBand: surface card, tone gradient wash from the top,
  // 54px medallion + title + subtitle, footer row of stat tiles.
  Widget _heroBand(
      ExpoPalette palette, int total, int pending, int active) {
    final primary = palette.primary;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border, width: 0.5),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primary.withValues(alpha: 0x14 / 0xFF),
                    primary.withValues(alpha: 0x00 / 0xFF),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0x14 / 0xFF),
                        border: Border.all(
                            color: primary
                                .withValues(alpha: 0x33 / 0xFF),
                            width: 0.5),
                        borderRadius:
                            BorderRadius.circular(ExpoRadius.lg),
                      ),
                      child: Icon(Icons.receipt_outlined,
                          size: 26, color: primary),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('Purchase Details', 'खरिद विवरण'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: ExpoType.h2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _t(
                                'View and track your individual exam, subject, unit, and chapter purchases.',
                                'तपाईंका exam, subject, unit र chapter purchase हरू हेर्नुहोस् र track गर्नुहोस्।'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: ExpoType.bodySmall,
                              height: 17 / 12,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _statTile(
                          palette,
                          primary,
                          '$total',
                          _t('All', 'सबै'),
                          Icons.layers_outlined),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _statTile(
                          palette,
                          palette.warning,
                          '$pending',
                          _t('Pending Review', 'समीक्षा हुँदैछ'),
                          Icons.access_time),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _statTile(
                          palette,
                          palette.success,
                          '$active',
                          _t('Approved', 'स्वीकृत'),
                          Icons.check_circle),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(ExpoPalette palette, Color tone, String value,
      String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0x14 / 0xFF),
        border: Border.all(
            color: tone.withValues(alpha: 0x33 / 0xFF), width: 0.5),
        borderRadius: BorderRadius.circular(ExpoRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: tone),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ExpoType.h3,
                    fontWeight: FontWeight.bold,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ExpoType.overline,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // Mirrors React's EmptyPurchases: section card with an icon badge, a
  // per-track title, and the shared description.
  Widget _emptyPurchases(ExpoPalette palette) {
    final primary = palette.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border, width: 0.5),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0x14 / 0xFF),
              border: Border.all(
                  color:
                      primary.withValues(alpha: 0x33 / 0xFF),
                  width: 0.5),
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
            ),
            child: Icon(Icons.receipt_outlined,
                size: 30, color: primary),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _filter == 'content'
                  ? _t('No content purchase requests yet.',
                      'अहिलेसम्म सामग्री खरिद अनुरोध छैन।')
                  : _t('No exam purchase requests yet.',
                      'अहिलेसम्म exam purchase request छैन।'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: ExpoType.bodyLarge,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            _t('Your exam purchase requests will appear here.',
                'तपाईंका exam purchase requests यहाँ देखिनेछन्।'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ExpoType.bodySmall,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Purchases {
  final List<ExamPurchaseRecord> exams;
  final List<ContentPurchaseRecord> contents;
  _Purchases(this.exams, this.contents);
}

// ===================== One card shell, two record shapes =====================

class _PurchaseCardShell extends StatefulWidget {
  final IconData icon;
  final Color tone;
  final String title;
  final String meta;
  final Widget? badge;
  final String status;
  final String statusLabel;
  final num amount;
  final String date;
  final String? adminMessage;
  final VoidCallback onPress;

  const _PurchaseCardShell({
    required this.icon,
    required this.tone,
    required this.title,
    required this.meta,
    this.badge,
    required this.status,
    required this.statusLabel,
    required this.amount,
    required this.date,
    this.adminMessage,
    required this.onPress,
  });

  @override
  State<_PurchaseCardShell> createState() => _PurchaseCardShellState();
}

class _PurchaseCardShellState extends State<_PurchaseCardShell> {
  bool _pressed = false;

  Color _statusColor() {
    switch (widget.status) {
      case 'active':
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  IconData _statusIcon() {
    switch (widget.status) {
      case 'active':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.access_time;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final tone = widget.tone;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPress,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // Tint on press rather than fade — React's PurchaseCardShell.
          color: _pressed
              ? tone.withValues(alpha: 0x14 / 0xFF)
              : palette.surface,
          border: Border.all(color: palette.border, width: 0.5),
          borderRadius: BorderRadius.circular(ExpoRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0x14 / 0xFF),
                    border: Border.all(
                        color: tone.withValues(alpha: 0x33 / 0xFF),
                        width: 0.5),
                    borderRadius:
                        BorderRadius.circular(ExpoRadius.md),
                  ),
                  child: Icon(widget.icon, size: 20, color: tone),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: ExpoType.bodyLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ExpoType.caption,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: palette.textDisabled),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusPill(
                        label: widget.statusLabel,
                        color: _statusColor(),
                        icon: _statusIcon(),
                      ),
                      if (widget.badge != null) widget.badge!,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Rs. ${widget.amount}${widget.date.isNotEmpty ? ' · ${widget.date}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ExpoType.caption,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
            // Admin message quote panel.
            if (widget.adminMessage != null &&
                widget.adminMessage!.isNotEmpty) ...[
              const SizedBox(height: 11),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _statusColor()
                      .withValues(alpha: 0x14 / 0xFF),
                  border: Border(
                    left: BorderSide(
                        color: _statusColor(), width: 3),
                    top: BorderSide(
                        color: _statusColor().withValues(
                            alpha: 0x33 / 0xFF),
                        width: 0.5),
                    right: BorderSide(
                        color: _statusColor().withValues(
                            alpha: 0x33 / 0xFF),
                        width: 0.5),
                    bottom: BorderSide(
                        color: _statusColor().withValues(
                            alpha: 0x33 / 0xFF),
                        width: 0.5),
                  ),
                  borderRadius:
                      BorderRadius.circular(ExpoRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 14, color: _statusColor()),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.adminMessage!,
                        style:
                            const TextStyle(fontSize: ExpoType.bodySmall),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExamPurchaseCard extends StatelessWidget {
  final ExamPurchaseRecord record;
  final String date;
  final VoidCallback onPress;

  const _ExamPurchaseCard(
      {required this.record, required this.date, required this.onPress});

  String _t(String en, String ne) => AppLanguage.tr(en, ne);

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final statusLabel = record.status == 'active'
        ? _t('Approved', 'स्वीकृत')
        : record.status == 'rejected'
            ? _t('Rejected', 'अस्वीकृत')
            // React's index card uses purchasePending here (not pendingReview).
            : _t('Purchase Pending', 'खरिद समीक्षा हुँदैछ');
    final meta = [
      record.courseName,
      record.subcourseName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return _PurchaseCardShell(
      icon: Icons.description_outlined,
      tone: palette.primary,
      title: record.examTitle.isNotEmpty
          ? record.examTitle
          : _t('Exam Purchase', 'परीक्षा खरिद'),
      meta: meta,
      badge: StatusPill(
        label: _t('Exam Details', 'परीक्षा विवरण'),
        color: palette.primary,
        icon: Icons.school_outlined,
      ),
      status: record.status,
      statusLabel: statusLabel,
      amount: record.amount,
      date: date,
      adminMessage: record.adminMessage,
      onPress: onPress,
    );
  }
}

class _ContentPurchaseCard extends StatelessWidget {
  final ContentPurchaseRecord record;
  final String date;
  final VoidCallback onPress;

  const _ContentPurchaseCard(
      {required this.record, required this.date, required this.onPress});

  String _t(String en, String ne) => AppLanguage.tr(en, ne);

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final statusLabel = record.status == 'active'
        ? _t('Approved', 'स्वीकृत')
        : record.status == 'rejected'
            ? _t('Rejected', 'अस्वीकृत')
            : _t('Purchase Pending', 'खरिद समीक्षा हुँदैछ');
    final title = AppLanguage.isNepali && record.contentTitleNe.isNotEmpty
        ? record.contentTitleNe
        : record.contentTitle;
    // The old card printed `contentType · subjectId` — a raw enum next to a
    // raw document id. The type is the only part a student can read, so it
    // becomes a translated pill.
    final typeLabel = record.contentType == 'subject'
        ? _t('Subject', 'विषय')
        : record.contentType == 'unit'
            ? _t('Unit', 'युनिट')
            : _t('Chapter', 'अध्याय');
    return _PurchaseCardShell(
      icon: Icons.book_outlined,
      tone: palette.accent,
      title: title.isNotEmpty
          ? title
          : _t('Content Purchase', 'सामग्री खरिद'),
      meta: '',
      badge: StatusPill(
        label: typeLabel,
        color: palette.accent,
        icon: Icons.layers_outlined,
      ),
      status: record.status,
      statusLabel: statusLabel,
      amount: record.amount,
      date: date,
      adminMessage: record.adminMessage,
      onPress: onPress,
    );
  }
}
