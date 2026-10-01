// Analytics series building: day-key arithmetic, document parsing, the
// sparse `days` map expanded into one point per calendar day, and streaks.
//
// Dart port of the read/derive half of
// LoksewasolutionApp/src/core/services/analyticsSnapshot.ts. The WRITE path
// (recordAnalyticsSnapshot, buildBackfillDays, bucketFromScore) is
// intentionally NOT ported: this module is read-only by design.
import 'dart:math';

import '../server_clock.dart';
import 'analytics_types.dart';

// ---------- date-key arithmetic ----------
//
// Keys are Kathmandu calendar days. All arithmetic happens at UTC midnight so
// a day is always exactly 86_400_000 ms; Nepal has no DST, so the Kathmandu
// day boundary maps cleanly onto this and no offset maths is needed.

const int _dayMs = 86400000;
final RegExp _keyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isDayKey(Object? value) => value is String && _keyPattern.hasMatch(value);

int _keyToUtcMs(String key) {
  final year = int.parse(key.substring(0, 4));
  final month = int.parse(key.substring(5, 7));
  final day = int.parse(key.substring(8, 10));
  return DateTime.utc(year, month, day).millisecondsSinceEpoch;
}

String _utcMsToKey(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// `addDayKey('2026-09-14', -3)` → `'2026-09-11'`.
String addDayKey(String key, int days) {
  if (!isDayKey(key)) return key;
  return _utcMsToKey(_keyToUtcMs(key) + days * _dayMs);
}

/// Whole days from `from` to `to`; negative when `to` is earlier.
int diffDayKeys(String from, String to) {
  if (!isDayKey(from) || !isDayKey(to)) return 0;
  return ((_keyToUtcMs(to) - _keyToUtcMs(from)) / _dayMs).round();
}

/// Today in Kathmandu — the same boundary QOTD uses, so a streak agrees with
/// it. Uses the server-corrected clock, mirroring todayDateKey() in
/// exam_service.dart.
String analyticsTodayKey() {
  final kathmandu =
      ServerClock.nowUtc().add(const Duration(hours: 5, minutes: 45));
  return '${kathmandu.year.toString().padLeft(4, '0')}-'
      '${kathmandu.month.toString().padLeft(2, '0')}-'
      '${kathmandu.day.toString().padLeft(2, '0')}';
}

// ---------- value coercion ----------

int _toInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.isFinite ? value.round() : fallback;
  return fallback;
}

double _toDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.isFinite ? value.toDouble() : fallback;
  return fallback;
}

String _toStr(dynamic value, [String fallback = '']) =>
    (value is String && value.isNotEmpty) ? value : fallback;

Map<String, dynamic>? _asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

DayBucket _normaliseBucket(dynamic raw) {
  if (raw is! Map) return EMPTY_BUCKET;
  return DayBucket(
    p: _toInt(raw['p']),
    pc: _toDouble(raw['pc']),
    s: _toInt(raw['s']),
    a: _toInt(raw['a']),
    qa: _toInt(raw['qa']),
    qc: _toInt(raw['qc']),
    ea: _toInt(raw['ea']),
    ep: _toDouble(raw['ep']),
    da: _toInt(raw['da']),
    dp: _toDouble(raw['dp']),
    ta: _toInt(raw['ta']),
    tc: _toInt(raw['tc']),
    ga: _toInt(raw['ga']),
    gc: _toInt(raw['gc']),
    rd: _toInt(raw['rd']),
  );
}

/// Parses a raw Firestore document into an [AnalyticsDocument].
/// Unknown day keys are skipped; missing fields default to zero.
AnalyticsDocument parseAnalyticsDocument(
    Map<String, dynamic> raw, String subcourseId) {
  final days = <String, DayBucket>{};
  final rawDays = raw['days'];
  if (rawDays is Map) {
    rawDays.forEach((key, value) {
      if (isDayKey(key)) days[key as String] = _normaliseBucket(value);
    });
  }
  final sorted = days.keys.toList()..sort();
  final streakRaw = _asMap(raw['streak']) ?? <String, dynamic>{};

  return AnalyticsDocument(
    courseId: _toStr(raw['courseId']),
    subcourseId: _toStr(raw['subcourseId'], subcourseId),
    percent: _toDouble(raw['percent']),
    points: _toInt(raw['points']),
    breakdown: _asMap(raw['breakdown']),
    streak: AnalyticsStreak(
      current: _toInt(streakRaw['current']),
      best: _toInt(streakRaw['best']),
      lastDay: _toStr(streakRaw['lastDay']),
    ),
    seededUpTo: _toStr(raw['seededUpTo']),
    firstDay: _toStr(raw['firstDay'], sorted.isNotEmpty ? sorted.first : ''),
    days: days,
  );
}

// ---------- streaks ----------
//
// A streak day means the user actually STUDIED something, not merely that the
// app opened. Points alone would not do: study time earns points, so launching
// the app and reading nothing would silently extend a streak.

/// Units of real work done on a day, given the previous observed snapshot.
int _dayEffort(DayBucket current, DayBucket? previous) {
  final base = previous ?? EMPTY_BUCKET;
  int delta(String key) =>
      max(0, (current.valueOf(key) - base.valueOf(key)).toInt());
  return delta('qa') +
      delta('ea') +
      delta('da') +
      delta('ta') +
      delta('ga') +
      delta('rd');
}

/// Current and best streak of consecutive studied days.
///
/// A missing day means no snapshot was taken, which means the app was not
/// opened, which correctly breaks the streak. Today NOT being studied yet does
/// not break it — the streak is measured from yesterday in that case, so it
/// does not appear to collapse every morning before the user has had a chance
/// to study.
AnalyticsStreak computeAnalyticsStreak(
    Map<String, DayBucket> days, String todayKey) {
  final keys = days.keys.where(isDayKey).toList()..sort();
  if (keys.isEmpty) return const AnalyticsStreak();

  final studied = <String>{};
  DayBucket? previous;
  var lastDay = '';
  for (final key in keys) {
    final bucket = days[key]!;
    if (_dayEffort(bucket, previous) > 0) {
      studied.add(key);
      lastDay = key;
    }
    previous = bucket;
  }

  var best = 0;
  var run = 0;
  final firstKey = keys.first;
  final span = max(0, diffDayKeys(firstKey, todayKey));
  for (var offset = 0; offset <= span; offset++) {
    if (studied.contains(addDayKey(firstKey, offset))) {
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
  }

  var cursor = studied.contains(todayKey) ? todayKey : addDayKey(todayKey, -1);
  var current = 0;
  while (studied.contains(cursor)) {
    current++;
    cursor = addDayKey(cursor, -1);
  }

  return AnalyticsStreak(
      current: current, best: max(best, current), lastDay: lastDay);
}

// ---------- series ----------

double _round2(double value) => (value * 100).round() / 100;

/// Expands the stored sparse map into one point per calendar day.
///
/// Days with no snapshot carry the previous cumulative values forward and
/// report a zero delta, which is semantically right: nothing was recorded, so
/// nothing changed. Charts can therefore index straight into this array without
/// having to reason about gaps.
List<AnalyticsSeriesPoint> buildAnalyticsSeries(
  AnalyticsDocument? doc,
  AnalyticsRange range, [
  String? todayKey,
]) {
  final today = todayKey ?? analyticsTodayKey();
  if (doc == null) return [];
  final keys = doc.days.keys.where(isDayKey).toList()..sort();
  if (keys.isEmpty) return [];

  final earliest = (doc.firstDay.isNotEmpty && isDayKey(doc.firstDay))
      ? doc.firstDay
      : keys.first;
  final windowStart = range == AnalyticsRange.all
      ? earliest
      : addDayKey(today, -(range.days! - 1));
  final start = windowStart.compareTo(earliest) > 0 ? windowStart : earliest;
  final span = diffDayKeys(start, today);
  if (span < 0) return [];

  // Carry-forward must begin from the last snapshot BEFORE the window, or a
  // 7-day view of a long-running account would start from zero and show a
  // fictitious jump on its first observed day.
  var carried = EMPTY_BUCKET;
  for (final key in keys) {
    if (key.compareTo(start) >= 0) break;
    carried = doc.days[key]!;
  }

  final points = <AnalyticsSeriesPoint>[];
  var previous = carried;
  for (var offset = 0; offset <= span; offset++) {
    final key = addDayKey(start, offset);
    final snapshot = doc.days[key];
    final observed = snapshot != null;
    final cumulative = observed ? snapshot : previous;

    var delta = EMPTY_BUCKET;
    if (observed) {
      delta = DayBucket(
        p: max(0, cumulative.p - previous.p),
        pc: _round2(cumulative.pc - previous.pc),
        s: max(0, cumulative.s - previous.s),
        a: max(0, cumulative.a - previous.a),
        qa: max(0, cumulative.qa - previous.qa),
        qc: max(0, cumulative.qc - previous.qc),
        ea: max(0, cumulative.ea - previous.ea),
        ep: _round2(cumulative.ep - previous.ep),
        da: max(0, cumulative.da - previous.da),
        dp: _round2(cumulative.dp - previous.dp),
        ta: max(0, cumulative.ta - previous.ta),
        tc: max(0, cumulative.tc - previous.tc),
        ga: max(0, cumulative.ga - previous.ga),
        gc: max(0, cumulative.gc - previous.gc),
        rd: max(0, cumulative.rd - previous.rd),
      );
    }

    points.add(AnalyticsSeriesPoint(
      key: key,
      index: offset,
      cumulative: cumulative,
      delta: delta,
      observed: observed,
      seeded: doc.seededUpTo.isNotEmpty && key.compareTo(doc.seededUpTo) <= 0,
    ));
    previous = cumulative;
  }

  return points;
}

/// Sum of one delta field across a series — e.g. questions answered this week.
num sumDelta(List<AnalyticsSeriesPoint> points, String field) {
  num total = 0;
  for (final point in points) {
    total += point.delta.valueOf(field);
  }
  return total;
}

/// Total real work done per day, the number the effort chart plots.
num effortOf(AnalyticsSeriesPoint point) {
  final d = point.delta;
  return d.qa + d.ea + d.da + d.ta + d.ga + d.rd;
}

/// The same window immediately before the one given, for "vs. previous period"
/// comparisons. Returns an empty list when there is no history to compare
/// with.
List<AnalyticsSeriesPoint> previousPeriodSeries(
  AnalyticsDocument? doc,
  AnalyticsRange range, [
  String? todayKey,
]) {
  final today = todayKey ?? analyticsTodayKey();
  if (doc == null || range == AnalyticsRange.all) return [];
  return buildAnalyticsSeries(doc, range, addDayKey(today, -range.days!));
}
