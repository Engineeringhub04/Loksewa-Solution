import 'dart:async';
import 'dart:math';


import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/analytics/analytics_derive.dart';
import 'package:loksewa_solution/services/analytics/analytics_strings.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/analytics/analytics_series.dart';
import 'package:loksewa_solution/services/analytics/analytics_store.dart';
import 'package:loksewa_solution/services/analytics/analytics_types.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/main_leaderboard.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/analytics/analytics_hero.dart';
import 'package:loksewa_solution/widgets/analytics/analytics_shared.dart';
import 'package:loksewa_solution/widgets/analytics/cohort_strip.dart';
import 'package:loksewa_solution/widgets/analytics/insight_card.dart';
import 'package:loksewa_solution/widgets/analytics/method_footer.dart';
import 'package:loksewa_solution/widgets/analytics/milestone_list.dart';
import 'package:loksewa_solution/widgets/analytics/range_switcher.dart';
import 'package:loksewa_solution/widgets/analytics/subcourse_picker.dart';
import 'package:loksewa_solution/widgets/analytics/week_strip.dart';
import 'package:loksewa_solution/widgets/charts/bar_chart.dart';
import 'package:loksewa_solution/widgets/charts/chart_card.dart';
import 'package:loksewa_solution/widgets/charts/chart_math.dart';
import 'package:loksewa_solution/widgets/charts/donut_chart.dart';
import 'package:loksewa_solution/widgets/charts/heatmap.dart';
import 'package:loksewa_solution/widgets/charts/line_area_chart.dart';
import 'package:loksewa_solution/widgets/charts/radar_chart.dart';
import 'package:loksewa_solution/widgets/charts/stat_tile.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
import 'package:loksewa_solution/widgets/stagger_entrance.dart';
import 'package:loksewa_solution/widgets/subpage_header.dart';

/// Which course the numbers on screen belong to, resolved from the user doc
/// plus the course catalogue (never a raw id shown to the user).
class AnalyticsIdentity {
  const AnalyticsIdentity({
    required this.courseId,
    required this.subcourseId,
    required this.courseName,
    required this.subcourseName,
  });

  final String courseId;
  final String subcourseId;
  final String courseName;
  final String subcourseName;
}

Future<AnalyticsIdentity> _defaultLoadIdentity(String uid) async {
  final idToken = await AuthService.getValidIdToken();
  final userDoc =
      await FirestoreRest.getDocument('users/$uid', idToken: idToken);
  final courseId = (userDoc?['courseId'] as String?) ?? '';
  final subcourseId = (userDoc?['subcourseId'] as String?) ?? '';
  var courseName = '';
  var subcourseName = '';
  if (courseId.isNotEmpty) {
    try {
      final course = await FirestoreRest.getDocument('app_courses/$courseId',
          idToken: idToken);
      courseName =
          ((course?['name'] ?? course?['nameNe']) as String?)?.trim() ?? '';
      if (subcourseId.isNotEmpty) {
        final subcourse = await FirestoreRest.getDocument(
            'app_courses/$courseId/subcourses/$subcourseId',
            idToken: idToken);
        subcourseName =
            ((subcourse?['name'] ?? subcourse?['nameNe']) as String?)?.trim() ??
                '';
        if (subcourseName.isEmpty) {
          final legacy = await FirestoreRest.getDocument(
              'app_subcourses/$subcourseId',
              idToken: idToken);
          subcourseName =
              ((legacy?['name'] ?? legacy?['nameNe']) as String?)?.trim() ?? '';
        }
      }
    } catch (_) {
      // Names are decoration; a failed lookup must not take the page down.
    }
  }
  return AnalyticsIdentity(
    courseId: courseId,
    subcourseId: subcourseId,
    courseName: courseName,
    subcourseName: subcourseName,
  );
}

class _AnalyticsPayload {
  const _AnalyticsPayload({
    required this.document,
    required this.available,
    required this.names,
    required this.fetchedAt,
    required this.canonical,
  });

  final AnalyticsDocument? document;
  final List<AnalyticsSubcourseRow> available;

  /// subcourseId → display name. Empty when there is nothing to switch between.
  final Map<String, String> names;

  /// When this payload was built — §15 has to say how old the numbers are.
  final int fetchedAt;

  /// Canonical live stats (computeMainLeaderboardScore + 50pt signup bonus):
  /// the single source of truth for the hero's points and coverage percent.
  /// Null in degraded mode, when the hero falls back to the snapshot's
  /// numbers.
  final CanonicalStats? canonical;
}

/// In-memory cohort board cache: 10 minutes per subcourse, shared with the
/// leaderboard screen's reads. Lives here (not in analytics_store.dart, which
/// is a frozen read-only layer) so a tap-to-load never re-buys 300 reads.
class _BoardCacheEntry {
  const _BoardCacheEntry(this.rows, this.at);

  final List<MainLeaderboardRow> rows;
  final int at;
}

const int _boardTtlMs = 10 * 60 * 1000;
final Map<String, _BoardCacheEntry> _boardCache = {};

/// Longest heatmap history drawn — 26 weeks is what fits a phone comfortably.
const int _heatmapMaxDays = 182;

/// Analytics — the private, per-user view of how a subcourse is actually going.
///
/// Mirrors app/analytics.tsx section for section (15 sections, same order):
/// who you are and how you're doing (hero, range, KPIs), how that changed over
/// time (trend, heatmap), what you're made of (radar, effort ring), how hard
/// you're working (points breakdown, daily effort), what to do next (accuracy
/// by source, insights), where you stand among others (consistency, cohort),
/// what you're aiming at (milestones), and how any of it was calculated
/// (method footer).
///
/// PRIVATE BY DESIGN: everything is read from `users/{uid}/app_analytics`,
/// which no other user can see.
///
/// [debugUid], [fetchDocument], [listSubcourses], [fetchBoard],
/// [loadIdentity] and [loadCanonical] are seams for widget tests — the
/// production defaults hit the real services.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    this.debugUid,
    this.fetchDocument = fetchAnalyticsDocument,
    this.listSubcourses = listAnalyticsSubcourses,
    this.fetchBoard = fetchMainLeaderboard,
    this.loadIdentity,
    this.loadCanonical,
  });

  final String? debugUid;
  final Future<AnalyticsDocument?> Function(String uid, String subcourseId)
      fetchDocument;
  final Future<List<AnalyticsSubcourseRow>> Function(String uid) listSubcourses;
  final Future<List<MainLeaderboardRow>> Function(String subcourseId)
      fetchBoard;
  final Future<AnalyticsIdentity> Function(String uid)? loadIdentity;

  /// Canonical-stats loader (computeMainLeaderboardScore + 50pt signup
  /// bonus). The hero's points and coverage percent come from here, NOT the
  /// once-a-day snapshot — the consistency rule documented in
  /// main_leaderboard.dart. Null selects the production default, which never
  /// throws: a null result puts the hero in degraded mode (snapshot fallback).
  final Future<CanonicalStats?> Function(
      String uid, String courseId, String subcourseId)? loadCanonical;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsRange _range = AnalyticsRange.d30;
  String _chosenSubcourseId = '';
  bool _pickerOpen = false;
  String? _selectedDayKey;
  String? _selectedSlice;
  int? _selectedEffortDay;

  // §13 loads behind a tap. The board is up to 300 documents and most visits
  // never scroll that far, so it stays off the critical path.
  CohortFacts? _cohort;
  bool _cohortLoading = false;
  bool _cohortBusy = false;
  bool _cohortOpened = false;

  AnalyticsIdentity? _identity;
  _AnalyticsPayload? _payload;
  bool _loading = true;
  Object? _error;

  String get _uid => widget.debugUid ?? AuthService.currentUser?.uid ?? '';

  String get _subcourseId => _chosenSubcourseId.isNotEmpty
      ? _chosenSubcourseId
      : (_identity?.subcourseId ?? '');

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final uid = _uid;
    if (uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final identity =
          await (widget.loadIdentity ?? _defaultLoadIdentity)(uid);
      if (!mounted) return;
      setState(() => _identity = identity);
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  /// Production canonical-stats loader: refreshes the leaderboard aggregate
  /// when the publish throttle allows — but only with a loaded profile, so
  /// the public row is never written as "Anonymous". Never throws; a null
  /// result puts the hero in degraded mode (snapshot fallback).
  Future<CanonicalStats?> _defaultLoadCanonical(
      String uid, String courseId, String subcourseId) {
    final profile = ProfileStore.instance.profile;
    return loadCanonicalStats(
      uid: uid,
      courseId: courseId,
      subcourseId: subcourseId,
      name: profile?.name ?? '',
      photoURL: profile?.photoURL,
      isPro: profile != null && hasActivePremium(profile),
      allowRefresh: profile != null,
    );
  }

  Future<_AnalyticsPayload> _loadPayload(
      String uid, String subcourseId) async {
    final results = await Future.wait([
      widget.fetchDocument(uid, subcourseId),
      widget.listSubcourses(uid),
      (widget.loadCanonical ?? _defaultLoadCanonical)(
          uid, _identity?.courseId ?? '', subcourseId),
    ]);
    final document = results[0] as AnalyticsDocument?;
    final available = results[1] as List<AnalyticsSubcourseRow>;
    var canonical = results[2] as CanonicalStats?;
    if (canonical == null) {
      // One forced retry before giving up: the hero NEVER falls back to the
      // snapshot's fossil numbers (the "Analytics says 594" bug — the Flutter
      // app never writes snapshots, so the snapshot is a frozen React-era
      // value). resetMainLeaderboardThrottle makes the retry actually
      // recompute instead of hitting the throttle.
      try {
        resetMainLeaderboardThrottle(uid, subcourseId);
        canonical = await (widget.loadCanonical ?? _defaultLoadCanonical)(
            uid, _identity?.courseId ?? '', subcourseId);
      } catch (_) {}
    }
    return _AnalyticsPayload(
      document: document,
      available: available,
      names: await _resolveSubcourseNames(available),
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
      canonical: canonical,
    );
  }

  /// Display names for every subcourse with recorded history.
  ///
  /// Skipped entirely for a single subcourse: the picker is hidden in that
  /// case, so the extra course reads would buy nothing. A name that cannot be
  /// resolved falls back upstream — it must not take the page down with it.
  Future<Map<String, String>> _resolveSubcourseNames(
      List<AnalyticsSubcourseRow> rows) async {
    if (rows.length < 2) return {};
    final names = <String, String>{};
    final courseIds =
        rows.map((row) => row.courseId).where((id) => id.isNotEmpty).toSet();
    String token = '';
    try {
      token = await AuthService.getValidIdToken();
    } catch (_) {
      return names;
    }
    await Future.wait(courseIds.map((courseId) async {
      try {
        final docs = await FirestoreRest.listDocuments(
            'app_courses/$courseId/subcourses',
            idToken: token);
        for (final doc in docs) {
          final id = (doc['id'] as String?) ?? '';
          if (id.isEmpty) continue;
          final name =
              ((doc['name'] ?? doc['nameNe']) as String?)?.trim() ?? '';
          if (name.isNotEmpty) names[id] = name;
        }
      } catch (_) {
        // Falls back upstream.
      }
    }));
    return names;
  }

  Future<void> _refreshData() async {
    final uid = _uid;
    final subcourseId = _subcourseId;
    if (uid.isEmpty || subcourseId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final payload = await _loadPayload(uid, subcourseId);
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_payload == null) _error = e;
      });
    }
  }

  /// Header refresh button and pull-to-refresh share one path.
  ///
  /// The board cache is always cleared — an explicit refresh has to mean
  /// something — but it must not silently buy 300 reads for a section the
  /// user never opened, so only an already-open section refetches.
  Future<void> _reload() async {
    _boardCache.remove(_subcourseId);
    await _refreshData();
    if (_cohortOpened) await _loadCohort();
  }

  Future<List<MainLeaderboardRow>> _cachedBoard(String subcourseId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hit = _boardCache[subcourseId];
    if (hit != null && now - hit.at < _boardTtlMs) return hit.rows;
    final rows = await widget.fetchBoard(subcourseId);
    _boardCache[subcourseId] = _BoardCacheEntry(rows, now);
    return rows;
  }

  Future<void> _loadCohort() async {
    if (_cohortBusy) return;
    final uid = _uid;
    final subcourseId = _subcourseId;
    if (uid.isEmpty || subcourseId.isEmpty) return;
    _cohortBusy = true;
    _cohortOpened = true;
    setState(() => _cohortLoading = true);
    try {
      final rows = await _cachedBoard(subcourseId);
      final facts = cohortFacts(
        rows
            .map((row) =>
                CohortRow(uid: row.uid, points: row.points, percent: row.percent))
            .toList(),
        uid,
      );
      if (!mounted) return;
      setState(() => _cohort = facts);
    } catch (_) {
      // A failed board read leaves the section in its prompt state rather than
      // showing a broken rank. Nothing else on the page depends on it.
      if (!mounted) return;
      setState(() => _cohort = null);
    } finally {
      _cohortBusy = false;
      if (mounted) setState(() => _cohortLoading = false);
    }
  }

  void _onSubcourseSelected(String next) {
    setState(() {
      _chosenSubcourseId = next;
      _pickerOpen = false;
      // Selections belong to the subcourse that was on screen when they were
      // made; carrying them across would highlight a day or slice that the
      // new subcourse may not even have.
      _selectedDayKey = null;
      _selectedSlice = null;
      _selectedEffortDay = null;
      // The cohort belongs to ONE subcourse's board. Carrying a rank across
      // would show the user a position they do not hold.
      _cohort = null;
      _cohortOpened = false;
    });
    _refreshData();
  }

  String _rangeLabel(AnalyticsRange range) {
    if (range == AnalyticsRange.all) return AnalyticsStrings.rangeAllLabel;
    return AnalyticsStrings.rangeDaysLabel(range.days!);
  }

  /// Chart/day labels follow the app language, like the React screen's `lang`.
  AnalyticsLanguage get _chartLang =>
      AppLanguage.isNepali ? AnalyticsLanguage.ne : AnalyticsLanguage.en;

  List<SubcourseOption> _subcourseOptions() {
    final payload = _payload;
    if (payload == null) return [];
    final enrolledId = _identity?.subcourseId ?? '';
    return payload.available.map((row) {
      // Never the raw id: an unresolved name falls back to the enrolled
      // subcourse label, then to a generic one.
      var name = payload.names[row.subcourseId] ?? '';
      if (name.isEmpty && row.subcourseId == enrolledId) {
        final fallback = _identity?.subcourseName ?? '';
        name = fallback.isNotEmpty
            ? fallback
            : (_identity?.courseName ?? '');
      }
      if (name.isEmpty) name = AnalyticsStrings.pickerUnnamed;
      return SubcourseOption(
        subcourseId: row.subcourseId,
        courseId: row.courseId,
        name: name,
        percent: row.percent,
        points: row.points,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);

    final header = SubpageHeader(
      title: AnalyticsStrings.title,
      actions: [
        GestureDetector(
          onTap: _reload,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.refresh, size: 19, color: Colors.white),
          ),
        ),
      ],
      showThemeToggle: true,
    );

    Widget body;
    final uid = _uid;
    final subcourseId = _subcourseId;

    if (_loading && _payload == null && _identity == null) {
      body = PreloadingWidget(
          tinted: false,
          label: AnalyticsStrings.loading,
          hint: AnalyticsStrings.loadingHint);
    } else if (_error != null && _payload == null) {
      // Checked before the course gate: a failed identity load leaves the
      // subcourse unknown, which must not masquerade as "choose a course".
      body = _Gate(
        icon: Icons.error_outline,
        title: AnalyticsStrings.errorTitle,
        description: AnalyticsStrings.errorDescription,
        onRetry: () {
          setState(() {
            _error = null;
            _loading = true;
          });
          _boot();
        },
      );
    } else if (uid.isEmpty || subcourseId.isEmpty) {
      body = _Gate(
        icon: Icons.school_outlined,
        title: AnalyticsStrings.title,
        description: AnalyticsStrings.noCourse,
        onRetry: null,
      );
    } else if (_payload != null && _payload!.document == null) {
      // No document means the once-a-day snapshot has never run for this
      // subcourse — the state a brand-new user is in, not an error.
      body = _Gate(
        icon: Icons.analytics_outlined,
        title: AnalyticsStrings.emptyTitle,
        description: AnalyticsStrings.emptyDescription,
        onRetry: _reload,
      );
    } else if (_payload != null && _payload!.canonical == null) {
      // The live aggregate could not be computed or read (even after one
      // forced retry). The hero shows an honest retry gate — NEVER the
      // snapshot's fossil points/percent, which is the "Analytics says 594
      // while the profile says much more" bug.
      body = _Gate(
        icon: Icons.error_outline,
        title: AnalyticsStrings.errorTitle,
        description: AnalyticsStrings.errorDescription,
        onRetry: _reload,
      );
    } else if (_payload?.document != null) {
      body = _content(context, colors, _payload!.document!);
    } else {
      body = PreloadingWidget(
          tinted: false,
          label: AnalyticsStrings.loading,
          hint: AnalyticsStrings.loadingHint);
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          header,
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _content(
      BuildContext context, ExpoPalette colors, AnalyticsDocument document) {
    final points = buildAnalyticsSeries(document, _range);
    final previousPoints = previousPeriodSeries(document, _range);

    /// Recorded days only — the sparklines and window totals are built from these.
    final observedPoints = points.where((point) => !point.seeded).toList();

    final summary = summarise(points);
    final previousSummary = summarise(previousPoints);
    final sourceStats = buildSourceStats(points);
    final latest = latestBucket(points);
    final seededCount = leadingSeededCount(points);

    final streak =
        computeAnalyticsStreak(document.days, analyticsTodayKey());
    final facts = timeFacts(document.breakdown, latest);

    // "vs previous all time" is not a sentence, and there is no previous
    // period to compare an all-time window against — so the qualifier is
    // simply dropped.
    final comparisonLabel = _range == AnalyticsRange.all
        ? null
        : AnalyticsStrings.vsPrevious(_rangeLabel(_range));
    final trackingStarted = summary.observedDays <= 1;

    final subcourseOptions = _subcourseOptions();
    final switchable = subcourseOptions.length > 1;
    final activeOption = subcourseOptions.isNotEmpty
        ? subcourseOptions.where(
            (option) => option.subcourseId == _subcourseId,
          )
        : const <SubcourseOption>[];
    final activeOptionName = activeOption.isEmpty
        ? null
        : activeOption.first.name;

    // ---------- trend ----------
    final trendValues =
        points.map((point) => point.cumulative.pc.toDouble()).toList();
    final trendLabels = points.map((point) => dayLabel(point.key, _chartLang)).toList();
    // Headroom above the best observed value rather than a fixed 0-100 axis: a
    // learner sitting at 14% would otherwise read as a flat line along the floor.
    final trendMax =
        min(100.0, chartMaxFor(points, (point) => point.cumulative.pc, 10));

    // ---------- heatmap (observed-only; never draws days it can't vouch for) ----------
    final allSeries = buildAnalyticsSeries(document, AnalyticsRange.all);
    final observedSeries =
        allSeries.where((point) => !point.seeded).toList();
    final heatmapSource = observedSeries.length > _heatmapMaxDays
        ? observedSeries.sublist(observedSeries.length - _heatmapMaxDays)
        : observedSeries;
    final heatmapDays = heatmapSource
        .map((point) =>
            HeatmapDay(key: point.key, value: effortOf(point).toDouble()))
        .toList();
    HeatmapDay? selectedDay;
    if (_selectedDayKey != null) {
      for (final day in heatmapDays) {
        if (day.key == _selectedDayKey) {
          selectedDay = day;
          break;
        }
      }
    }

    // ---------- radar ----------
    final radarAxes = sourceStats
        .map((stat) => RadarAxis(
              key: stat.key.name,
              label: analyticsSourceLabel(stat.key),
              value: stat.accuracy.toDouble(),
              untouched: !stat.touched,
            ))
        .toList();
    final touchedStats = sourceStats.where((stat) => stat.touched).toList();
    final strongest = touchedStats.isEmpty
        ? null
        : touchedStats.reduce(
            (best, stat) => stat.accuracy > best.accuracy ? stat : best);

    // ---------- effort ring ----------
    // The ring shows volume of work per source, not study time per feature:
    // the app measures total foreground seconds and the seconds spent on
    // activity-progress records, and nothing else — splitting a single total
    // six ways would be invention. The two real time figures moved into the
    // footer.
    final windowed = sourceStats.where((stat) => stat.volume > 0).toList();
    final lifetime = windowed.isEmpty;
    final effortRows =
        lifetime ? sourceStats.where((stat) => stat.lifetimeVolume > 0).toList() : windowed;
    final effortData = effortRows.map((stat) {
      final value = (lifetime ? stat.lifetimeVolume : stat.volume).toDouble();
      return DonutDatum(
        key: stat.key.name,
        label: analyticsSourceLabel(stat.key),
        value: value,
        color: analyticsHex(stat.color),
        display: compactNumber(value),
      );
    }).toList();
    final effortTotal =
        effortData.fold<double>(0, (sum, item) => sum + item.value);

    // ---------- canonical hero numbers ----------
    // THE CONSISTENCY RULE (see main_leaderboard.dart): the hero's points and
    // coverage percent come from the canonical live stats
    // (computeMainLeaderboardScore + 50pt signup bonus) — the same numbers
    // the Leaderboard board and the Profile stats card show. The snapshot's
    // copies (document.percent, latest.p) are frozen React-era fossils (the
    // Flutter app never writes snapshots) — using them is exactly the
    // "Analytics says 594, profile says much more" bug. A null canonical now
    // shows the retry gate in build(); this code defensively renders zeros
    // rather than fossils if it is ever reached without one.
    final canonical = _payload?.canonical;
    final heroPoints = canonical?.points ?? 0;
    final heroPercent = displayCoveragePercent(canonical?.percent ?? 0);

    // ---------- points breakdown ----------
    final breakdown = pointsBreakdown(
        canonical?.breakdown ?? const <String, dynamic>{}, heroPoints);
    final breakdownRows = breakdown.rows
        .map((row) => RankedBarRow(
              key: row.key.name,
              label: pointsRowLabel(row.labelKey),
              value: row.points.toDouble(),
              display: AnalyticsStrings.pointsRow(
                  pointsRowLabel(row.labelKey),
                  compactNumber(row.points.toDouble()),
                  row.share.round()),
              color: analyticsHex(row.color),
            ))
        .toList();

    // ---------- daily effort ----------
    final effortValues =
        points.map((point) => effortOf(point).toDouble()).toList();
    final effortLabels = points.map((point) => dayLabel(point.key, _chartLang)).toList();
    final effortMax = chartMaxFor(points, (point) => effortOf(point), 4);
    // Averaged over OBSERVED days only, and over active ones at that: a mean
    // dragged down by days the app was never opened is not "your typical day".
    final activeEfforts = observedPoints
        .map((point) => effortOf(point).toDouble())
        .where((value) => value > 0)
        .toList();
    final effortAverage = activeEfforts.isEmpty
        ? null
        : activeEfforts.reduce((a, b) => a + b) / activeEfforts.length;
    final weekendMarks = weekendIndices(points);
    final selectedEffort = _selectedEffortDay != null &&
            _selectedEffortDay! >= 0 &&
            _selectedEffortDay! < points.length
        ? points[_selectedEffortDay!]
        : null;

    // ---------- accuracy by source ----------
    // Fixed 0-100 scale, unlike the trend line: an accuracy bar rescaled to
    // the best performer would make 40% look like mastery simply because
    // nothing else was higher.
    final accuracyStats = sourceStats.toList()
      ..sort((a, b) {
        final touched = (b.touched ? 1 : 0).compareTo(a.touched ? 1 : 0);
        if (touched != 0) return touched;
        return b.accuracy.compareTo(a.accuracy);
      });
    final accuracyRows = accuracyStats
        .map((stat) => RankedBarRow(
              key: stat.key.name,
              label: analyticsSourceLabel(stat.key),
              value: stat.touched ? stat.accuracy.toDouble() : 0,
              display: stat.touched
                  ? formatPercent(stat.accuracy)
                  : AnalyticsStrings.accuracyUntouched,
              color: analyticsHex(stat.color),
              muted: !stat.touched,
            ))
        .toList();

    // ---------- insights ----------
    final insights = deriveInsights(sourceStats);

    // ---------- consistency ----------
    final weekDots = weekStrip(
        buildAnalyticsSeries(document, AnalyticsRange.all),
        analyticsTodayKey());
    final peakDay =
        bestWeekday(buildAnalyticsSeries(document, AnalyticsRange.all));

    // ---------- milestones ----------
    final milestones = buildMilestones(
      heroPoints,
      streak.current,
      summary.accuracy,
      facts.totalSeconds,
      MilestonePalette(
        points: colorToHex(colors.primary),
        streak: colorToHex(colors.warning),
        accuracy: colorToHex(colors.success),
        time: colorToHex(colors.info),
      ),
    );

    final sections = <Widget>[
      // ---------- 2. Hero ----------
      // The ring shows the SAME coverage percent as the profile stats card
      // and the leaderboard board: the canonical live computation
      // (computeMainLeaderboardScore + 50pt signup bonus) — NOT the
      // snapshot's document.percent, which goes stale the moment any
      // intraday activity happens. The old value was also never the
      // aggregate: it came from a different document and a different
      // pipeline, so the two rings could never agree. displayCoveragePercent
      // keeps the sub-10% one-decimal formatting the profile card uses, so
      // tiny values match there too. In degraded mode (canonical
      // unreadable) the hero falls back to the snapshot's numbers.
      AnalyticsHero(
        courseName: _identity?.courseName.isNotEmpty == true
            ? _identity!.courseName
            : AnalyticsStrings.heroFallbackCourse,
        subcourseName: activeOptionName ??
            (_identity?.subcourseName.isNotEmpty == true
                ? _identity!.subcourseName
                : AnalyticsStrings.pickerUnnamed),
        percent: heroPercent,
        points: heroPoints,
        streak: streak.current,
        activeDays: summary.activeDays,
        // Only present once §13 has been opened — the hero never pays for a
        // board read on its own.
        rank: _cohort?.rank,
        switchable: switchable,
        onPress: switchable ? () => setState(() => _pickerOpen = true) : null,
      ),

      // ---------- 3. Range switcher ----------
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RangeSwitcher(
            options: [
              RangeOption(value: AnalyticsRange.d7, label: AnalyticsStrings.range7d),
              RangeOption(value: AnalyticsRange.d30, label: AnalyticsStrings.range30d),
              RangeOption(value: AnalyticsRange.d90, label: AnalyticsStrings.range90d),
              RangeOption(value: AnalyticsRange.all, label: AnalyticsStrings.rangeAll),
            ],
            value: _range,
            onChange: (next) => setState(() => _range = next),
          ),
          const SizedBox(height: 6),
          Text(
            trackingStarted
                ? AnalyticsStrings.trackingStarted
                : AnalyticsStrings.rangeObserved(summary.observedDays),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ExpoType.caption,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),

      // ---------- 4. KPI tiles ----------
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.trending_up,
                  label: AnalyticsStrings.kpiAccuracy,
                  value: formatPercent(summary.accuracy),
                  accent: colors.primary,
                  // Percentage POINTS, not a relative change: accuracy is
                  // already a percentage, and "+12% of 60%" would mean two
                  // different things to two different readers.
                  delta: summary.accuracyStart != null
                      ? summary.accuracy - summary.accuracyStart!
                      : null,
                  deltaLabel: AnalyticsStrings.kpiSincePeriodStart,
                  trend: observedPoints
                      .map((point) => point.cumulative.pc.toDouble())
                      .toList(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: Icons.schedule_outlined,
                  label: AnalyticsStrings.kpiStudyTime,
                  value: formatDuration(summary.studySeconds.toDouble()),
                  accent: colors.info,
                  delta: percentChange(
                      summary.studySeconds, previousSummary.studySeconds),
                  deltaLabel: comparisonLabel,
                  trend: observedPoints
                      .map((point) => point.delta.s.toDouble() / 60)
                      .toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.checklist_outlined,
                  label: AnalyticsStrings.kpiActivities,
                  value: compactNumber(summary.activities.toDouble()),
                  accent: colors.success,
                  delta: percentChange(
                      summary.activities, previousSummary.activities),
                  deltaLabel: comparisonLabel,
                  trend: observedPoints
                      .map((point) => effortOf(point).toDouble())
                      .toList(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: Icons.calendar_today_outlined,
                  label: AnalyticsStrings.kpiActiveDays,
                  value: '${summary.activeDays}',
                  accent: colors.warning,
                  delta: percentChange(
                      summary.activeDays, previousSummary.activeDays),
                  deltaLabel: comparisonLabel,
                  trend: observedPoints
                      .map((point) => effortOf(point) > 0 ? 1.0 : 0.0)
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),

      // ---------- 5. Score trend ----------
      ChartCard(
        title: AnalyticsStrings.trendTitle,
        subtitle: AnalyticsStrings.trendSubtitle,
        height: 200,
        empty: points.length < 2,
        emptyLabel: AnalyticsStrings.trendEmpty,
        emptyIcon: Icons.analytics_outlined,
        footer: seededCount > 0
            ? _LegendRow(
                // A dashed swatch, matching exactly how the chart draws the
                // estimated stretch — a colour key the user can map back to
                // the line.
                leading: Container(
                  width: 16,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                          color: colors.textSecondary,
                          width: 2,
                          style: BorderStyle.solid),
                    ),
                  ),
                ),
                label: AnalyticsStrings.estimateNote(seededCount),
              )
            : null,
        child: LineAreaChart(
          values: trendValues,
          labels: trendLabels,
          color: colors.primary,
          height: 200,
          maxValue: trendMax,
          seededCount: seededCount,
          formatValue: (value) => '${value.round()}%',
          emptyLabel: AnalyticsStrings.trendEmpty,
        ),
      ),

      // ---------- 6. Activity heatmap ----------
      ChartCard(
        title: AnalyticsStrings.heatmapTitle,
        // The grid keeps its own full-history window regardless of the range
        // switcher: seven days of a contribution grid is one column, which
        // would say nothing at all.
        subtitle: heatmapDays.isNotEmpty ? AnalyticsStrings.heatmapSubtitle : null,
        height: 150,
        empty: heatmapDays.isEmpty,
        emptyLabel: AnalyticsStrings.heatmapEmpty,
        emptyIcon: Icons.grid_on_outlined,
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedDay != null) ...[
              _DayPill(
                dateLabel: fullDateLabel(selectedDay.key, _chartLang),
                valueLabel:
                    AnalyticsStrings.heatmapDayValue(selectedDay.value.round()),
              ),
              const SizedBox(height: ExpoSpacing.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    AnalyticsStrings.heatmapHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ExpoType.caption,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                HeatmapLegend(
                  color: colors.success,
                  lessLabel: AnalyticsStrings.heatmapLess,
                  moreLabel: AnalyticsStrings.heatmapMore,
                ),
              ],
            ),
          ],
        ),
        child: Heatmap(
          days: heatmapDays,
          color: colors.success,
          weekdayLabels: weekdayLabels(_chartLang),
          monthLabelFor: (key) => monthLabel(key, _chartLang),
          selectedKey: _selectedDayKey,
          onSelect: (day) => setState(() => _selectedDayKey =
              _selectedDayKey == day.key ? null : day.key),
          emptyLabel: AnalyticsStrings.heatmapEmpty,
        ),
      ),

      // ---------- 7. Skill radar ----------
      ChartCard(
        title: AnalyticsStrings.radarTitle,
        subtitle: AnalyticsStrings.radarSubtitle,
        height: 250,
        empty: latest == null,
        emptyLabel: AnalyticsStrings.radarEmpty,
        emptyIcon: Icons.hub_outlined,
        footer: strongest != null
            ? _LegendRow(
                leading: Icon(Icons.military_tech,
                    size: 14,
                    color: analyticsHex(strongest.color)),
                label: AnalyticsStrings.radarStrongest(
                    analyticsSourceLabel(strongest.key),
                    formatPercent(strongest.accuracy)),
              )
            : null,
        child: RadarChart(
          axes: radarAxes,
          color: colors.primary,
          maxValue: 100,
          emptyLabel: AnalyticsStrings.radarEmpty,
        ),
      ),

      // ---------- 8. Where effort goes ----------
      ChartCard(
        title: AnalyticsStrings.effortTitle,
        subtitle: lifetime
            ? AnalyticsStrings.effortSubtitleLifetime
            : AnalyticsStrings.effortSubtitle,
        height: 160,
        empty: effortTotal <= 0,
        emptyLabel: AnalyticsStrings.effortEmpty,
        emptyIcon: Icons.pie_chart_outline,
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FactRow(
                label: AnalyticsStrings.effortTotalTime,
                value: formatDuration(facts.totalSeconds.toDouble())),
            _FactRow(
                label: AnalyticsStrings.effortTrackedTime,
                value: formatDuration(facts.trackedSeconds.toDouble())),
            if (facts.sessions > 0)
              _FactRow(
                  label: AnalyticsStrings.effortAvgSession,
                  value: formatDuration(
                      facts.totalSeconds / facts.sessions)),
          ],
        ),
        child: DonutChart(
          data: effortData,
          centerValue: compactNumber(effortTotal),
          centerLabel: AnalyticsStrings.effortCenter,
          selectedKey: _selectedSlice,
          onSelect: (key) => setState(
              () => _selectedSlice = _selectedSlice == key ? null : key),
          emptyLabel: AnalyticsStrings.effortEmpty,
        ),
      ),

      // ---------- 9. Where the points came from ----------
      ChartCard(
        title: AnalyticsStrings.pointsTitle,
        subtitle: AnalyticsStrings.pointsSubtitle,
        height: max(120.0, breakdownRows.length * 44.0),
        empty: breakdownRows.isEmpty,
        emptyLabel: AnalyticsStrings.pointsEmpty,
        emptyIcon: Icons.local_offer_outlined,
        right: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(ExpoRadius.pill),
          ),
          child: Text(
            '${compactNumber(breakdown.total.toDouble())} ${AnalyticsStrings.pointsUnit}',
            style: TextStyle(
              fontSize: ExpoType.caption,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
        ),
        footer: breakdown.estimated
            ? _LegendRow(
                leading: Icon(Icons.info_outline,
                    size: 13, color: colors.textSecondary),
                label: AnalyticsStrings.pointsEstimateNote,
              )
            : null,
        child: RankedBars(
          rows: breakdownRows,
          color: colors.primary,
          emptyLabel: AnalyticsStrings.pointsEmpty,
        ),
      ),

      // ---------- 10. Daily effort ----------
      ChartCard(
        title: AnalyticsStrings.dailyTitle,
        subtitle: AnalyticsStrings.dailySubtitle,
        height: 190,
        empty: points.isEmpty,
        emptyLabel: AnalyticsStrings.dailyEmpty,
        emptyIcon: Icons.bar_chart_outlined,
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedEffort != null) ...[
              _DayPill(
                dateLabel: fullDateLabel(selectedEffort.key, _chartLang),
                valueLabel: selectedEffort.seeded
                    ? AnalyticsStrings.dailySeededDay
                    : AnalyticsStrings.dailyDayValue(effortOf(selectedEffort).round()),
              ),
              const SizedBox(height: ExpoSpacing.sm),
            ],
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: colors.warning,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AnalyticsStrings.dailyWeekendNote,
                    style: TextStyle(
                      fontSize: ExpoType.caption,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        child: BarChart(
          values: effortValues,
          labels: effortLabels,
          color: colors.primary,
          height: 190,
          maxValue: effortMax,
          averageValue: effortAverage,
          averageLabel: AnalyticsStrings.dailyAverage,
          accentIndices: weekendMarks,
          accentColor: colors.warning,
          seededCount: seededCount,
          selectedIndex: _selectedEffortDay,
          onSelect: (index) => setState(() => _selectedEffortDay =
              _selectedEffortDay == index ? null : index),
          formatValue: (value) => '${value.round()}',
          emptyLabel: AnalyticsStrings.dailyEmpty,
        ),
      ),

      // ---------- 11. Accuracy by source ----------
      ChartCard(
        title: AnalyticsStrings.accuracyTitle,
        subtitle: AnalyticsStrings.accuracySubtitle,
        height: max(120.0, accuracyRows.length * 44.0),
        empty: latest == null,
        emptyLabel: AnalyticsStrings.accuracyEmpty,
        emptyIcon: Icons.speed,
        child: RankedBars(
          rows: accuracyRows,
          color: colors.primary,
          maxValue: 100,
          emptyLabel: AnalyticsStrings.accuracyEmpty,
        ),
      ),

      // ---------- 12. What to do next ----------
      if (insights.strength != null || insights.focus != null)
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AnalyticsStrings.insightTitle,
              style: TextStyle(
                fontSize: ExpoType.bodyLarge,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: ExpoSpacing.sm),
            if (insights.strength != null) ...[
              InsightCard(
                tone: InsightTone.strength,
                eyebrow: AnalyticsStrings.insightStrengthEyebrow,
                title: analyticsSourceLabel(insights.strength!.source),
                description: AnalyticsStrings.insightStrengthBody,
                value: formatPercent(insights.strength!.accuracy),
                accent: analyticsHex(insights.strength!.color),
                ctaLabel: AnalyticsStrings.insightKeepGoing,
                onPress: () => context
                    .push(analyticsSourceRoute(insights.strength!.source)),
              ),
              const SizedBox(height: ExpoSpacing.sm),
            ],
            if (insights.focus != null)
              InsightCard(
                tone: InsightTone.focus,
                eyebrow: AnalyticsStrings.insightFocusEyebrow,
                title: analyticsSourceLabel(insights.focus!.source),
                description: insights.focusUntouched
                    ? AnalyticsStrings.insightFocusUntouchedBody
                    : AnalyticsStrings.insightFocusBody,
                value: insights.focusUntouched
                    ? null
                    : formatPercent(insights.focus!.accuracy),
                accent: analyticsHex(insights.focus!.color),
                ctaLabel: AnalyticsStrings.insightPracticeNow,
                onPress: () => context
                    .push(analyticsSourceRoute(insights.focus!.source)),
              ),
          ],
        ),

      // ---------- 13. Consistency ----------
      ChartCard(
        title: AnalyticsStrings.weekTitle,
        subtitle: AnalyticsStrings.weekSubtitle,
        height: 72,
        empty: weekDots.isEmpty,
        emptyLabel: AnalyticsStrings.weekEmpty,
        emptyIcon: Icons.calendar_today_outlined,
        right: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department,
                size: 14, color: colors.warning),
            const SizedBox(width: 4),
            Text(
              AnalyticsStrings.weekStreakLabel,
              style: TextStyle(
                fontSize: ExpoType.caption,
                fontWeight: FontWeight.w700,
                color: colors.warning,
              ),
            ),
          ],
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (peakDay != null)
              _FactRow(
                label: AnalyticsStrings.weekPeakDay,
                value: weekdayLabels(_chartLang)[peakDay.weekday],
              ),
            if (streak.best > 0)
              _FactRow(
                label: AnalyticsStrings.weekBestStreak,
                value: AnalyticsStrings.dayStreak(streak.best),
              ),
          ],
        ),
        child: Center(
          child: WeekStrip(
            dots: weekDots,
            weekdayLabels: weekdayLabels(_chartLang),
            color: colors.primary,
          ),
        ),
      ),

      // ---------- 14. You vs the cohort ----------
      ChartCard(
        title: AnalyticsStrings.cohortTitle,
        subtitle: AnalyticsStrings.cohortSubtitle,
        height: _cohort != null ? 184 : 84,
        emptyIcon: Icons.people_outline,
        child: CohortStrip(
          facts: _cohort,
          loading: _cohortLoading,
          prompt: AnalyticsStrings.cohortPrompt,
          loadLabel: AnalyticsStrings.cohortLoad,
          emptyLabel: AnalyticsStrings.cohortEmpty,
          medianLabel: AnalyticsStrings.cohortMedian,
          youLabel: AnalyticsStrings.cohortYou,
          toNextLabel: AnalyticsStrings.cohortToNext,
          headline:
              _cohort?.rank != null ? AnalyticsStrings.cohortHeadline : null,
          subline: _cohort?.topPercent != null
              ? AnalyticsStrings.cohortSubline(_cohort!.topPercent!)
              : null,
          boardLabel: AnalyticsStrings.cohortBoardLabel,
          onLoad: _loadCohort,
          onOpenBoard: () => context.push('/leaderboard'),
        ),
      ),

      // ---------- 15. Milestones ----------
      ChartCard(
        title: AnalyticsStrings.milestoneTitle,
        subtitle: AnalyticsStrings.milestoneSubtitle,
        height: max(
            120.0, MilestoneList.preferredHeight(milestones.length)),
        empty: milestones.isEmpty,
        emptyLabel: AnalyticsStrings.milestoneEmpty,
        emptyIcon: Icons.flag_outlined,
        child: MilestoneList(
          milestones: milestones,
          labelFor: _milestoneLabel,
          doneLabel: AnalyticsStrings.milestoneDone,
        ),
      ),

      // ---------- 16. How this is calculated ----------
      MethodFooter(
        title: AnalyticsStrings.methodTitle,
        intro: AnalyticsStrings.methodIntro,
        weightsTitle: AnalyticsStrings.methodWeightsTitle,
        labelFor: pointsRowLabel,
        timeNote: (hours) => AnalyticsStrings.methodTimeNote(hours),
        estimateNote: AnalyticsStrings.methodEstimateNote,
        privacyNote: AnalyticsStrings.methodPrivacyNote,
        expandLabel: AnalyticsStrings.methodExpand,
        collapseLabel: AnalyticsStrings.methodCollapse,
        fetchedAt: _payload?.fetchedAt ??
            DateTime.now().millisecondsSinceEpoch,
        updatedLabel: (key, value) {
          switch (key) {
            case 'minutesAgo':
              return AnalyticsStrings.updatedMinutesAgo(value);
            case 'hoursAgo':
              return AnalyticsStrings.updatedHoursAgo(value);
            default:
              return AnalyticsStrings.updatedJustNow();
          }
        },
      ),
    ];

    final list = RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(ExpoSpacing.screenPadding),
        itemCount: sections.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: ExpoSpacing.md),
        // Staggered entrance, one step per section down the page: one-shot
        // slide+fade, capped at 8 steps × 60ms. Runs once on first build —
        // StaggerEntrance keeps its state across parent re-renders.
        itemBuilder: (context, index) => StaggerEntrance(
          delayMs: min(index, 8) * 60,
          child: sections[index],
        ),
      ),
    );

    return Stack(
      children: [
        list,
        SubcoursePicker(
          visible: _pickerOpen,
          onClose: () => setState(() => _pickerOpen = false),
          options: subcourseOptions,
          selectedId: _subcourseId,
          onSelect: _onSubcourseSelected,
        ),
      ],
    );
  }

  String _milestoneLabel(Milestone milestone) {
    switch (milestone.key) {
      case 'points':
        return AnalyticsStrings.milestonePoints(milestone.targetLabel);
      case 'streak':
        return AnalyticsStrings.milestoneStreak(milestone.targetLabel);
      case 'accuracy':
        return AnalyticsStrings.milestoneAccuracy(milestone.targetLabel);
      case 'hours':
        return AnalyticsStrings.milestoneHours(milestone.targetLabel);
      default:
        return milestone.key;
    }
  }
}

/// Honest empty/error gate: icon, title, description, optional retry.
class _Gate extends StatelessWidget {
  const _Gate({
    required this.icon,
    required this.title,
    required this.description,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: colors.textDisabled),
            const SizedBox(height: ExpoSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ExpoType.h3,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: ExpoSpacing.sm),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ExpoType.bodySmall,
                color: colors.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: ExpoSpacing.md),
              FilledButton(
                onPressed: onRetry,
                child: Text(AnalyticsStrings.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small "icon + label" footer line, e.g. the dashed estimate swatch.
class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.leading, required this.label});

  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Row(
      children: [
        leading,
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: ExpoType.caption,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Label ......... value" footer line.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ExpoType.caption,
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ExpoType.caption,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The tapped-day detail pill shared by the heatmap and the effort chart.
class _DayPill extends StatelessWidget {
  const _DayPill({required this.dateLabel, required this.valueLabel});

  final String dateLabel;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(ExpoRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 14, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ExpoType.caption,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            valueLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ExpoType.caption,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
