// Tests for the analytics derive layer: seeded exclusion, chart scales,
// weekend tinting, UTC weekday maths, cohort facts, milestone ordering,
// insight rules and the points reconciliation.
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/analytics/analytics_derive.dart';
import 'package:loksewa_solution/services/analytics/analytics_series.dart';
import 'package:loksewa_solution/services/analytics/analytics_types.dart';

DayBucket _bucket({
  int p = 0,
  double pc = 0,
  int s = 0,
  int qa = 0,
  int qc = 0,
  int ea = 0,
  double ep = 0,
  int da = 0,
  int ta = 0,
  int tc = 0,
  int ga = 0,
  int rd = 0,
}) =>
    DayBucket(
        p: p, pc: pc, s: s, qa: qa, qc: qc, ea: ea, ep: ep, da: da,
        ta: ta, tc: tc, ga: ga, rd: rd);

AnalyticsDocument _doc(Map<String, DayBucket> days,
        {String seededUpTo = '', String firstDay = ''}) =>
    AnalyticsDocument(
        subcourseId: 'sub1',
        days: days,
        seededUpTo: seededUpTo,
        firstDay: firstDay);

/// A document with one huge seeded lump followed by small observed days.
AnalyticsDocument _seededDoc() => _doc({
      // The backfill lump: everything untimed lands here at once.
      '2026-09-20': _bucket(p: 1000, qa: 10, ta: 500, tc: 400, rd: 200, s: 36000),
      '2026-09-25': _bucket(p: 1010, qa: 12, ta: 505, tc: 404, rd: 202, s: 36300, pc: 62),
      '2026-09-26': _bucket(p: 1020, qa: 14, ta: 510, tc: 408, rd: 204, s: 36600, pc: 64),
      '2026-09-27': _bucket(p: 1035, qa: 17, ta: 518, tc: 414, rd: 206, s: 37200, pc: 66),
    }, seededUpTo: '2026-09-20');

const _palette = MilestonePalette(
    points: '#fff', streak: '#fff', accuracy: '#fff', time: '#fff');

void main() {
  group('chart scales', () {
    test('chartMaxFor rounds the ceiling up to a readable value', () {
      // niceMax headroom, exercised through chartMaxFor: 47 → 50.
      final doc = _doc({'2026-09-27': _bucket(p: 47)});
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-27');
      expect(chartMaxFor(points, (pt) => pt.delta.p), 50);
    });

    test('chartMaxFor never drops below the minimum', () {
      final doc = _doc({'2026-09-27': _bucket()});
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-27');
      expect(chartMaxFor(points, (pt) => pt.delta.p), 1);
      expect(chartMaxFor(points, (pt) => pt.delta.p, 5), 5);
    });
  });

  group('seeded exclusion', () {
    test('summarise totals come from observed days only', () {
      final points =
          buildAnalyticsSeries(_seededDoc(), AnalyticsRange.all, '2026-09-27');
      final summary = summarise(points);

      // The 1000-point lump is invisible to window totals.
      expect(summary.pointsEarned, 35); // 10 + 10 + 15
      // Effort per observed day: 9 (2+5+2), 9 (2+5+2), 13 (3+8+2).
      expect(summary.activities, 31);
      expect(summary.studySeconds, 300 + 300 + 600);
      expect(summary.activeDays, 3);
      expect(summary.observedDays, 3);
      // Levels still read off the newest snapshot.
      expect(summary.accuracy, 66);
      expect(summary.totalPoints, 1035);
      // Baseline is the first OBSERVED day, not the seeded lump.
      expect(summary.accuracyStart, 62);
    });

    test('chartMaxFor ignores the seeded lump when observed days exist', () {
      final points =
          buildAnalyticsSeries(_seededDoc(), AnalyticsRange.all, '2026-09-27');
      final max = chartMaxFor(points, (pt) => pt.delta.p);
      // Observed deltas are 10/10/15 → niceMax(15) = 20. With the 1000-point
      // lump it would have been 1000.
      expect(max, 20);
    });

    test('chartMaxFor falls back to all points when nothing is observed', () {
      final doc = _doc({
        '2026-09-20': _bucket(p: 1000),
        '2026-09-21': _bucket(p: 1200),
      }, seededUpTo: '2026-09-21');
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-21');
      expect(chartMaxFor(points, (pt) => pt.delta.p), 1000);
    });

    test('leadingSeededCount counts only the leading run', () {
      final points =
          buildAnalyticsSeries(_seededDoc(), AnalyticsRange.all, '2026-09-27');
      expect(leadingSeededCount(points), 1);
    });

    test('buildSourceStats volume skips seeded deltas; lifetime reads latest', () {
      final points =
          buildAnalyticsSeries(_seededDoc(), AnalyticsRange.all, '2026-09-27');
      final stats = buildSourceStats(points);
      final practice =
          stats.firstWhere((s) => s.key == AnalyticsSourceKey.practice);
      // Window volume: 5 + 5 + 8 attempted on observed days only.
      expect(practice.volume, 18);
      // Lifetime volume off the newest snapshot.
      expect(practice.lifetimeVolume, 518);
      expect(practice.touched, isTrue);
      final exam = stats.firstWhere((s) => s.key == AnalyticsSourceKey.exam);
      expect(exam.touched, isFalse);
      expect(exam.accuracy, 0);
    });

    test('weekStrip gives seeded days zero activities', () {
      // Seeded day inside the trailing-7 window: observed but contributes 0.
      final doc = _doc({
        '2026-09-25': _bucket(p: 900, qa: 400, ta: 300),
        '2026-09-26': _bucket(p: 910, qa: 402, ta: 305),
        '2026-09-27': _bucket(p: 925, qa: 405, ta: 313),
      }, seededUpTo: '2026-09-25');
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-27');
      final strip = weekStrip(points, '2026-09-27');
      expect(strip.length, 7);
      expect(strip.last.today, isTrue);
      expect(strip.last.key, '2026-09-27');

      final seededDot = strip.firstWhere((d) => d.key == '2026-09-25');
      expect(seededDot.recorded, isTrue);
      expect(seededDot.activities, 0); // backfill artefact, not real work

      final realDot = strip.firstWhere((d) => d.key == '2026-09-26');
      expect(realDot.activities, 2 + 5);
      expect(realDot.recorded, isTrue);

      // A day with no snapshot at all is unrecorded with zero activities.
      final missing = strip.firstWhere((d) => d.key == '2026-09-21');
      expect(missing.recorded, isFalse);
      expect(missing.activities, 0);
    });

    test('bestWeekday skips seeded days', () {
      final points =
          buildAnalyticsSeries(_seededDoc(), AnalyticsRange.all, '2026-09-27');
      final best = bestWeekday(points)!;
      // 2026-09-27 is a Sunday with effort 13 — and so is the seeded 09-20,
      // whose 710-unit lump must NOT count. activities == 13 proves the skip.
      expect(best.weekday, 0);
      expect(best.activities, 13);
    });

    test('bestWeekday is null with no real effort', () {
      final points = buildAnalyticsSeries(
          _doc({'2026-09-25': _bucket(p: 10)}), AnalyticsRange.all, '2026-09-25');
      expect(bestWeekday(points), isNull);
    });
  });

  group('weekdayOfKey', () {
    test('reads keys in UTC, never the device zone', () {
      // 2026-10-01 is a Thursday however the device is set.
      expect(weekdayOfKey('2026-10-01'), 4);
      expect(weekdayOfKey('2026-09-25'), 5); // Friday
      expect(weekdayOfKey('2026-09-26'), 6); // Saturday
      expect(weekdayOfKey('2026-09-27'), 0); // Sunday
      expect(weekdayOfKey('2026-01-01'), 4); // Thursday
      expect(weekdayOfKey('garbage'), 0);
    });

    test('weekendIndices picks Friday and Saturday', () {
      // 2026-09-25 (Fri) … 2026-10-01 (Thu).
      final days = {
        for (var i = 0; i < 7; i++)
          '2026-09-${25 + i}': _bucket(qa: 1),
      };
      final points =
          buildAnalyticsSeries(_doc(days), AnalyticsRange.all, '2026-10-01');
      expect(weekendIndices(points), [0, 1]);
    });
  });

  group('percentChange', () {
    test('computes relative change; null without a baseline', () {
      expect(percentChange(150, 100), 50);
      expect(percentChange(100, 100), 0);
      expect(percentChange(50, 200), -75);
      expect(percentChange(40, 0), isNull);
      expect(percentChange(40, -5), isNull);
    });
  });

  group('cohortFacts', () {
    List<CohortRow> board() => const [
          CohortRow(uid: 'a', points: 50, percent: 90),
          CohortRow(uid: 'b', points: 40, percent: 80),
          CohortRow(uid: 'c', points: 30, percent: 70),
          CohortRow(uid: 'd', points: 20, percent: 60),
          CohortRow(uid: 'e', points: 10, percent: 50),
        ];

    test('rank, medians and gaps from board order', () {
      final facts = cohortFacts(board(), 'c');
      expect(facts.rank, 3);
      expect(facts.size, 5);
      expect(facts.topPercent, 60);
      expect(facts.medianPercent, 70);
      expect(facts.medianPoints, 30);
      expect(facts.topPoints, 50);
      expect(facts.position, 60);
      expect(facts.myPoints, 30);
      expect(facts.myPercent, 70);
      expect(facts.pointsToNext, 10);
    });

    test('leader has no one above; topPercent never rounds to zero', () {
      final facts = cohortFacts(board(), 'a');
      expect(facts.rank, 1);
      expect(facts.pointsToNext, isNull);
      expect(facts.position, 100);

      final big = List<CohortRow>.generate(
          300, (i) => CohortRow(uid: 'u$i', points: 300 - i, percent: 90));
      expect(cohortFacts(big, 'u0').topPercent, 1);
      expect(cohortFacts(big, 'u299').topPercent, 100);
    });

    test('even-sized boards average the two middle values', () {
      const rows = [
        CohortRow(uid: 'a', points: 40, percent: 80),
        CohortRow(uid: 'b', points: 30, percent: 70),
        CohortRow(uid: 'c', points: 20, percent: 60),
        CohortRow(uid: 'd', points: 10, percent: 50),
      ];
      final facts = cohortFacts(rows, 'b');
      expect(facts.medianPoints, 25);
      expect(facts.medianPercent, 65);
    });

    test('empty board and unknown user degrade gracefully', () {
      final empty = cohortFacts(const [], 'x');
      expect(empty.rank, isNull);
      expect(empty.size, 0);
      expect(empty.topPercent, isNull);
      expect(empty.medianPoints, 0);
      expect(empty.topPoints, 0);
      expect(empty.position, isNull);
      expect(empty.pointsToNext, isNull);

      final missing = cohortFacts(board(), 'ghost');
      expect(missing.rank, isNull);
      expect(missing.myPoints, 0);
      expect(missing.topPercent, isNull);
    });
  });

  group('buildMilestones', () {
    test('undone first, closest to done first', () {
      final rows = buildMilestones(120, 3, 72.4, 3600 * 10, _palette);
      // Progress: accuracy 80.4%, points 48%, streak 42.9%, hours 20%.
      expect(rows.map((m) => m.key), ['accuracy', 'points', 'streak', 'hours']);
      expect(rows.every((m) => !m.done), isTrue);
    });

    test('done milestones sink below undone ones', () {
      final rows = buildMilestones(120, 7, 95, 3600 * 60, _palette);
      // points 48% undone; done: hours 120%, accuracy 105.6%, streak 100%.
      expect(rows.map((m) => m.key), ['points', 'hours', 'accuracy', 'streak']);
      expect(rows.first.done, isFalse);
      expect(rows.skip(1).every((m) => m.done), isTrue);
    });

    test('tiers step up and keep going past 25k', () {
      expect(buildMilestones(99, 0, 0, 0, _palette).first.target, 100);
      expect(buildMilestones(100, 0, 0, 0, _palette).first.target, 250);
      expect(buildMilestones(25000, 0, 0, 0, _palette).first.target, 50000);
      expect(buildMilestones(30000, 0, 0, 0, _palette).first.target, 50000);
    });

    test('labels are display-ready', () {
      final rows = buildMilestones(120, 3, 72.4, 3600 * 10, _palette);
      final points = rows.firstWhere((m) => m.key == 'points');
      expect(points.currentLabel, '120');
      expect(points.targetLabel, '250');
      final hours = rows.firstWhere((m) => m.key == 'hours');
      expect(hours.currentLabel, '10h');
      expect(hours.targetLabel, '50h');
      final accuracy = rows.firstWhere((m) => m.key == 'accuracy');
      expect(accuracy.currentLabel, '72%');
    });
  });

  group('deriveInsights', () {
    SourceStat stat(AnalyticsSourceKey key,
            {double accuracy = 0, num volume = 0, num lifetime = 0}) =>
        SourceStat(
          key: key,
          color: SOURCE_META[key]!.color,
          accuracy: accuracy,
          volume: volume,
          lifetimeVolume: lifetime,
          touched: lifetime > 0,
        );

    List<SourceStat> allTouched() => [
          stat(AnalyticsSourceKey.exam, accuracy: 70, volume: 4, lifetime: 10),
          stat(AnalyticsSourceKey.dailyTest, accuracy: 65, volume: 4, lifetime: 10),
          stat(AnalyticsSourceKey.practice, accuracy: 80, volume: 8, lifetime: 20),
          stat(AnalyticsSourceKey.qotd, accuracy: 80, volume: 8, lifetime: 20),
          stat(AnalyticsSourceKey.gkPm, accuracy: 50, volume: 4, lifetime: 10),
          stat(AnalyticsSourceKey.reading, accuracy: 40, volume: 4, lifetime: 50),
        ];

    test('strength is the best touched accuracy; ties break to heavier weight', () {
      final insights = deriveInsights(allTouched());
      // practice and qotd tie at 80; practice weighs 2.5 vs qotd 2.
      expect(insights.strength!.source, AnalyticsSourceKey.practice);
    });

    test('focus prefers the untouched heaviest-weight source', () {
      final stats = [
        stat(AnalyticsSourceKey.exam), // untouched, weight 3
        stat(AnalyticsSourceKey.dailyTest, accuracy: 65, volume: 4, lifetime: 10),
        stat(AnalyticsSourceKey.practice, accuracy: 80, volume: 8, lifetime: 20),
        stat(AnalyticsSourceKey.qotd, accuracy: 70, volume: 8, lifetime: 20),
        stat(AnalyticsSourceKey.gkPm, accuracy: 50, volume: 4, lifetime: 10),
        stat(AnalyticsSourceKey.reading), // untouched, weight 1
      ];
      final insights = deriveInsights(stats);
      expect(insights.focus!.source, AnalyticsSourceKey.exam);
      expect(insights.focusUntouched, isTrue);
      expect(insights.strength!.source, AnalyticsSourceKey.practice);
    });

    test('with everything touched, focus is the weakest meaningful source', () {
      final insights = deriveInsights(allTouched());
      // gkPm at 50 is weakest; reading (40) is coverage, not accuracy.
      expect(insights.focus!.source, AnalyticsSourceKey.gkPm);
      expect(insights.focusUntouched, isFalse);
    });

    test('weak samples below the meaningful threshold are ignored', () {
      final stats = [
        stat(AnalyticsSourceKey.exam, accuracy: 40, volume: 1, lifetime: 3),
        stat(AnalyticsSourceKey.dailyTest, accuracy: 65, volume: 4, lifetime: 10),
        stat(AnalyticsSourceKey.practice, accuracy: 80, volume: 8, lifetime: 20),
        stat(AnalyticsSourceKey.qotd, accuracy: 90, volume: 8, lifetime: 20),
        stat(AnalyticsSourceKey.gkPm, accuracy: 70, volume: 4, lifetime: 10),
        stat(AnalyticsSourceKey.reading, accuracy: 40, volume: 4, lifetime: 50),
      ];
      final insights = deriveInsights(stats);
      // exam's 40% on 3 attempts is noise, so it is skipped over: focus falls
      // to the next weakest eligible source, dailyTest at 65%.
      expect(insights.strength!.source, AnalyticsSourceKey.qotd);
      expect(insights.focus!.source, AnalyticsSourceKey.dailyTest);
      expect(insights.focusUntouched, isFalse);
    });

    test('weakest == strength yields no focus', () {
      // Everything touched at the same accuracy: the strength (tie → heaviest
      // weight, exam) is also the weakest, so there is nothing to fix.
      final stats = ANALYTICS_SOURCES
          .map((k) => stat(k, accuracy: 70, volume: 5, lifetime: 10))
          .toList();
      final insights = deriveInsights(stats);
      expect(insights.strength!.source, AnalyticsSourceKey.exam);
      expect(insights.focus, isNull);
      expect(insights.focusUntouched, isFalse);
    });

    test('nothing touched: no strength, heaviest source as focus', () {
      final insights = deriveInsights(
          ANALYTICS_SOURCES.map((k) => stat(k)).toList());
      expect(insights.strength, isNull);
      expect(insights.focus!.source, AnalyticsSourceKey.exam);
      expect(insights.focusUntouched, isTrue);
    });
  });

  group('pointsBreakdown', () {
    Map<String, dynamic> breakdown() => {
          'qotd': {'attempts': 10, 'correct': 7},
          'practice': {'attempted': 20, 'correct': 12, 'chaptersCompleted': 2},
          'reading': {'questionsRead': 5},
          'usage': {'foregroundSeconds': 7200},
        };

    test('exact rows reconcile to the total', () {
      // qotd 10*4+7*10=110, practice 20*2+12*5+2*8=116,
      // reading 5*1=5, time 7200/3600*12=24 → 255.
      final result = pointsBreakdown(breakdown(), 255);
      expect(result.estimated, isFalse);
      expect(result.total, 255);
      final byKey = {for (final r in result.rows) r.key: r};
      expect(byKey[PointsRowKey.qotd]!.points, 110);
      expect(byKey[PointsRowKey.practice]!.points, 116);
      expect(byKey[PointsRowKey.reading]!.points, 5);
      expect(byKey[PointsRowKey.time]!.points, 24);
      expect(byKey.containsKey(PointsRowKey.bonus), isFalse);
      // Sorted by points, shares add to ~100.
      expect(result.rows.first.key, PointsRowKey.practice);
      final shareSum = result.rows.fold<double>(0, (s, r) => s + r.share);
      expect(shareSum, closeTo(100, 0.001));
    });

    test('dailyTest row is exact from attempts × average', () {
      final bd = breakdown()
        ..['dailyTest'] = {'attempts': 4, 'averagePercent': 60};
      // 4*6 + 4*60*0.5 = 144. Total 255+144 = 399.
      final result = pointsBreakdown(bd, 399);
      final row = result.rows.firstWhere((r) => r.key == PointsRowKey.dailyTest);
      expect(row.points, 144);
      expect(result.estimated, isFalse);
    });

    test('exam overshoot is absorbed by the exam row only', () {
      final bd = breakdown()
        ..['exam'] = {'attempts': 2, 'averagePercent': 80};
      // Exam upper bound: 2*10 + 2*80 = 180. Others sum to 255.
      // Total 295 → exam trimmed to 40, everything else untouched.
      final result = pointsBreakdown(bd, 295);
      expect(result.estimated, isTrue);
      final byKey = {for (final r in result.rows) r.key: r};
      expect(byKey[PointsRowKey.exam]!.points, 40);
      expect(byKey[PointsRowKey.qotd]!.points, 110);
      expect(byKey[PointsRowKey.practice]!.points, 116);
      expect(byKey.containsKey(PointsRowKey.bonus), isFalse);
    });

    test('exam never drops below its attempt-points floor', () {
      final bd = {
        'exam': {'attempts': 2, 'averagePercent': 80},
        'qotd': {'attempts': 10, 'correct': 7}, // 110
      };
      // Sum 290 vs total 100: exam would go to -90 without the floor.
      final result = pointsBreakdown(bd, 100);
      final exam = result.rows.firstWhere((r) => r.key == PointsRowKey.exam);
      expect(exam.points, 20); // the certain 2 × 10 attempt points
      // The qotd row is never touched by the reconciliation.
      expect(result.rows.firstWhere((r) => r.key == PointsRowKey.qotd).points,
          110);
    });

    test('remainder under the total becomes the bonus row', () {
      final result = pointsBreakdown(breakdown(), 300);
      final bonus =
          result.rows.firstWhere((r) => r.key == PointsRowKey.bonus);
      expect(bonus.points, 45); // 300 - 255
      expect(bonus.color, '#94A3B8');
    });

    test('sub-point rows are filtered out', () {
      // 150s of app time → 0.5 time points: noise, not a row.
      final result = pointsBreakdown({
        'usage': {'foregroundSeconds': 150},
      }, 10);
      expect(result.rows.any((r) => r.key == PointsRowKey.time), isFalse);
      expect(result.rows.map((r) => r.key), [PointsRowKey.bonus]);
    });

    test('null breakdown yields no rows', () {
      final result = pointsBreakdown(null, 500);
      expect(result.rows, isEmpty);
      expect(result.total, 0);
      expect(result.estimated, isFalse);
    });
  });

  group('sources', () {
    test('sourceAccuracy reads levels; reading uses coverage', () {
      final bucket = _bucket(qa: 10, qc: 7, ta: 10, tc: 8, ep: 82.5, rd: 100);
      expect(sourceAccuracy(bucket, AnalyticsSourceKey.qotd), 70);
      expect(sourceAccuracy(bucket, AnalyticsSourceKey.practice), 80);
      expect(sourceAccuracy(bucket, AnalyticsSourceKey.exam), 82.5);
      expect(sourceAccuracy(bucket, AnalyticsSourceKey.reading), 50); // 100/200
      expect(sourceAccuracy(bucket, AnalyticsSourceKey.gkPm), 0); // untouched
    });

    test('sourceVolume reads attempts or covered units', () {
      final bucket = _bucket(qa: 10, ea: 3, da: 2, ta: 40, ga: 7, rd: 100);
      expect(sourceVolume(bucket, AnalyticsSourceKey.qotd), 10);
      expect(sourceVolume(bucket, AnalyticsSourceKey.exam), 3);
      expect(sourceVolume(bucket, AnalyticsSourceKey.dailyTest), 2);
      expect(sourceVolume(bucket, AnalyticsSourceKey.practice), 40);
      expect(sourceVolume(bucket, AnalyticsSourceKey.gkPm), 7);
      expect(sourceVolume(bucket, AnalyticsSourceKey.reading), 100);
    });

    test('SOURCE_META keeps the six fixed hues', () {
      expect(SOURCE_META[AnalyticsSourceKey.exam]!.color, '#6366F1');
      expect(SOURCE_META[AnalyticsSourceKey.dailyTest]!.color, '#0EA5E9');
      expect(SOURCE_META[AnalyticsSourceKey.practice]!.color, '#10B981');
      expect(SOURCE_META[AnalyticsSourceKey.qotd]!.color, '#F59E0B');
      expect(SOURCE_META[AnalyticsSourceKey.gkPm]!.color, '#A855F7');
      expect(SOURCE_META[AnalyticsSourceKey.reading]!.color, '#14B8A6');
      expect(ANALYTICS_SOURCES.length, 6);
    });
  });

  group('weightRows', () {
    test('shares sum to 100 and follow the scoring weights', () {
      final rows = weightRows();
      expect(rows.first.source, AnalyticsSourceKey.exam);
      expect(rows.first.weight, 3);
      final shareSum = rows.fold<double>(0, (s, r) => s + r.share);
      expect(shareSum, closeTo(100, 0.001));
      // exam 3 / 12.5 total = 24%.
      expect(rows.first.share, closeTo(24, 0.001));
    });

    test('TIME_POINTS_CAP_HOURS matches the scoring cap', () {
      expect(TIME_POINTS_CAP_HOURS, 20);
    });
  });

  group('timeFacts', () {
    test('reports the two real totals, never an invented split', () {
      final facts = timeFacts({
        'usage': {'foregroundSeconds': 5000, 'sessionCount': 3},
        'reading': {'secondsSpent': 1200},
      }, _bucket(s: 4000));
      expect(facts.totalSeconds, 5000); // max(latest, usage)
      expect(facts.trackedSeconds, 1200);
      expect(facts.sessions, 3);
    });

    test('tracked seconds can never exceed the total', () {
      final facts = timeFacts({
        'usage': {'foregroundSeconds': 100},
        'reading': {'secondsSpent': 99999},
      }, null);
      expect(facts.totalSeconds, 100);
      expect(facts.trackedSeconds, 100);
    });
  });

  group('date labels', () {
    test('labels format English dates', () {
      expect(dayLabel('2026-10-01'), '1 Oct');
      expect(monthLabel('2026-10-01'), 'Oct');
      expect(fullDateLabel('2026-10-01'), 'Thu, 1 Oct 2026');
      expect(weekdayLabels(), ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']);
    });

    test('invalid keys degrade to the raw key or empty', () {
      expect(dayLabel('nope'), 'nope');
      expect(monthLabel('nope'), '');
      expect(fullDateLabel('nope'), 'nope');
    });
  });

  group('relativeTime', () {
    test('buckets into justNow / minutesAgo / hoursAgo', () {
      final just = relativeTime(0, 30 * 1000);
      expect(just.key, 'justNow');
      expect(just.value, 0);
      final mins = relativeTime(0, 2 * 60 * 1000 + 5000);
      expect(mins.key, 'minutesAgo');
      expect(mins.value, 2);
      final hours = relativeTime(0, 3 * 3600 * 1000);
      expect(hours.key, 'hoursAgo');
      expect(hours.value, 3);
    });
  });

  group('small helpers', () {
    test('clampPercent pins to 0..100', () {
      expect(clampPercent(72.5), 72.5);
      expect(clampPercent(150), 100);
      expect(clampPercent(-5), 0);
      expect(clampPercent('abc'), 0);
      expect(clampPercent(null), 0);
      expect(clampPercent(double.nan), 0);
    });

    test('latestBucket returns the newest cumulative or null', () {
      expect(latestBucket([]), isNull);
      final points =
          buildAnalyticsSeries(_seededDoc(), AnalyticsRange.all, '2026-09-27');
      expect(latestBucket(points)!.p, 1035);
    });

    test('totalActivitiesOf sums attempts and coverage', () {
      expect(totalActivitiesOf(_bucket(qa: 1, ea: 2, da: 3, ta: 4, ga: 5, rd: 6)),
          21);
    });
  });
}
