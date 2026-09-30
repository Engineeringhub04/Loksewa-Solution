import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/stagger_entrance.dart';

/// Practice Analytics — REAL data only, from
/// `users/{uid}/learning_progress` docs
/// (`{subjectSlug}__{chapterSlug}`).
///
/// Known doc fields: `attemptedQuestionIds` / `correctQuestionIds` (lists),
/// `completed` (bool), `totalQuestions` (int), `updatedAt` (timestamp),
/// `unitId`, `subjectId`, `chapterId`.
///
/// There is NO per-day question granularity in these docs, so nothing here
/// invents daily question counts: every number is an aggregate over docs,
/// and every time-scoped label says exactly what it measures (chapters
/// active in the window, by `updatedAt`).
class PracticeAnalyticsScreen extends StatefulWidget {
  final String? subjectSlug;
  final String? subjectTitle;
  final String? unitId;
  final String? unitTitle;
  final String? chapterSlug;
  final String? chapterTitle;

  const PracticeAnalyticsScreen({
    super.key,
    this.subjectSlug,
    this.subjectTitle,
    this.unitId,
    this.unitTitle,
    this.chapterSlug,
    this.chapterTitle,
  });

  @override
  State<PracticeAnalyticsScreen> createState() =>
      _PracticeAnalyticsScreenState();
}

class _PracticeAnalyticsScreenState extends State<PracticeAnalyticsScreen> {
  late Future<_AnalyticsData> _future;

  /// 0 = Today, 1 = Last 7 days, 2 = All time.
  int _tab = 2;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  static String _canon(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  bool _matches(Map<String, dynamic> d) {
    final id = '${d['id'] ?? ''}';
    final parts = id.split('__');
    final idSubject = parts.isNotEmpty ? parts.first : '';
    final idChapter =
        parts.length > 1 ? parts.sublist(1).join('__') : '';
    if (widget.subjectSlug != null && widget.subjectSlug!.isNotEmpty) {
      final want = _canon(widget.subjectSlug!);
      final raw = '${d['subjectId'] ?? ''}';
      if (_canon(idSubject) != want &&
          _canon(raw) != want &&
          raw != widget.subjectSlug) {
        return false;
      }
    }
    if (widget.unitId != null && widget.unitId!.isNotEmpty) {
      if ('${d['unitId'] ?? ''}' != widget.unitId) return false;
    }
    if (widget.chapterSlug != null && widget.chapterSlug!.isNotEmpty) {
      final want = _canon(widget.chapterSlug!);
      if (_canon(idChapter) != want &&
          _canon('${d['chapterId'] ?? ''}') != want) {
        return false;
      }
    }
    return true;
  }

  Future<_AnalyticsData> _load() async {
    final user = AuthService.currentUser;
    // ExamRest auto-attaches the ID token (same pattern as the other
    // learning_progress reads), but a signed-in user is still required.
    if (user == null) throw const _SignInRequired();
    final docs = await ExamRest.listDocs(
        'users/${user.uid}/learning_progress',
        pageSize: 200);
    final rows = <_ChapterStat>[];
    for (final d in docs) {
      if (!_matches(d)) continue;
      final id = '${d['id'] ?? ''}';
      final idParts = id.split('__');
      rows.add(_ChapterStat(
        chapterId: '${d['chapterId'] ?? (idParts.length > 1 ? idParts.sublist(1).join('__') : id)}',
        subjectId: d['subjectId'] as String?,
        unitId: d['unitId'] as String?,
        attempted:
            ((d['attemptedQuestionIds'] as List?) ?? []).whereType<String>().length,
        correct:
            ((d['correctQuestionIds'] as List?) ?? []).whereType<String>().length,
        total: (d['totalQuestions'] as num?)?.toInt() ?? 0,
        completed: d['completed'] == true,
        updatedAt: d['updatedAt'] as DateTime?,
      ));
    }
    rows.sort((a, b) {
      final au = a.updatedAt, bu = b.updatedAt;
      if (au != null && bu != null) return bu.compareTo(au);
      if (au != null) return -1;
      if (bu != null) return 1;
      return a.chapterId.compareTo(b.chapterId);
    });
    return _AnalyticsData(rows: rows);
  }

  String get _scopeTitle =>
      widget.chapterTitle ??
      widget.unitTitle ??
      widget.subjectTitle ??
      'All Subjects';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Docs whose last activity falls in the selected window.
  List<_ChapterStat> _windowRows(List<_ChapterStat> rows) {
    final now = DateTime.now();
    if (_tab == 0) {
      return rows
          .where((r) => r.updatedAt != null && _sameDay(r.updatedAt!, now))
          .toList();
    }
    if (_tab == 1) {
      final cutoff =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      return rows
          .where((r) => r.updatedAt != null && !r.updatedAt!.isBefore(cutoff))
          .toList();
    }
    return rows;
  }

  String get _windowPhrase =>
      _tab == 0 ? 'today' : _tab == 1 ? 'in the last 7 days' : 'all time';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Practice Analytics'),
          Expanded(
            child: FutureBuilder<_AnalyticsData>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const PreloadingWidget(
                    tinted: false,
                    label: 'Loading Analytics...',
                  );
                }
                if (snap.hasError) {
                  return _errorState(context, snap.error);
                }
                final data = snap.data!;
                if (data.rows.isEmpty) return _emptyState(context);
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      StaggerEntrance(
                          delayMs: 0,
                          child: _heroCard(context, data)),
                      const SizedBox(height: 14),
                      StaggerEntrance(
                          delayMs: 60, child: _timeTabs(context)),
                      const SizedBox(height: 10),
                      StaggerEntrance(
                          delayMs: 90,
                          child: _windowCard(context, data)),
                      const SizedBox(height: 16),
                      StaggerEntrance(
                          delayMs: 120,
                          child: _weeklyCard(context, data)),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'Chapters (${data.rows.length})',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...data.rows.asMap().entries.map((e) =>
                          StaggerEntrance(
                            delayMs: (e.key > 8 ? 8 : e.key) * 60,
                            child: _chapterRow(context, e.value),
                          )),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ states
  Widget _errorState(BuildContext context, Object? error) {
    final signIn = error is _SignInRequired;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined,
                size: 44,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(
              signIn
                  ? 'Sign in to view your practice analytics.'
                  : 'Failed to load practice analytics.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (!signIn)
              ElevatedButton(
                onPressed: _reload,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 64),
          Icon(Icons.analytics_outlined,
              size: 52,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          const Text('No practice data yet',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Attempt practice questions in $_scopeTitle and your analytics will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ hero card
  /// ALL-TIME aggregates over every matching doc.
  Widget _heroCard(BuildContext context, _AnalyticsData data) {
    final rows = data.rows;
    final attempted = rows.fold(0, (a, r) => a + r.attempted);
    final correct = rows.fold(0, (a, r) => a + r.correct);
    final completed = rows.where((r) => r.completed).length;
    final total = rows.fold(0, (a, r) => a + r.total);
    final accuracy =
        attempted == 0 ? null : (correct / attempted * 100).round();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x470C2D91), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF153DB8), Color(0xFF0C2D91)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -90,
                right: -36,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF5A8CFF)
                        .withValues(alpha: 0.22),
                  ),
                ),
              ),
              Positioned(
                bottom: -110,
                left: -60,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00002D)
                        .withValues(alpha: 0.16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _scopeTitle,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'All-time practice totals',
                      style: TextStyle(
                          color:
                              Colors.white.withValues(alpha: 0.72),
                          fontSize: 11),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _heroStat('$attempted', 'Attempted'),
                        _heroStat(
                            accuracy == null ? '—' : '$accuracy%',
                            'Accuracy'),
                        _heroStat('$completed', 'Completed'),
                        _heroStat('$total', 'Total Qs'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 10),
            textAlign: TextAlign.center),
      ],
    );
  }

  // ------------------------------------------------------------ time tabs
  Widget _timeTabs(BuildContext context) {
    const labels = ['Today', 'Last 7 Days', 'All Time'];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      ),
      child: Row(
        children: labels.asMap().entries.map((e) {
          final active = _tab == e.key;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: active
                      ? const LinearGradient(
                          colors: [
                            Color(0xFF2563EB),
                            Color(0xFF1D4ED8)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                ),
                child: Text(e.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: active
                            ? Colors.white
                            : scheme.onSurface
                                .withValues(alpha: 0.65))),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Stats over the doc SET active in the selected window — labels stay
  /// honest about what the window measures.
  Widget _windowCard(BuildContext context, _AnalyticsData data) {
    final rows = _windowRows(data.rows);
    final attempted = rows.fold(0, (a, r) => a + r.attempted);
    final correct = rows.fold(0, (a, r) => a + r.correct);
    final accuracy =
        attempted == 0 ? null : (correct / attempted * 100).round();
    final scheme = Theme.of(context).colorScheme;
    final subtle = scheme.onSurface.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).cardColor,
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D0F172A), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          _windowRow('Chapters active $_windowPhrase', '${rows.length}',
              context),
          const SizedBox(height: 10),
          _windowRow('Questions attempted in active chapters',
              '$attempted', context),
          const SizedBox(height: 10),
          _windowRow('Accuracy across active chapters',
              accuracy == null ? '—' : '$accuracy%', context,
              strong: true),
          const SizedBox(height: 10),
          Text(
            'Based on chapter activity dates — daily question counts are not tracked.',
            style: TextStyle(fontSize: 10, color: subtle),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _windowRow(String label, String value, BuildContext context,
      {bool strong = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurface.withValues(alpha: 0.75))),
        ),
        const SizedBox(width: 12),
        Text(value,
            style: TextStyle(
                fontSize: strong ? 15 : 13.5,
                fontWeight: FontWeight.bold,
                color: strong
                    ? const Color(0xFF1D4ED8)
                    : scheme.onSurface)),
      ],
    );
  }

  // ------------------------------------------------------------ weekly chart
  /// Active chapters per day over the last 7 days, bucketed by each doc's
  /// `updatedAt` date — honestly labeled as activity, not question counts.
  Widget _weeklyCard(BuildContext context, _AnalyticsData data) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days =
        List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final counts = days
        .map((d) => data.rows
            .where((r) => r.updatedAt != null && _sameDay(r.updatedAt!, d))
            .length)
        .toList();
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).cardColor,
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D0F172A), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Chapters active per day',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('By last activity — last 7 days',
              style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          SizedBox(
            height: 118,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: days.asMap().entries.map((e) {
                final i = e.key;
                final day = e.value;
                final count = counts[i];
                final isToday = i == 6;
                final frac = max == 0 ? 0.0 : count / max;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('$count',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface
                                  .withValues(alpha: 0.7))),
                      const SizedBox(height: 4),
                      Expanded(
                        child: FractionallySizedBox(
                          alignment: Alignment.bottomCenter,
                          heightFactor:
                              count == 0 ? 0.06 : (0.12 + 0.88 * frac),
                          child: Container(
                            width: 22,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(7)),
                              color: count == 0
                                  ? scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.7)
                                  : null,
                              gradient: count == 0
                                  ? null
                                  : LinearGradient(
                                      colors: isToday
                                          ? [
                                              const Color(0xFFF59E0B),
                                              const Color(0xFFD97706)
                                            ]
                                          : const [
                                              Color(0xFF3B82F6),
                                              Color(0xFF1D4ED8)
                                            ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        letters[day.weekday - 1],
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.w500,
                            color: isToday
                                ? const Color(0xFF1D4ED8)
                                : scheme.onSurface
                                    .withValues(alpha: 0.55)),
                      ),
                      Text('${day.day}',
                          style: TextStyle(
                              fontSize: 9,
                              color: scheme.onSurface
                                  .withValues(alpha: 0.45))),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ chapter rows
  Widget _chapterRow(BuildContext context, _ChapterStat r) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accuracy =
        r.attempted == 0 ? null : (r.correct / r.attempted * 100).round();
    final pct = r.total > 0
        ? (r.attempted / r.total * 100).round().clamp(0, 100)
        : (r.completed ? 100 : 0);
    final softPrimary = dark
        ? const Color(0xFF2563EB).withValues(alpha: 0.18)
        : const Color(0xFFE7EEFF);
    final fg = dark ? const Color(0xFF93B4FF) : const Color(0xFF0C2D91);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color:
                    Theme.of(context).dividerColor.withValues(alpha: 0.6)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0D0F172A),
                  blurRadius: 8,
                  offset: Offset(0, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: softPrimary,
                    ),
                    child: Icon(Icons.quiz_outlined, size: 16, color: fg),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.chapterId,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (r.unitId != null && r.unitId!.isNotEmpty)
                          Text('Unit: ${r.unitId}',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.6)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(accuracy == null ? '—' : '$accuracy%',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: accuracy == null
                                  ? scheme.onSurface
                                      .withValues(alpha: 0.4)
                                  : const Color(0xFF1D4ED8))),
                      Text('accuracy',
                          style: TextStyle(
                              fontSize: 9.5,
                              color: scheme.onSurface
                                  .withValues(alpha: 0.55))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: scheme.surfaceContainerHighest,
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: pct / 100,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: pct >= 100
                                ? const Color(0xFF059669)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('$pct%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface
                              .withValues(alpha: 0.7))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '${r.attempted}${r.total > 0 ? ' / ${r.total}' : ''} questions',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurface
                              .withValues(alpha: 0.6))),
                  Text(
                      r.updatedAt == null
                          ? 'No activity date'
                          : 'Last active ${_fmtDate(r.updatedAt!)}',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurface
                              .withValues(alpha: 0.6))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _SignInRequired implements Exception {
  const _SignInRequired();
}

class _ChapterStat {
  final String chapterId;
  final String? subjectId;
  final String? unitId;
  final int attempted;
  final int correct;
  final int total;
  final bool completed;
  final DateTime? updatedAt;

  const _ChapterStat({
    required this.chapterId,
    this.subjectId,
    this.unitId,
    required this.attempted,
    required this.correct,
    required this.total,
    required this.completed,
    this.updatedAt,
  });
}

class _AnalyticsData {
  final List<_ChapterStat> rows;
  const _AnalyticsData({required this.rows});
}
