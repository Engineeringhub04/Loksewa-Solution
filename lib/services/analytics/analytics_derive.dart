// Everything that sits between a stored snapshot and what a chart draws.
//
// Deliberately free of Flutter, of the theme and of the chart widgets. The
// maths here is the part most likely to be quietly wrong — deltas across days
// with no snapshot, scales that one backfilled lump would flatten, accuracy
// read as a level rather than summed like a total — so it has to be runnable
// and checkable on its own.
//
// Dart port of
// LoksewasolutionApp/src/components/analytics/analyticsDerive.ts.
//
// ===== The one rule that governs this whole file =====
// SEEDED DAYS HAVE NO PER-DAY MEANING. The backfill attributes every untimed
// source (practice, reading, GK/PM, study time) as a single lump to the
// earliest reconstructed day, because that is the only honest answer to "when
// did this happen?" — we do not know. Their CUMULATIVE values are trustworthy
// and are what the trend line plots; their DELTAS are an artefact. So every
// window total and every chart scale in this file is computed from observed
// days only.
import 'dart:math';

import '../main_leaderboard.dart';
import 'analytics_series.dart';
import 'analytics_types.dart';

// ---------- scoring mirrors ----------
//
// main_leaderboard.dart is the single source of truth for scoring, but its
// weights and helpers are private and that file is owned by another area of
// the app. These copies MUST stay in sync with it:
//   _percentWeights        ↔ _percentWeights in main_leaderboard.dart
//   _readingTargetUnits    ↔ _readingTargetUnits (200)
//   _timePoints            ↔ _timePoints (12/hr, capped at 240)

/// Weight of each source inside the ACCURACY average.
const Map<AnalyticsSourceKey, double> _percentWeights = {
  AnalyticsSourceKey.exam: 3,
  AnalyticsSourceKey.dailyTest: 2.5,
  AnalyticsSourceKey.practice: 2.5,
  AnalyticsSourceKey.qotd: 2,
  AnalyticsSourceKey.gkPm: 1.5,
  AnalyticsSourceKey.reading: 1,
};

const double _readingTargetUnits = 200;

const double _timePointsPerHour = 12;
const double _timePointsCap = 240;

double _timePoints(double foregroundSeconds) => min(
    _timePointsCap, (max(0, foregroundSeconds) / 3600) * _timePointsPerHour);

double _percentOf(double part, double whole) =>
    whole > 0 ? (part / whole) * 100 : 0;

// ---------- sources ----------

/// Canonical order. The radar plots its axes in this order and the donut lays
/// out its arcs in it, so keeping one array as the source of truth is what
/// stops two sections of the same page disagreeing about which colour means
/// what.
// ignore: constant_identifier_names
const List<AnalyticsSourceKey> ANALYTICS_SOURCES = [
  AnalyticsSourceKey.exam,
  AnalyticsSourceKey.dailyTest,
  AnalyticsSourceKey.practice,
  AnalyticsSourceKey.qotd,
  AnalyticsSourceKey.gkPm,
  AnalyticsSourceKey.reading,
];

class AnalyticsSourceMeta {
  /// A fixed hue, not a theme token. A legend colour has to mean the same
  /// thing in light and dark, and all six have to stay apart from one
  /// another; the theme palette offers neither guarantee.
  final String color;

  /// i18n key under `analytics.sources`.
  final String labelKey;

  const AnalyticsSourceMeta({required this.color, required this.labelKey});
}

// ignore: constant_identifier_names
const Map<AnalyticsSourceKey, AnalyticsSourceMeta> SOURCE_META = {
  AnalyticsSourceKey.exam:
      AnalyticsSourceMeta(color: '#6366F1', labelKey: 'analytics.sources.exam'),
  AnalyticsSourceKey.dailyTest: AnalyticsSourceMeta(
      color: '#0EA5E9', labelKey: 'analytics.sources.dailyTest'),
  AnalyticsSourceKey.practice: AnalyticsSourceMeta(
      color: '#10B981', labelKey: 'analytics.sources.practice'),
  AnalyticsSourceKey.qotd:
      AnalyticsSourceMeta(color: '#F59E0B', labelKey: 'analytics.sources.qotd'),
  AnalyticsSourceKey.gkPm:
      AnalyticsSourceMeta(color: '#A855F7', labelKey: 'analytics.sources.gkPm'),
  AnalyticsSourceKey.reading: AnalyticsSourceMeta(
      color: '#14B8A6', labelKey: 'analytics.sources.reading'),
};

/// Where a "go practise this" button sends the user.
///
/// Practice and reading point at the SUBJECT LIST rather than a deep practice
/// screen: those screens require course/subcourse/subject/chapter/unit params,
/// and pushing them bare lands the user on a broken screen. The subject list
/// is the real entry point to both flows.
// ignore: constant_identifier_names
const Map<AnalyticsSourceKey, String> SOURCE_ROUTES = {
  AnalyticsSourceKey.exam: '/(tabs)/exam',
  AnalyticsSourceKey.dailyTest: '/daily-test',
  AnalyticsSourceKey.practice: '/subjects',
  AnalyticsSourceKey.qotd: '/question-of-the-day',
  AnalyticsSourceKey.gkPm: '/additional-features/gk',
  AnalyticsSourceKey.reading: '/subjects',
};

/// How well the user is doing at one source, 0..100.
///
/// Reading has no right or wrong answer, so its "accuracy" is coverage against
/// the nominal target — the same substitution the leaderboard percent already
/// makes, reused here so the radar cannot disagree with the score it sits
/// under.
double sourceAccuracy(DayBucket bucket, AnalyticsSourceKey key) {
  switch (key) {
    case AnalyticsSourceKey.exam:
      return clampPercent(bucket.ep);
    case AnalyticsSourceKey.dailyTest:
      return clampPercent(bucket.dp);
    case AnalyticsSourceKey.practice:
      return clampPercent(_percentOf(bucket.tc.toDouble(), bucket.ta.toDouble()));
    case AnalyticsSourceKey.qotd:
      return clampPercent(_percentOf(bucket.qc.toDouble(), bucket.qa.toDouble()));
    case AnalyticsSourceKey.gkPm:
      return clampPercent(_percentOf(bucket.gc.toDouble(), bucket.ga.toDouble()));
    case AnalyticsSourceKey.reading:
      return clampPercent(_percentOf(bucket.rd.toDouble(), _readingTargetUnits));
  }
}

/// Attempts (or covered units, for reading) recorded in one bucket.
num sourceVolume(DayBucket bucket, AnalyticsSourceKey key) {
  switch (key) {
    case AnalyticsSourceKey.exam:
      return bucket.ea;
    case AnalyticsSourceKey.dailyTest:
      return bucket.da;
    case AnalyticsSourceKey.practice:
      return bucket.ta;
    case AnalyticsSourceKey.qotd:
      return bucket.qa;
    case AnalyticsSourceKey.gkPm:
      return bucket.ga;
    case AnalyticsSourceKey.reading:
      return bucket.rd;
  }
}

class SourceStat {
  final AnalyticsSourceKey key;
  final String color;

  /// 0..100, read off the newest snapshot — accuracy is a level, not a total.
  final double accuracy;

  /// Attempts inside the selected window, from observed days only.
  final num volume;

  /// Lifetime attempts, which is what decides "never touched".
  final num lifetimeVolume;

  /// False when the user has never used this source at all.
  final bool touched;

  const SourceStat({
    required this.key,
    required this.color,
    required this.accuracy,
    required this.volume,
    required this.lifetimeVolume,
    required this.touched,
  });
}

/// One row per source: current accuracy, volume in the window, lifetime volume.
///
/// A source at zero because it was never opened and a source at zero because
/// the user keeps getting it wrong are completely different messages, which is
/// why `touched` is carried separately rather than inferred from the number.
List<SourceStat> buildSourceStats(List<AnalyticsSeriesPoint> points) {
  final latest = latestBucket(points);
  final observed = points.where((point) => !point.seeded).toList();

  return ANALYTICS_SOURCES.map((key) {
    final lifetimeVolume = latest != null ? sourceVolume(latest, key) : 0;
    num volume = 0;
    for (final point in observed) {
      volume += sourceVolume(point.delta, key);
    }
    return SourceStat(
      key: key,
      color: SOURCE_META[key]!.color,
      accuracy: latest != null ? sourceAccuracy(latest, key) : 0,
      volume: volume,
      lifetimeVolume: lifetimeVolume,
      touched: lifetimeVolume > 0,
    );
  }).toList();
}

// ---------- window summary ----------

class RangeSummary {
  /// Seconds of app time recorded inside the window.
  final num studySeconds;

  /// Questions answered plus units covered inside the window.
  final num activities;

  /// Points earned inside the window.
  final num pointsEarned;

  /// Days inside the window that carry real work.
  final int activeDays;

  /// Latest weighted accuracy, 0..100. A level: read, never summed.
  final double accuracy;

  /// Accuracy on the first observed day of the window; null with nothing to compare.
  final double? accuracyStart;

  /// How many of the window's days were actually recorded rather than carried forward.
  final int observedDays;

  /// Lifetime figures, read off the newest snapshot.
  final num totalStudySeconds;
  final num totalPoints;
  final num totalActivities;

  const RangeSummary({
    this.studySeconds = 0,
    this.activities = 0,
    this.pointsEarned = 0,
    this.activeDays = 0,
    this.accuracy = 0,
    this.accuracyStart,
    this.observedDays = 0,
    this.totalStudySeconds = 0,
    this.totalPoints = 0,
    this.totalActivities = 0,
  });
}

RangeSummary summarise(List<AnalyticsSeriesPoint> points) {
  if (points.isEmpty) return const RangeSummary();

  final observed = points.where((point) => !point.seeded).toList();
  final latest = latestBucket(points);

  num studySeconds = 0;
  num activities = 0;
  num pointsEarned = 0;
  var activeDays = 0;
  var observedDays = 0;

  for (final point in observed) {
    if (point.observed) observedDays++;
    studySeconds += point.delta.s;
    pointsEarned += point.delta.p;
    final effort = effortOf(point);
    activities += effort;
    if (effort > 0) activeDays++;
  }

  // Compared against the first OBSERVED day, not the first day of the window:
  // an estimate makes a poor baseline for "how much did I improve".
  AnalyticsSeriesPoint? firstObserved;
  for (final point in observed) {
    if (point.observed) {
      firstObserved = point;
      break;
    }
  }
  final accuracyStart =
      firstObserved != null && observedDays > 1 ? firstObserved.cumulative.pc : null;

  return RangeSummary(
    studySeconds: studySeconds,
    activities: activities,
    pointsEarned: pointsEarned,
    activeDays: activeDays,
    accuracy: latest != null ? clampPercent(latest.pc) : 0,
    accuracyStart: accuracyStart,
    observedDays: observedDays,
    totalStudySeconds: latest?.s ?? 0,
    totalPoints: latest?.p ?? 0,
    totalActivities: latest != null ? totalActivitiesOf(latest) : 0,
  );
}

/// Relative change, as a percentage.
///
/// Returns null rather than Infinity or 100 when there is no baseline: "you
/// did 40 minutes last week and 40 this week" is a real comparison, "you did
/// nothing last week" is not, and dressing the second up as +100% would be a
/// lie the user would reasonably act on.
double? percentChange(num current, num previous) {
  final c = current.toDouble();
  final p = previous.toDouble();
  if (!c.isFinite || !p.isFinite) return null;
  if (p <= 0) return null;
  return ((c - p) / p) * 100;
}

// ---------- series → chart input ----------

/// Pulls one number per day out of the series.
List<num> seriesValues(
  List<AnalyticsSeriesPoint> points,
  num Function(AnalyticsSeriesPoint) pick,
) =>
    points.map(pick).toList();

/// How many days at the START of the window are reconstructed.
///
/// Charts draw exactly this many leading points dashed and dimmed. Counting
/// only the leading run (rather than every seeded day anywhere) is what lets a
/// chart split into two paths instead of needing per-point styling.
int leadingSeededCount(List<AnalyticsSeriesPoint> points) {
  var count = 0;
  for (final point in points) {
    if (!point.seeded) break;
    count++;
  }
  return count;
}

/// Rounds a maximum up to a readable value — 47 → 50, 230 → 250, 1.8 → 2.
///
/// Charts scaled to the exact data maximum put the tallest bar flush against
/// the top edge and produce axis labels like "47", which reads as noise. Kept
/// private here (rather than in widgets/charts/chart_math.dart) so the
/// analytics data layer never depends on the chart widgets layer.
double _niceMax(num value) {
  final v = value.toDouble();
  if (!v.isFinite || v <= 0) return 1;
  final magnitude = pow(10, (log(v) / ln10).floor()).toDouble();
  final normalized = v / magnitude;
  final step = normalized <= 1
      ? 1.0
      : normalized <= 2
          ? 2.0
          : normalized <= 2.5
              ? 2.5
              : normalized <= 5
                  ? 5.0
                  : 10.0;
  return step * magnitude;
}

/// A y-axis ceiling that the backfill lump cannot blow out.
///
/// The first seeded day absorbs every untimed source at once, so including it
/// would scale a 90-day chart to a spike that is not a real day's work and
/// press every genuine bar flat against the axis.
double chartMaxFor(
  List<AnalyticsSeriesPoint> points,
  num Function(AnalyticsSeriesPoint) pick, [
  double minimum = 1,
]) {
  final observed = points.where((point) => !point.seeded).toList();
  final source = observed.isNotEmpty ? observed : points;
  var peak = 0.0;
  for (final point in source) {
    final value = pick(point).toDouble();
    if (value.isFinite && value > peak) peak = value;
  }
  return _niceMax(max(peak, minimum));
}

/// Indices of Friday and Saturday — Nepal's weekend — for the effort chart tint.
List<int> weekendIndices(List<AnalyticsSeriesPoint> points) {
  final indices = <int>[];
  for (var index = 0; index < points.length; index++) {
    final weekday = weekdayOfKey(points[index].key);
    if (weekday == 5 || weekday == 6) indices.add(index);
  }
  return indices;
}

// ---------- points breakdown ----------

/// Neutral greys: neither is a learning source, and both must stay off the six hues.
const String _timeColor = '#64748B';
const String _bonusColor = '#94A3B8';

enum PointsRowKey {
  exam,
  dailyTest,
  practice,
  qotd,
  gkPm,
  reading,
  time,
  bonus,
}

AnalyticsSourceKey? _pointsRowSource(PointsRowKey key) {
  switch (key) {
    case PointsRowKey.exam:
      return AnalyticsSourceKey.exam;
    case PointsRowKey.dailyTest:
      return AnalyticsSourceKey.dailyTest;
    case PointsRowKey.practice:
      return AnalyticsSourceKey.practice;
    case PointsRowKey.qotd:
      return AnalyticsSourceKey.qotd;
    case PointsRowKey.gkPm:
      return AnalyticsSourceKey.gkPm;
    case PointsRowKey.reading:
      return AnalyticsSourceKey.reading;
    case PointsRowKey.time:
    case PointsRowKey.bonus:
      return null;
  }
}

class PointsRowMeta {
  final String color;
  final String labelKey;
  const PointsRowMeta({required this.color, required this.labelKey});
}

PointsRowMeta pointsRowMeta(PointsRowKey key) {
  final source = _pointsRowSource(key);
  if (source != null) {
    final meta = SOURCE_META[source]!;
    return PointsRowMeta(color: meta.color, labelKey: meta.labelKey);
  }
  switch (key) {
    case PointsRowKey.time:
      return const PointsRowMeta(
          color: _timeColor, labelKey: 'analytics.sources.time');
    case PointsRowKey.bonus:
      return const PointsRowMeta(
          color: _bonusColor, labelKey: 'analytics.sources.bonus');
    default:
      throw StateError('unreachable');
  }
}

class PointsRow {
  final PointsRowKey key;
  final String color;
  final String labelKey;
  final int points;

  /// Share of the total, 0..100.
  final double share;

  const PointsRow({
    required this.key,
    required this.color,
    required this.labelKey,
    required this.points,
    required this.share,
  });
}

class PointsBreakdown {
  final List<PointsRow> rows;
  final num total;

  /// True when the exam row had to be inferred rather than summed exactly.
  final bool estimated;

  const PointsBreakdown({
    required this.rows,
    required this.total,
    required this.estimated,
  });
}

/// Positive finite number, or 0. Mirrors the `num()` helper in the React
/// source, which clamps missing and negative values to zero.
double _posNum(dynamic value) {
  if (value is num && value.isFinite && value > 0) return value.toDouble();
  return 0;
}

Map<String, dynamic> _section(Map<String, dynamic>? breakdown, String name) {
  final value = breakdown?[name];
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

/// Where the PTS total actually came from, using the leaderboard's own
/// constants.
///
/// The point of this section is to stop the score being a magic number, so it
/// has to reconcile: the rows are made to add up to the total the hero shows
/// rather than to a figure only this card believes in.
///
/// Accuracy of each row, honestly:
/// - qotd, practice, gkPm, time — EXACT from the stored breakdown.
/// - dailyTest — EXACT. Its `averagePercent` is the mean over every attempt,
///   and points were `attempts × 6 + Σscore × 0.5`, so
///   `attempts × average × 0.5` reproduces Σscore exactly.
/// - reading — an UNDER-estimate. Read-mode completion bonuses were awarded
///   per completed record and the count of those records is not stored.
/// - exam — an UPPER bound. Points accrued per attempt
///   (`attempts × 10 + Σscore`) but the snapshot only keeps the average of
///   each set's BEST attempt, so Σscore is unrecoverable. It is exact when
///   every set was attempted once, and too high when a set was retried.
///
/// Since exam is the only row that can overshoot, any excess over the real
/// total is subtracted from exam alone — never spread across rows that are
/// already right — and floored at the attempt points, which are certain.
/// Whatever is left under the total becomes the "bonus" row, which is where
/// the unrecorded reading bonuses genuinely belong.
PointsBreakdown pointsBreakdown(
    Map<String, dynamic>? breakdown, num totalPoints) {
  if (breakdown == null) {
    return const PointsBreakdown(rows: [], total: 0, estimated: false);
  }

  final qotdSec = _section(breakdown, 'qotd');
  final examSec = _section(breakdown, 'exam');
  final dailySec = _section(breakdown, 'dailyTest');
  final practiceSec = _section(breakdown, 'practice');
  final gkPmSec = _section(breakdown, 'gkPm');
  final readingSec = _section(breakdown, 'reading');
  final usageSec = _section(breakdown, 'usage');

  final qotd = _posNum(qotdSec['attempts']) * LeaderboardPoints.qotdAttempt +
      _posNum(qotdSec['correct']) * LeaderboardPoints.qotdCorrect;

  final examAttempts = _posNum(examSec['attempts']);
  final examFloor = examAttempts * LeaderboardPoints.examAttempt;
  var exam = examFloor +
      examAttempts *
          clampPercent(examSec['averagePercent']) *
          LeaderboardPoints.examPerScorePoint;

  final dailyAttempts = _posNum(dailySec['attempts']);
  final dailyTest = dailyAttempts * LeaderboardPoints.dailyTestAttempt +
      dailyAttempts *
          clampPercent(dailySec['averagePercent']) *
          LeaderboardPoints.dailyTestPerScorePoint;

  final practice = _posNum(practiceSec['attempted']) * LeaderboardPoints.practiceAttempt +
      _posNum(practiceSec['correct']) * LeaderboardPoints.practiceCorrect +
      _posNum(practiceSec['chaptersCompleted']) * LeaderboardPoints.completionBonus;

  final gkPm = _posNum(gkPmSec['attempted']) * LeaderboardPoints.gkPmAttempt +
      _posNum(gkPmSec['correct']) * LeaderboardPoints.gkPmCorrect;

  final reading = _posNum(readingSec['questionsRead']) * LeaderboardPoints.readViewed +
      _posNum(readingSec['theoryCompleted']) * LeaderboardPoints.theoryCompleted +
      _posNum(readingSec['constitutionParts']) * LeaderboardPoints.constitutionRead;

  final time = _timePoints(_posNum(usageSec['foregroundSeconds']));

  final total = max(0, totalPoints.round());
  double sumOf() => qotd + exam + dailyTest + practice + gkPm + reading + time;

  if (total > 0 && sumOf() > total) {
    exam = max(examFloor, exam - (sumOf() - total));
  }

  final values = <PointsRowKey, double>{
    PointsRowKey.exam: exam,
    PointsRowKey.dailyTest: dailyTest,
    PointsRowKey.practice: practice,
    PointsRowKey.qotd: qotd,
    PointsRowKey.gkPm: gkPm,
    PointsRowKey.reading: reading,
    PointsRowKey.time: time,
    PointsRowKey.bonus: total > 0 ? max(0, total - sumOf()) : 0,
  };

  final denominator = total > 0 ? total.toDouble() : sumOf();
  final rows = values.entries
      // Sub-point slivers are noise, and a row reading "0 PTS" invites the
      // question of why it is there at all.
      .where((entry) => entry.value >= 1)
      .map((entry) {
    final meta = pointsRowMeta(entry.key);
    return PointsRow(
      key: entry.key,
      color: meta.color,
      labelKey: meta.labelKey,
      points: entry.value.round(),
      share: denominator > 0 ? (entry.value / denominator) * 100 : 0,
    );
  }).toList()
    ..sort((a, b) => b.points.compareTo(a.points));

  return PointsBreakdown(
      rows: rows, total: denominator, estimated: examAttempts > 0);
}

// ---------- strengths & focus ----------

class Insight {
  final AnalyticsSourceKey source;
  final String color;
  final String labelKey;
  final double accuracy;
  final String route;

  /// Weight this source carries inside the overall percentage.
  final double weight;

  const Insight({
    required this.source,
    required this.color,
    required this.labelKey,
    required this.accuracy,
    required this.route,
    required this.weight,
  });
}

class Insights {
  /// Best-performing touched source, or null when nothing has been touched.
  final Insight? strength;

  /// What to work on next. An untouched high-weight source outranks a weak
  /// one: a source at zero because it was never opened is a bigger, easier
  /// win than a source the user is already practising and getting 55% on.
  final Insight? focus;

  /// True when `focus` is untouched rather than merely weak.
  final bool focusUntouched;

  const Insights({
    required this.strength,
    required this.focus,
    required this.focusUntouched,
  });
}

/// Below this, an accuracy figure is noise rather than a verdict.
const int _meaningfulSample = 5;

Insight _toInsight(SourceStat stat) => Insight(
      source: stat.key,
      color: stat.color,
      labelKey: SOURCE_META[stat.key]!.labelKey,
      accuracy: stat.accuracy,
      route: SOURCE_ROUTES[stat.key]!,
      weight: _percentWeights[stat.key]!,
    );

Insights deriveInsights(List<SourceStat> stats) {
  final touched = stats.where((stat) => stat.touched).toList();

  Insight? strength;
  if (touched.isNotEmpty) {
    var best = touched.first;
    for (final stat in touched.skip(1)) {
      if (stat.accuracy > best.accuracy ||
          (stat.accuracy == best.accuracy &&
              _percentWeights[stat.key]! > _percentWeights[best.key]!)) {
        best = stat;
      }
    }
    strength = _toInsight(best);
  }

  // Untouched first, heaviest weight wins — that is the largest movement in
  // the overall percentage available for the least work.
  final untouched = stats.where((stat) => !stat.touched).toList();
  if (untouched.isNotEmpty) {
    var pick = untouched.first;
    for (final stat in untouched.skip(1)) {
      if (_percentWeights[stat.key]! > _percentWeights[pick.key]!) {
        pick = stat;
      }
    }
    return Insights(
        strength: strength, focus: _toInsight(pick), focusUntouched: true);
  }

  // Otherwise the weakest source with enough attempts to mean something.
  // Reading is excluded: it is coverage, not accuracy, so "you are bad at
  // reading" would be a category error.
  final weak = stats
      .where((stat) =>
          stat.key != AnalyticsSourceKey.reading &&
          stat.lifetimeVolume >= _meaningfulSample)
      .toList();
  if (weak.isEmpty) {
    return Insights(strength: strength, focus: null, focusUntouched: false);
  }

  var worst = weak.first;
  for (final stat in weak.skip(1)) {
    if (stat.accuracy < worst.accuracy) worst = stat;
  }
  // Nothing to fix — do not manufacture a weakness out of a strong
  // all-round run.
  if (strength != null && worst.key == strength.source) {
    return Insights(strength: strength, focus: null, focusUntouched: false);
  }
  return Insights(
      strength: strength, focus: _toInsight(worst), focusUntouched: false);
}

// ---------- consistency ----------

class WeekDot {
  final String key;
  final int weekday;
  final num activities;

  /// A snapshot exists for this day; false means we simply do not know.
  final bool recorded;
  final bool today;

  const WeekDot({
    required this.key,
    required this.weekday,
    required this.activities,
    required this.recorded,
    required this.today,
  });
}

/// The trailing seven days ending today, oldest first.
List<WeekDot> weekStrip(List<AnalyticsSeriesPoint> points, String todayKey) {
  final byKey = {for (final point in points) point.key: point};
  final dots = <WeekDot>[];
  for (var offset = 6; offset >= 0; offset--) {
    final key = addDayKey(todayKey, -offset);
    final point = byKey[key];
    dots.add(WeekDot(
      key: key,
      weekday: weekdayOfKey(key),
      // A seeded day's delta is a backfill artefact, so it contributes nothing.
      activities: point != null && !point.seeded ? effortOf(point) : 0,
      recorded: point?.observed ?? false,
      today: offset == 0,
    ));
  }
  return dots;
}

class WeekdayLoad {
  final int weekday;
  final num activities;

  const WeekdayLoad({required this.weekday, required this.activities});
}

/// The weekday the user actually gets work done on.
///
/// Seeded days are skipped outright — the backfill dumps everything untimed
/// onto one reconstructed date, which would crown whichever weekday that
/// happened to fall on and be completely meaningless.
WeekdayLoad? bestWeekday(List<AnalyticsSeriesPoint> points) {
  final totals = List<num>.filled(7, 0);
  var any = false;

  for (final point in points) {
    if (point.seeded) continue;
    final effort = effortOf(point);
    if (effort <= 0) continue;
    totals[weekdayOfKey(point.key)] += effort;
    any = true;
  }
  if (!any) return null;

  var best = 0;
  for (var index = 1; index < 7; index++) {
    if (totals[index] > totals[best]) best = index;
  }
  return WeekdayLoad(weekday: best, activities: totals[best]);
}

// ---------- cohort ----------

/// One row of an already ranking-ordered leaderboard board.
class CohortRow {
  final String uid;
  final num points;
  final num percent;

  const CohortRow({
    required this.uid,
    required this.points,
    required this.percent,
  });
}

class CohortFacts {
  /// 1-based, or null when the user has no published row yet.
  final int? rank;

  /// How many people are in this subcourse's board.
  final int size;

  /// "Top N%" — smaller is better. Null without a rank.
  final int? topPercent;
  final double medianPercent;
  final double medianPoints;

  /// The board leader's points — the axis every marker is placed against.
  final double topPoints;

  /// Where the user sits, 0..100 across the board's points range.
  final double? position;
  final num myPoints;
  final num myPercent;

  /// Points needed to pass the person directly above; null at the top.
  final double? pointsToNext;

  const CohortFacts({
    required this.rank,
    required this.size,
    required this.topPercent,
    required this.medianPercent,
    required this.medianPoints,
    required this.topPoints,
    required this.position,
    required this.myPoints,
    required this.myPercent,
    required this.pointsToNext,
  });
}

double _median(List<num> values) {
  if (values.isEmpty) return 0;
  final sorted = values.map((v) => v.toDouble()).toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// The user's standing in their subcourse, from an already-sorted board.
///
/// The board arrives in ranking order, so position is the index — recomputing
/// the comparison here would risk this section and the leaderboard screen
/// disagreeing about who is ahead.
CohortFacts cohortFacts(List<CohortRow> rows, String uid) {
  final size = rows.length;
  final index = uid.isEmpty ? -1 : rows.indexWhere((row) => row.uid == uid);
  final me = index >= 0 ? rows[index] : null;

  final points = rows.map((row) => row.points).toList();
  final best =
      points.isEmpty ? 0.0 : points.map((p) => p.toDouble()).reduce(max);

  return CohortFacts(
    rank: index >= 0 ? index + 1 : null,
    size: size,
    topPercent: index >= 0 && size > 0
        ? max(1, (((index + 1) / size) * 100).round())
        : null,
    medianPercent: _median(rows.map((row) => row.percent).toList()),
    medianPoints: _median(points),
    topPoints: best,
    position: me != null && best > 0
        ? clampPercent((me.points.toDouble() / best) * 100)
        : null,
    myPoints: me?.points ?? 0,
    myPercent: me?.percent ?? 0,
    pointsToNext: index > 0
        ? max(0, rows[index - 1].points.toDouble() - rows[index].points.toDouble())
        : null,
  );
}

// ---------- milestones ----------

class Milestone {
  final String key;
  final String icon;
  final String color;
  final double current;
  final double target;

  /// 0..100.
  final double progress;
  final bool done;

  /// Formatted for display; the raw numbers are rarely what should be shown.
  final String currentLabel;
  final String targetLabel;

  const Milestone({
    required this.key,
    required this.icon,
    required this.color,
    required this.current,
    required this.target,
    required this.progress,
    required this.done,
    required this.currentLabel,
    required this.targetLabel,
  });
}

class MilestonePalette {
  final String points;
  final String streak;
  final String accuracy;
  final String time;

  const MilestonePalette({
    required this.points,
    required this.streak,
    required this.accuracy,
    required this.time,
  });
}

/// Round numbers a learner recognises, rather than an arbitrary curve.
const List<int> _pointsTiers = [100, 250, 500, 1000, 2500, 5000, 10000, 25000];
const int _streakTarget = 7;
const int _accuracyTarget = 90;
const int _studyHoursTarget = 50;

int _nextTier(num value) {
  for (final tier in _pointsTiers) {
    if (value < tier) return tier;
  }
  // Past the last named tier, keep going in 25k steps rather than showing a
  // permanently completed bar.
  return ((value + 1) / 25000).ceil() * 25000;
}

List<Milestone> buildMilestones(
  num totalPoints,
  int currentStreak,
  num accuracy,
  num totalStudySeconds,
  MilestonePalette palette,
) {
  final hours = max(0, totalStudySeconds.toDouble()) / 3600;
  final tier = _nextTier(totalPoints);
  final accuracyValue = accuracy.toDouble();

  final rows = <Milestone>[
    Milestone(
      key: 'points',
      icon: 'trophy',
      color: palette.points,
      current: totalPoints.toDouble(),
      target: tier.toDouble(),
      progress: _percentOf(totalPoints.toDouble(), tier.toDouble()),
      done: false,
      currentLabel: totalPoints.round().toString(),
      targetLabel: tier.toString(),
    ),
    Milestone(
      key: 'streak',
      icon: 'flame',
      color: palette.streak,
      current: currentStreak.toDouble(),
      target: _streakTarget.toDouble(),
      progress: _percentOf(currentStreak.toDouble(), _streakTarget.toDouble()),
      done: currentStreak >= _streakTarget,
      currentLabel: currentStreak.toString(),
      targetLabel: _streakTarget.toString(),
    ),
    Milestone(
      key: 'accuracy',
      icon: 'ribbon',
      color: palette.accuracy,
      current: accuracyValue,
      target: _accuracyTarget.toDouble(),
      progress: _percentOf(accuracyValue, _accuracyTarget.toDouble()),
      done: accuracyValue >= _accuracyTarget,
      currentLabel: '${accuracyValue.round()}%',
      targetLabel: '$_accuracyTarget%',
    ),
    Milestone(
      key: 'hours',
      icon: 'hourglass',
      color: palette.time,
      current: hours,
      target: _studyHoursTarget.toDouble(),
      progress: _percentOf(hours, _studyHoursTarget.toDouble()),
      done: hours >= _studyHoursTarget,
      currentLabel: '${hours.floor()}h',
      targetLabel: '${_studyHoursTarget}h',
    ),
  ];

  // Closest to done first: the one a user can actually finish this week is the
  // one worth putting at the top.
  rows.sort((a, b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    return b.progress.compareTo(a.progress);
  });
  return rows;
}

// ---------- method explainer ----------

class WeightRow {
  final AnalyticsSourceKey source;
  final String labelKey;
  final String color;
  final double weight;

  /// Share of the weighting, 0..100 — the number the user can actually act on.
  final double share;

  const WeightRow({
    required this.source,
    required this.labelKey,
    required this.color,
    required this.weight,
    required this.share,
  });
}

/// The real `PERCENT_WEIGHTS`, rendered as shares.
///
/// Read from the same weights the scoring uses (see the mirrors at the top of
/// this file) rather than restated, so the explainer cannot drift away from
/// the formula it claims to describe.
List<WeightRow> weightRows() {
  final total =
      ANALYTICS_SOURCES.fold<double>(0, (sum, key) => sum + _percentWeights[key]!);
  final rows = ANALYTICS_SOURCES.map((key) {
    final meta = SOURCE_META[key]!;
    final weight = _percentWeights[key]!;
    return WeightRow(
      source: key,
      labelKey: meta.labelKey,
      color: meta.color,
      weight: weight,
      share: total > 0 ? (weight / total) * 100 : 0,
    );
  }).toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));
  return rows;
}

/// Hours of study after which time stops paying, for the explainer's caveat.
// ignore: constant_identifier_names
const int TIME_POINTS_CAP_HOURS = 20; // = round(240 / 12)

// ---------- time ----------

class TimeFacts {
  /// Lifetime foreground seconds.
  final int totalSeconds;

  /// Lifetime seconds recorded against a tracked learning activity.
  final int trackedSeconds;

  /// Sessions recorded, for the average-session figure.
  final int sessions;

  const TimeFacts({
    required this.totalSeconds,
    required this.trackedSeconds,
    required this.sessions,
  });
}

/// The only time figures the app genuinely measures.
///
/// There is no per-feature timing anywhere in the data model — `secondsSpent`
/// exists on activity progress records (read, theory, constitution, GK, PM,
/// past questions) and nowhere else, and exams, daily tests and practice
/// record no time at all. So this reports the two totals that are real and
/// does not attempt a per-feature breakdown that would have to be invented.
TimeFacts timeFacts(Map<String, dynamic>? breakdown, DayBucket? latest) {
  final usage = _section(breakdown, 'usage');
  final reading = _section(breakdown, 'reading');
  int toInt(dynamic value) =>
      value is num && value.isFinite ? max(0, value.round()) : 0;
  final totalSeconds =
      max(latest?.s ?? 0, toInt(usage['foregroundSeconds']));
  final trackedSeconds =
      min(totalSeconds, toInt(reading['secondsSpent']));
  return TimeFacts(
    totalSeconds: totalSeconds,
    trackedSeconds: trackedSeconds,
    sessions: toInt(usage['sessionCount']),
  );
}

// ---------- dates ----------

const List<String> _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Devanagari month names, kept for future use (labels are English for now).
const List<String> _monthsNe = [
  'जन', 'फेब', 'मार्च', 'अप्रिल', 'मे', 'जुन',
  'जुलाई', 'अग', 'सेप', 'अक्टो', 'नोभे', 'डिसे'
];

const List<String> _weekdaysEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// Devanagari weekday names, kept for future use.
const List<String> _weekdaysNe =
    ['आइत', 'सोम', 'मंगल', 'बुध', 'बिहि', 'शुक्र', 'शनि'];

enum AnalyticsLanguage { en, ne }

/// Weekday of a `YYYY-MM-DD` key, read in UTC (0 = Sunday … 6 = Saturday).
///
/// The keys are already Kathmandu calendar days. Re-parsing them in the
/// device's zone would shift every one of them by a day for anyone behind
/// UTC, which would silently misalign the heatmap grid and the weekend tint.
int weekdayOfKey(String key) {
  final time = DateTime.tryParse('${key}T00:00:00Z')?.toUtc();
  if (time == null) return 0;
  // Dart: Monday = 1 … Sunday = 7. React's getUTCDay: Sunday = 0 … Saturday = 6.
  return time.weekday % 7;
}

({int day, int month, int year}) _partsOf(String key) {
  // TS's String.slice degrades to '' on short keys; Dart's substring throws,
  // so guard the length the same way isDayKey-shaped input never needs.
  int part(int start, int end) =>
      key.length >= end ? int.tryParse(key.substring(start, end)) ?? 0 : 0;
  return (day: part(8, 10), month: part(5, 7), year: part(0, 4));
}

/// Axis label — "14 Sep".
String dayLabel(String key, [AnalyticsLanguage language = AnalyticsLanguage.en]) {
  final parts = _partsOf(key);
  if (parts.month < 1 || parts.month > 12) return key;
  final months = language == AnalyticsLanguage.ne ? _monthsNe : _monthsEn;
  return '${parts.day} ${months[parts.month - 1]}';
}

/// Month name alone, for the heatmap's column headings.
String monthLabel(String key,
    [AnalyticsLanguage language = AnalyticsLanguage.en]) {
  final parts = _partsOf(key);
  if (parts.month < 1 || parts.month > 12) return '';
  return (language == AnalyticsLanguage.ne ? _monthsNe : _monthsEn)[parts.month - 1];
}

/// Full date with weekday, for the tapped-day detail pill.
String fullDateLabel(String key,
    [AnalyticsLanguage language = AnalyticsLanguage.en]) {
  final parts = _partsOf(key);
  if (parts.month < 1 || parts.month > 12) return key;
  final months = language == AnalyticsLanguage.ne ? _monthsNe : _monthsEn;
  final weekdays =
      language == AnalyticsLanguage.ne ? _weekdaysNe : _weekdaysEn;
  return '${weekdays[weekdayOfKey(key)]}, ${parts.day} ${months[parts.month - 1]} ${parts.year}';
}

List<String> weekdayLabels(
        [AnalyticsLanguage language = AnalyticsLanguage.en]) =>
    language == AnalyticsLanguage.ne
        ? List<String>.from(_weekdaysNe)
        : List<String>.from(_weekdaysEn);

class RelativeTime {
  /// i18n key under `analytics.footer` — `justNow`, `minutesAgo` or `hoursAgo`.
  final String key;
  final int value;

  const RelativeTime({required this.key, required this.value});
}

/// "Updated 2 minutes ago", as a key plus a number rather than a formatted
/// string — the two languages word it differently enough that building the
/// sentence here would mean embedding English grammar in a helper.
RelativeTime relativeTime(int fetchedAtMs, int nowMs) {
  final seconds = max(0, ((nowMs - fetchedAtMs) / 1000).floor());
  if (seconds < 60) return const RelativeTime(key: 'justNow', value: 0);
  final minutes = seconds ~/ 60;
  if (minutes < 60) return RelativeTime(key: 'minutesAgo', value: minutes);
  return RelativeTime(key: 'hoursAgo', value: minutes ~/ 60);
}

// ---------- small shared helpers ----------

double clampPercent(dynamic value) {
  double parsed;
  if (value is num) {
    parsed = value.toDouble();
  } else if (value is String) {
    parsed = double.tryParse(value) ?? 0;
  } else {
    parsed = 0;
  }
  if (!parsed.isFinite) return 0;
  return parsed.clamp(0.0, 100.0);
}

/// The newest snapshot in the window, which carries the lifetime totals.
DayBucket? latestBucket(List<AnalyticsSeriesPoint> points) =>
    points.isEmpty ? null : points.last.cumulative;

num totalActivitiesOf(DayBucket bucket) =>
    bucket.qa + bucket.ea + bucket.da + bucket.ta + bucket.ga + bucket.rd;
