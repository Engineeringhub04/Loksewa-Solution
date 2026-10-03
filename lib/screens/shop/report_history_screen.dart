// Your Report History — one feed for every report context.
//
// Mirrors app/report-history/index.tsx: hero tally (all / pending /
// resolved), filter tracks derived from the sources actually present in the
// user's history (sorted by count desc — a new context gets its own tab
// automatically), per-source tone cards with the 4-state status pill,
// admin shortcut card, footer note, pull-to-refresh.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/syllabus_entrance.dart';
import 'report_visuals.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _isAdmin = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Mirrors `fetchMyReportHistory`: newest first. Security rules only ever
  /// return this user's docs for non-admins, so the client-side filter is a
  /// no-op.
  Future<void> _load({bool refresh = false}) async {
    if (!refresh) setState(() => _loading = true);
    try {
      final uid = AuthService.currentUser?.uid;
      final idToken = await AuthService.getValidIdToken();
      final userDoc =
          await FirestoreRest.getDocument('users/$uid', idToken: idToken)
              .catchError((_) => null);
      // Filtered query (not a blind list): the security rule only allows
      // reading own reports (or all for admins), so constrain server-side.
      // No ORDER BY — Firestore needs a composite index for where+orderBy;
      // we sort client-side instead.
      final raw = await ExamRest.runQuery(
        'app_report_history',
        where: ExamRest.fieldFilter('reporterId', 'EQUAL', uid ?? ''),
        limit: 200,
      );
      final mine = raw
        ..sort((a, b) => _millis(b['createdAt'])
            .compareTo(_millis(a['createdAt'])));
      if (!mounted) return;
      setState(() {
        _items = mine;
        _isAdmin = userDoc?['isAdmin'] == true;
        _loading = false;
        // A stale selection can outlive its last record — fall back to all.
        if (_filter != 'all' &&
            !_tracks.any((t) => t.key == _filter)) {
          _filter = 'all';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(
          context,
          AppLanguage.tr('Could not load your reports.',
              'तपाईंका रिपोर्टहरू लोड हुन सकेन।'),
          ToastVariant.error);
    }
  }

  int _millis(dynamic raw) {
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  /// Tracks derived from the sources actually present, sorted by count desc.
  List<MapEntry<String, int>> get _tracks {
    final counts = <String, int>{};
    for (final d in _items) {
      final s = (d['source'] ?? 'other').toString();
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<Map<String, dynamic>> get _visible => _filter == 'all'
      ? _items
      : _items
          .where((d) => (d['source'] ?? 'other').toString() == _filter)
          .toList();

  String _docId(Map<String, dynamic> d) => d['id']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr(
                  'Your Report History', 'तपाईंका रिपोर्टहरूको इतिहास')),
          Expanded(
            child: _loading
                ? PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
                    hint: AppLanguage.tr(
                        'Fetching your content', 'सामग्री ल्याउँदै'),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(refresh: true),
                    color: pal.primary,
                    child: _body(pal),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _body(ExpoPalette pal) {
    final tracks = _tracks;
    final visible = _visible;
    final open =
        _items.where((d) => d['status']?.toString() == 'pending').length;
    final closed =
        _items.where((d) => d['status']?.toString() == 'resolved').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _hero(pal, open, closed),
        if (_isAdmin) ...[
          const SizedBox(height: 12),
          _adminCard(pal),
        ],
        // Bleeds past the screen padding so the track scrolls edge to edge.
        if (tracks.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                _trackChip(pal, 'all', _items.length, null, true),
                for (final t in tracks) ...[
                  const SizedBox(width: 8),
                  _trackChip(pal, t.key, t.value,
                      reportSourceVisual(t.key), _filter == t.key),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (visible.isEmpty)
          _emptyBody(pal)
        else ...[
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            SyllabusEntrance(
              delayMs: (i < 8 ? i : 8) * 45,
              child: _ReportCard(
                record: visible[i],
                pal: pal,
                date: _fmtDate(visible[i]['createdAt']),
                onTap: () =>
                    context.push('/report-history/${_docId(visible[i])}'),
              ),
            ),
          ],
          // A quiet closing line so the list never ends on a hard edge.
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: pal.border,
                width: 0.75,
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 15, color: pal.textDisabled),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    AppLanguage.tr(
                        'Your report is waiting for admin review. A response will appear here once it is reviewed.',
                        'तपाईंको रिपोर्ट एडमिन समीक्षाको प्रतीक्षामा छ। समीक्षा भएपछि प्रतिक्रिया यहाँ देखिनेछ।'),
                    style: TextStyle(
                        fontSize: 11, color: pal.textDisabled),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _hero(ExpoPalette pal, int open, int closed) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.primary, const Color(0xFF1E40AF)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0x1A / 0xFF),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0x29 / 0xFF),
                ),
                child: const Icon(Icons.flag_outlined,
                    size: 22, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.tr('Your Report History',
                          'तपाईंका रिपोर्टहरूको इतिहास'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLanguage.tr(
                          'Everything you have reported, with its current status',
                          'तपाईंले पठाएका सबै रिपोर्ट, हालको स्थितिसहित'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0xCC / 0xFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(
                value: '${_items.length}',
                label: AppLanguage.tr('All', 'सबै'),
                icon: Icons.description_outlined,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              _StatTile(
                value: '$open',
                label: AppLanguage.tr('Pending review', 'समीक्षा बाँकी'),
                icon: Icons.schedule_outlined,
                color: const Color(0xFFFCD34D),
              ),
              const SizedBox(width: 8),
              _StatTile(
                value: '$closed',
                label: AppLanguage.tr('Resolved', 'समाधान भयो'),
                icon: Icons.check_circle_outline,
                color: const Color(0xFF6EE7B7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _adminCard(ExpoPalette pal) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => context.push('/admin/report-history'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: pal.surface,
          border: Border.all(color: pal.border, width: 0.75),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: pal.info.withValues(
                    alpha: dark ? 0x26 / 0xFF : 0x14 / 0xFF),
              ),
              child: Icon(Icons.admin_panel_settings_outlined,
                  size: 20, color: pal.info),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLanguage.tr('Report Details Control',
                        'रिपोर्ट विवरण नियन्त्रण'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: pal.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLanguage.tr(
                        'Review question and discussion reports, then send a custom resolution message.',
                        'प्रश्न र छलफलका रिपोर्ट समीक्षा गरी रिपोर्टकर्तालाई समाधान सन्देश पठाउनुहोस्।'),
                    style:
                        TextStyle(fontSize: 12, color: pal.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: pal.textDisabled),
          ],
        ),
      ),
    );
  }

  Widget _trackChip(ExpoPalette pal, String value, int count,
      ReportVisual? visual, bool active) {
    final accent = visual != null
        ? reportToneColor(pal, visual.tone)
        : pal.primary;
    final label = value == 'all'
        ? AppLanguage.tr('All', 'सबै')
        : AppLanguage.tr(visual!.labelEn, visual.labelNe);
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active
              ? accent.withValues(
                  alpha: (Theme.of(context).brightness == Brightness.dark
                          ? 0x2E
                          : 0x18) /
                      0xFF)
              : pal.surface,
          border: Border.all(
            color: active
                ? accent.withValues(
                    alpha: (Theme.of(context).brightness == Brightness.dark
                            ? 0x88
                            : 0x55) /
                        0xFF)
                : pal.border,
            width: 0.75,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (visual != null) ...[
              Icon(visual.icon,
                  size: 13,
                  color: active ? accent : pal.textSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    active ? FontWeight.bold : FontWeight.w500,
                color: active ? accent : pal.textSecondary,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: active ? accent : pal.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBody(ExpoPalette pal) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border, width: 0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.primary.withValues(
                  alpha: dark ? 0x26 / 0xFF : 0x14 / 0xFF),
              border: Border.all(
                color: pal.primary.withValues(
                    alpha: dark ? 0x55 / 0xFF : 0x33 / 0xFF),
                width: 0.75,
              ),
            ),
            child:
                Icon(Icons.flag_outlined, size: 30, color: pal.primary),
          ),
          const SizedBox(height: 16),
          Text(
            AppLanguage.tr('No reports found', 'रिपोर्ट भेटिएन'),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: pal.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            AppLanguage.tr(
                'New question and discussion reports will appear here.',
                'नयाँ प्रश्न र छलफल रिपोर्टहरू यहाँ देखिनेछन्।'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: pal.textSecondary),
          ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmtDate(dynamic raw) {
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is num) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return '—';
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _StatTile(
      {required this.value,
      required this.label,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0x1F / 0xFF),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0xCC / 0xFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  final Map<String, dynamic> record;
  final ExpoPalette pal;
  final String date;
  final VoidCallback onTap;
  const _ReportCard(
      {required this.record,
      required this.pal,
      required this.date,
      required this.onTap});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final r = widget.record;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sourceKey = (r['source'] ?? 'other').toString();
    final source = reportSourceVisual(sourceKey);
    final sourceColor = reportToneColor(pal, source.tone);
    final status = reportStatusVisual((r['status'] ?? 'pending').toString());
    final statusColor = reportToneColor(pal, status.tone);
    // The auto-filled origin ("Exam · Set 3") is far more useful than the
    // generic source name, so it wins when present.
    final origin = ((r['contextLabel'] ?? '').toString().isNotEmpty)
        ? r['contextLabel'].toString()
        : AppLanguage.tr(source.labelEn, source.labelNe);
    final tint = dark ? 0x26 / 0xFF : 0x14 / 0xFF;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // Pressed state tints instead of fading: a faded card on a light
          // background just looks unloaded.
          color: _pressed
              ? sourceColor.withValues(alpha: tint)
              : pal.surface,
          border: Border.all(
            color: _pressed ? sourceColor : pal.border,
            width: 0.75,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0x0F / 0xFF),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: sourceColor.withValues(alpha: tint),
                    border: Border.all(
                      color: sourceColor.withValues(
                          alpha: dark ? 0x55 / 0xFF : 0x33 / 0xFF),
                      width: 0.75,
                    ),
                  ),
                  child: Icon(source.icon,
                      size: 21, color: sourceColor),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ((r['targetTitle'] ?? '').toString().isNotEmpty)
                            ? r['targetTitle'].toString()
                            : origin,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$origin · ${(r['reason'] ?? '').toString()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: pal.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 19, color: pal.textDisabled),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: pal.divider, width: 0.75)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_month_outlined,
                          size: 13, color: pal.textDisabled),
                      const SizedBox(width: 5),
                      Text(
                        widget.date,
                        style: TextStyle(
                            fontSize: 12, color: pal.textSecondary),
                      ),
                    ],
                  ),
                  StatusPill(
                    label:
                        AppLanguage.tr(status.labelEn, status.labelNe),
                    color: statusColor,
                    icon: status.icon,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
