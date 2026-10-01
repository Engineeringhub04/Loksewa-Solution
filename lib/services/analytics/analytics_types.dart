// Analytics data-layer types. Pure Dart — no Flutter, no Firebase.
//
// Dart port of the type declarations in
// LoksewasolutionApp/src/core/services/analyticsSnapshot.ts (DayBucket,
// AnalyticsStreak, AnalyticsDocument, AnalyticsSeriesPoint, AnalyticsRange)
// plus the source-key union from
// LoksewasolutionApp/src/components/analytics/analyticsDerive.ts.
library;

/// The six learning sources the analytics screen breaks down, in the canonical
/// order the radar and donut both use.
enum AnalyticsSourceKey {
  exam,
  dailyTest,
  practice,
  qotd,
  gkPm,
  reading,
}

/// One day's snapshot of the cumulative totals. Every field is a running total
/// as of the END of that day, never a per-day amount — per-day amounts are
/// derived by differencing (see buildAnalyticsSeries in analytics_series.dart).
///
/// Field names are two characters because the stored Firestore document
/// rewrites its whole `days` map on every snapshot; short keys keep that write
/// cheap. The names mirror the React document exactly.
class DayBucket {
  /// Points (cumulative effort score).
  final int p;

  /// Weighted percent at that moment, 0..100. Not cumulative — a snapshot.
  final double pc;

  /// Foreground seconds in the app.
  final int s;

  /// Recorded activity count.
  final int a;

  /// QOTD attempts / correct.
  final int qa;
  final int qc;

  /// Exam attempts / average of best-per-set percent.
  final int ea;
  final double ep;

  /// Daily Test attempts / average percent.
  final int da;
  final double dp;

  /// Practice questions attempted / correct.
  final int ta;
  final int tc;

  /// GK + PM + past questions attempted / correct.
  final int ga;
  final int gc;

  /// Reading coverage units (questions read + weighted theory + constitution).
  final int rd;

  const DayBucket({
    this.p = 0,
    this.pc = 0,
    this.s = 0,
    this.a = 0,
    this.qa = 0,
    this.qc = 0,
    this.ea = 0,
    this.ep = 0,
    this.da = 0,
    this.dp = 0,
    this.ta = 0,
    this.tc = 0,
    this.ga = 0,
    this.gc = 0,
    this.rd = 0,
  });

  /// Reads a field by its two-letter key. Unknown keys read as 0.
  num valueOf(String key) {
    switch (key) {
      case 'p':
        return p;
      case 'pc':
        return pc;
      case 's':
        return s;
      case 'a':
        return a;
      case 'qa':
        return qa;
      case 'qc':
        return qc;
      case 'ea':
        return ea;
      case 'ep':
        return ep;
      case 'da':
        return da;
      case 'dp':
        return dp;
      case 'ta':
        return ta;
      case 'tc':
        return tc;
      case 'ga':
        return ga;
      case 'gc':
        return gc;
      case 'rd':
        return rd;
      default:
        return 0;
    }
  }

  /// Keys whose per-day delta is meaningful. `pc`, `ep` and `dp` are levels,
  /// not totals — their movement is reported signed instead.
  static const List<String> cumulativeKeys = [
    'p',
    's',
    'a',
    'qa',
    'qc',
    'ea',
    'da',
    'ta',
    'tc',
    'ga',
    'gc',
    'rd',
  ];

  DayBucket copyWith({
    int? p,
    double? pc,
    int? s,
    int? a,
    int? qa,
    int? qc,
    int? ea,
    double? ep,
    int? da,
    double? dp,
    int? ta,
    int? tc,
    int? ga,
    int? gc,
    int? rd,
  }) {
    return DayBucket(
      p: p ?? this.p,
      pc: pc ?? this.pc,
      s: s ?? this.s,
      a: a ?? this.a,
      qa: qa ?? this.qa,
      qc: qc ?? this.qc,
      ea: ea ?? this.ea,
      ep: ep ?? this.ep,
      da: da ?? this.da,
      dp: dp ?? this.dp,
      ta: ta ?? this.ta,
      tc: tc ?? this.tc,
      ga: ga ?? this.ga,
      gc: gc ?? this.gc,
      rd: rd ?? this.rd,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DayBucket &&
        p == other.p &&
        pc == other.pc &&
        s == other.s &&
        a == other.a &&
        qa == other.qa &&
        qc == other.qc &&
        ea == other.ea &&
        ep == other.ep &&
        da == other.da &&
        dp == other.dp &&
        ta == other.ta &&
        tc == other.tc &&
        ga == other.ga &&
        gc == other.gc &&
        rd == other.rd;
  }

  @override
  int get hashCode => Object.hash(
      p, pc, s, a, qa, qc, ea, ep, da, dp, ta, tc, ga, gc, rd);
}

/// An empty snapshot: the identity element for differencing.
// ignore: constant_identifier_names
const DayBucket EMPTY_BUCKET = DayBucket();

/// Current and best streak of consecutive studied days.
class AnalyticsStreak {
  final int current;
  final int best;

  /// Last day with real study effort, `YYYY-MM-DD`, or '' if never.
  final String lastDay;

  const AnalyticsStreak({this.current = 0, this.best = 0, this.lastDay = ''});
}

/// The stored document at `users/{uid}/app_analytics/{subcourseId}`.
class AnalyticsDocument {
  final String courseId;
  final String subcourseId;
  final double percent;
  final int points;

  /// The leaderboard breakdown snapshot, or null when never recorded.
  /// Shape mirrors LeaderboardScore.breakdown in main_leaderboard.dart:
  /// qotd/exam/dailyTest/practice/gkPm/reading/usage sub-maps.
  final Map<String, dynamic>? breakdown;

  final AnalyticsStreak streak;

  /// Days at or before this key were reconstructed, not observed. '' = none.
  final String seededUpTo;

  /// Earliest day present in [days].
  final String firstDay;

  final Map<String, DayBucket> days;

  const AnalyticsDocument({
    this.courseId = '',
    this.subcourseId = '',
    this.percent = 0,
    this.points = 0,
    this.breakdown,
    this.streak = const AnalyticsStreak(),
    this.seededUpTo = '',
    this.firstDay = '',
    this.days = const {},
  });
}

/// One calendar day inside a built series.
class AnalyticsSeriesPoint {
  /// The day key, `YYYY-MM-DD`.
  final String key;

  /// Position in the returned series, 0-based.
  final int index;

  /// Cumulative totals, carried forward across days with no snapshot.
  final DayBucket cumulative;

  /// Change since the previous day. Zero on carried-forward days.
  final DayBucket delta;

  /// True when a snapshot actually exists for this day.
  final bool observed;

  /// True when this day was reconstructed rather than observed.
  final bool seeded;

  const AnalyticsSeriesPoint({
    required this.key,
    required this.index,
    required this.cumulative,
    required this.delta,
    required this.observed,
    required this.seeded,
  });
}

/// Chart window. `days` is null for the unbounded range.
enum AnalyticsRange {
  d7(7),
  d30(30),
  d90(90),
  all(null);

  const AnalyticsRange(this.days);
  final int? days;
}
