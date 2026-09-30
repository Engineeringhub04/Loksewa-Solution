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

  /// Test hook for the unit-filter contract (see
  /// `_PracticeAnalyticsScreenState._unitMatches`).
  @visibleForTesting
  static bool debugUnitMatches(String? storedUnitId, String? wantUnitId) =>
      _PracticeAnalyticsScreenState._unitMatches(storedUnitId, wantUnitId);

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

  /// Mirrors `_canonicalLearningId` in exam_service.dart: composite ids like
  /// `course__subcourse__slug` collapse to their last `__` segment before
  /// canonicalization. The practice save and the units/chapters reads all use
  /// that normalization, so this filter must too — otherwise no stored doc
  /// ever matches and the page stays blank.
  static String _logical(String s) {
    final parts = s.split('__').where((p) => p.isNotEmpty).toList();
    return _canon(parts.isNotEmpty ? parts.last : s);
  }

  /// Unit filter contract: the practice save stores `unitId` canonicalized
  /// (`_canonicalLearningId` in exam_service.dart), while the units screen
  /// passes the raw track id — canonicalize both sides before comparing,
  /// like the subject/chapter filters do. Comparing raw strings here used
  /// to filter out every doc and show "No practice data yet".
  static bool _unitMatches(String? storedUnitId, String? wantUnitId) {
    if (wantUnitId == null || wantUnitId.isEmpty) return true;
    return _logical(storedUnitId ?? '') == _logical(wantUnitId);
  }

  bool _matches(Map<String, dynamic> d) {
    final id = '${d['id'] ?? ''}';
    final parts = id.split('__');
    final idSubject = parts.isNotEmpty ? parts.first : '';
    final idChapter =
        parts.length > 1 ? parts.sublist(1).join('__') : '';
    if (widget.subjectSlug != null && widget.subjectSlug!.isNotEmpty) {
      final want = _logical(widget.subjectSlug!);
      final raw = '${d['subjectId'] ?? ''}';
      if (_canon(idSubject) != want &&
          _canon(raw) != want &&
          raw != widget.subjectSlug) {
        return false;
      }
    }
    if (!_unitMatches(d['unitId'] as String?, widget.unitId)) return false;
    if (widget.chapterSlug != null && widget.chapterSlug!.isNotEmpty) {
      final want = _logical(widget.chapterSlug!);
      if (_canon(idChapter) != want &&
          _canon('${d['chapterId'] ?? ''}') != want) {
        return false;
      }
    }
    return true;
  }

  /// `updatedAt` is stored as an ISO-8601 string by the practice save
  /// (`DateTime.now().toUtc().toIso8601String()`), so `decode` returns a
  /// String, not a DateTime. Parse leniently — handles String, DateTime,
  /// or null — instead of `as DateTime?`, which threw on every doc and
  /// put the page in the error state.
  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  Future<_AnalyticsData> _load() async {
    final user = AuthService.currentUser;
    // ExamRest auto-attaches the ID token (same pattern as the other
    // learning_progress reads), but a signed-in user is still required.
    if (user == null) throw const _SignInRequired();
    final docs = await ExamRest.listDocs(
        'users/${user.uid}/learning_progress',
        pageSize: 200);
    var courseId = '';
    var subcourseId = '';
    final rows = <_ChapterStat>[];
    for (final d in docs) {
      if (!_matches(d)) continue;
      // The practice save writes the raw course/subcourse alongside the
      // canonical ids — reuse them for the catalogue lookup below.
      if (courseId.isEmpty) courseId = '${d['courseId'] ?? ''}';
      if (subcourseId.isEmpty) subcourseId = '${d['subcourseId'] ?? ''}';
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
        updatedAt: _parseDateTime(d['updatedAt']),
      ));
    }
    rows.sort((a, b) {
      final au = a.updatedAt, bu = b.updatedAt;
      if (au != null && bu != null) return bu.compareTo(au);
      if (au != null) return -1;
      if (bu != null) return 1;
      return a.chapterId.compareTo(b.chapterId);
    });
    // Resolve real chapter/unit names from the cached course catalogue
    // (the same 3-min cached fetches the chapters screen uses — no new
    // network layer, no read waterfall). Falls back to raw ids.
    await _attachNames(user.uid, courseId, subcourseId, rows);
    return _AnalyticsData(rows: rows);
  }

  /// Maps canonical chapter/unit ids to their catalogue titles. Only runs
  /// when a subject scope is known (the only way this page is opened).
  /// Everything is best-effort: any failure leaves the raw ids in place
  /// and never breaks the page.
  Future<void> _attachNames(String uid, String courseId, String subcourseId,
      List<_ChapterStat> rows) async {
    final subject = widget.subjectSlug;
    if (subject == null || subject.isEmpty || rows.isEmpty) return;
    try {
      var course = courseId;
      var subcourse = subcourseId;
      if (course.isEmpty || subcourse.isEmpty) {
        final scope = await fetchCourseScope(uid);
        if (course.isEmpty) course = scope['courseId'] ?? '';
        if (subcourse.isEmpty) subcourse = scope['subcourseId'] ?? '';
      }
      if (course.isEmpty || subcourse.isEmpty) return;
      Future<List<Map<String, dynamic>>> safe(
          Future<List<Map<String, dynamic>>> Function() f) async {
        try {
          return await f();
        } catch (_) {
          return [];
        }
      }
      final hasUnit = widget.unitId != null && widget.unitId!.isNotEmpty;
      final results = await Future.wait([
        safe(() => fetchSubjectChapters(course, subcourse, subject)),
        safe(() => fetchSubjectUnits(course, subcourse, subject)),
        if (hasUnit)
          safe(() => fetchUnitChapters(
              course, subcourse, subject, widget.unitId!)),
      ]);
      final chapterNames = <String, String>{};
      void addChapters(List<Map<String, dynamic>> list) {
        for (final c in list) {
          final key = canonicalCatalogSlug('${c['id']}');
          final name = '${c['name'] ?? ''}'.trim();
          if (key.isNotEmpty &&
              name.isNotEmpty &&
              name != 'Chapter') {
            chapterNames.putIfAbsent(key, () => name);
          }
        }
      }
      addChapters(results[0]);
      if (results.length > 2) addChapters(results[2]);
      // "All" view of a unit-structured subject: rows can belong to ANY
      // unit, but fetchSubjectChapters only returns direct (unit-less)
      // chapters and fetchUnitChapters above only ran for a selected unit.
      // Resolve names from every unit's chapters so cards show real titles
      // instead of raw ids like `surveying-1-2`. The per-unit fetches are
      // the same 3-min cached calls the units screen fans out — concurrent,
      // not a waterfall.
      if (!hasUnit) {
        final units = results[1];
        if (units.isNotEmpty) {
          final perUnit = await Future.wait(units.map((u) =>
              safe(() => fetchUnitChapters(
                  course, subcourse, subject, '${u['id']}'))));
          for (final list in perUnit) {
            addChapters(list);
          }
        }
      }
      final unitNames = <String, String>{};
      for (final u in results[1]) {
        final key = canonicalCatalogSlug('${u['id']}');
        final name = '${u['name'] ?? ''}'.trim();
        if (key.isNotEmpty && name.isNotEmpty && name != 'Unit') {
          unitNames.putIfAbsent(key, () => name);
        }
      }
      for (final r in rows) {
        r.chapterName =
            chapterNames[canonicalCatalogSlug(r.chapterId)];
        if (r.unitId != null && r.unitId!.isNotEmpty) {
          r.unitName = unitNames[canonicalCatalogSlug(r.unitId!)];
        }
      }
    } catch (_) {
      // Names are a nicety — the ids stay as fallback.
    }
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
                      // The window summary and the chart both depend on the
                      // selected tab: AnimatedSwitcher cross-fades/slides
                      // them on tab change (finite one-shot, 300ms).
                      StaggerEntrance(
                        delayMs: 90,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.05, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey('window$_tab'),
                            child: _windowCard(context, data),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      StaggerEntrance(
                        delayMs: 120,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.05, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey('weekly$_tab'),
                            child: _weeklyCard(context, data),
                          ),
                        ),
                      ),
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
  /// honest about what the window measures. Premium look: three stat
  /// tiles with icons and colored numbers, plus the honest footnote.
  Widget _windowCard(BuildContext context, _AnalyticsData data) {
    final rows = _windowRows(data.rows);
    final attempted = rows.fold(0, (a, r) => a + r.attempted);
    final correct = rows.fold(0, (a, r) => a + r.correct);
    final accuracy =
        attempted == 0 ? null : (correct / attempted * 100).round();
    final scheme = Theme.of(context).colorScheme;
    final subtle = scheme.onSurface.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
          Text(
            'Active $_windowPhrase',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: subtle,
                letterSpacing: 0.4),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _windowTile(
                context,
                icon: Icons.quiz_outlined,
                value: '${rows.length}',
                label: 'Chapters',
                accent: const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 8),
              _windowTile(
                context,
                icon: Icons.checklist_rounded,
                value: '$attempted',
                label: 'Questions',
                accent: const Color(0xFF059669),
              ),
              const SizedBox(width: 8),
              _windowTile(
                context,
                icon: Icons.track_changes_rounded,
                value: accuracy == null ? '—' : '$accuracy%',
                label: 'Accuracy',
                accent: const Color(0xFFD97706),
              ),
            ],
          ),
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

  Widget _windowTile(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: scheme.brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ activity chart
  /// Chapters active per bucket, from each doc's last-activity date.
  /// The buckets follow the selected tab so every tab switch shows real
  /// movement (and the AnimatedSwitcher has something to flow between):
  /// - Today: 6 buckets of 4 hours.
  /// - Last 7 days: one bucket per day.
  /// - All time: one bucket per week over the last 7 weeks (we only track
  ///   each chapter's LAST activity date, so a true all-time per-day chart
  ///   would be mostly zeros — the subtitle says what it shows).
  Widget _weeklyCard(BuildContext context, _AnalyticsData data) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    late final List<String> labels;
    late final List<String> sublabels;
    late final List<int> counts;
    late final int highlight;
    late final String subtitle;
    late final String title;

    if (_tab == 0) {
      title = 'Chapters active per 4 hours';
      subtitle = 'By last activity — today';
      labels = const ['12a', '4a', '8a', '12p', '4p', '8p'];
      sublabels = const ['', '', '', '', '', ''];
      counts = List.filled(6, 0);
      for (final r in data.rows) {
        final u = r.updatedAt;
        if (u == null || !_sameDay(u, now)) continue;
        counts[(u.hour ~/ 4).clamp(0, 5)]++;
      }
      highlight = (now.hour ~/ 4).clamp(0, 5);
    } else if (_tab == 1) {
      title = 'Chapters active per day';
      subtitle = 'By last activity — last 7 days';
      final days =
          List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
      labels = [for (final d in days) letters[d.weekday - 1]];
      sublabels = [for (final d in days) '${d.day}'];
      counts = [
        for (final d in days)
          data.rows
              .where((r) =>
                  r.updatedAt != null && _sameDay(r.updatedAt!, d))
              .length
      ];
      highlight = 6;
    } else {
      title = 'Chapters active per week';
      subtitle = 'By last activity — last 7 weeks';
      final starts =
          List.generate(7, (i) => today.subtract(Duration(days: 48 - i * 7)));
      labels = [for (final s in starts) '${s.day}'];
      sublabels = [for (final s in starts) months[s.month - 1]];
      counts = [
        for (final s in starts)
          data.rows
              .where((r) =>
                  r.updatedAt != null &&
                  !r.updatedAt!.isBefore(s) &&
                  r.updatedAt!.isBefore(s.add(const Duration(days: 7))))
              .length
      ];
      highlight = 6;
    }

    final max = counts.fold(0, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    final gridColor = scheme.onSurface.withValues(alpha: 0.07);
    const barH = 84.0;

    Widget bar(int i) {
      final count = counts[i];
      final isHi = i == highlight;
      final frac = max == 0 ? 0.0 : count / max;
      final h = count == 0 ? 5.0 : (16 + (barH - 16) * frac);
      return Container(
        width: 24,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color:
              count == 0 ? scheme.surfaceContainerHighest : null,
          gradient: count == 0
              ? null
              : LinearGradient(
                  colors: isHi
                      ? const [Color(0xFFFBBF24), Color(0xFFD97706)]
                      : const [Color(0xFF60A5FA), Color(0xFF1D4ED8)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
          boxShadow: count == 0
              ? null
              : [
                  BoxShadow(
                    color: (isHi
                            ? const Color(0xFFD97706)
                            : const Color(0xFF1D4ED8))
                        .withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
      );
    }

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
          Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 10),
          // Value labels.
          Row(
            children: labels.asMap().entries.map((e) {
              final i = e.key;
              final isHi = i == highlight;
              return Expanded(
                child: Text(
                  '${counts[i]}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: counts[i] == 0
                        ? scheme.onSurface.withValues(alpha: 0.3)
                        : isHi
                            ? const Color(0xFFD97706)
                            : scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          // Bars over faint gridlines.
          SizedBox(
            height: barH,
            child: Stack(
              children: [
                Positioned(
                  top: barH / 3,
                  left: 0,
                  right: 0,
                  child: Container(height: 1, color: gridColor),
                ),
                Positioned(
                  top: barH * 2 / 3,
                  left: 0,
                  right: 0,
                  child: Container(height: 1, color: gridColor),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                      height: 1,
                      color:
                          scheme.onSurface.withValues(alpha: 0.12)),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: labels.asMap().entries.map((e) {
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [bar(e.key)],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Day labels.
          Row(
            children: labels.asMap().entries.map((e) {
              final i = e.key;
              final isHi = i == highlight;
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: isHi
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isHi
                              ? const Color(0xFF1D4ED8)
                              : scheme.onSurface
                                  .withValues(alpha: 0.55)),
                    ),
                    if (sublabels[i].isNotEmpty)
                      Text(sublabels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 9,
                              color: scheme.onSurface
                                  .withValues(alpha: 0.45))),
                  ],
                ),
              );
            }).toList(),
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
                        Text(r.chapterName ?? r.chapterId,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (r.unitId != null && r.unitId!.isNotEmpty)
                          Text('Unit: ${r.unitName ?? r.unitId}',
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

  /// Resolved from the cached course catalogue after load; null (or
  /// unset) means the UI falls back to the raw ids.
  String? chapterName;
  String? unitName;

  _ChapterStat({
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
