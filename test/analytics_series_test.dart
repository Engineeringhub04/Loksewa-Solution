// Tests for the analytics series layer: day-key arithmetic, series building
// with carry-forward, delta clamping, seeded flags, and streaks.
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/analytics/analytics_series.dart';
import 'package:loksewa_solution/services/analytics/analytics_types.dart';

DayBucket _bucket({
  int p = 0,
  double pc = 0,
  int qa = 0,
  int qc = 0,
  int ea = 0,
  int da = 0,
  int ta = 0,
  int ga = 0,
  int rd = 0,
}) =>
    DayBucket(p: p, pc: pc, qa: qa, qc: qc, ea: ea, da: da, ta: ta, ga: ga, rd: rd);

AnalyticsDocument _doc(Map<String, DayBucket> days,
        {String seededUpTo = '', String firstDay = ''}) =>
    AnalyticsDocument(
      subcourseId: 'sub1',
      days: days,
      seededUpTo: seededUpTo,
      firstDay: firstDay,
    );

void main() {
  group('day keys', () {
    test('isDayKey accepts YYYY-MM-DD only', () {
      expect(isDayKey('2026-09-25'), isTrue);
      expect(isDayKey('2026-9-5'), isFalse);
      expect(isDayKey('not-a-day'), isFalse);
      expect(isDayKey(''), isFalse);
      expect(isDayKey(null), isFalse);
      expect(isDayKey(42), isFalse);
    });

    test('addDayKey moves across month boundaries', () {
      expect(addDayKey('2026-09-14', -3), '2026-09-11');
      expect(addDayKey('2026-10-01', -1), '2026-09-30');
      expect(addDayKey('2026-01-01', 1), '2026-01-02');
      expect(addDayKey('2026-09-25', 7), '2026-10-02');
    });

    test('addDayKey passes invalid keys through untouched', () {
      expect(addDayKey('nope', 3), 'nope');
    });

    test('diffDayKeys counts whole days, signed', () {
      expect(diffDayKeys('2026-09-25', '2026-09-28'), 3);
      expect(diffDayKeys('2026-09-28', '2026-09-25'), -3);
      expect(diffDayKeys('2026-09-25', '2026-09-25'), 0);
      expect(diffDayKeys('bad', '2026-09-25'), 0);
    });
  });

  group('buildAnalyticsSeries', () {
    test('returns empty for null or day-less documents', () {
      expect(buildAnalyticsSeries(null, AnalyticsRange.d7, '2026-10-01'), isEmpty);
      expect(buildAnalyticsSeries(_doc({}), AnalyticsRange.d7, '2026-10-01'), isEmpty);
    });

    test('deltas across missing days: gap carries forward with zero delta', () {
      final doc = _doc({
        '2026-09-25': _bucket(p: 10, qa: 5, pc: 50),
        '2026-09-27': _bucket(p: 25, qa: 12, pc: 60),
      });
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-27');

      expect(points.map((pt) => pt.key),
          ['2026-09-25', '2026-09-26', '2026-09-27']);

      // First observed day diffs against empty.
      expect(points[0].observed, isTrue);
      expect(points[0].delta.p, 10);
      expect(points[0].delta.qa, 5);

      // The missing day carries the previous cumulative forward, delta zero.
      expect(points[1].observed, isFalse);
      expect(points[1].cumulative, _bucket(p: 10, qa: 5, pc: 50));
      expect(points[1].delta, EMPTY_BUCKET);

      // Deltas resume from the carried values, not from zero.
      expect(points[2].observed, isTrue);
      expect(points[2].delta.p, 15);
      expect(points[2].delta.qa, 7);
      expect(points[2].delta.pc, 10);
    });

    test('carry-forward starts before the window: no fictitious jump', () {
      final doc = _doc({
        '2026-09-20': _bucket(p: 100, qa: 50),
        '2026-09-30': _bucket(p: 130, qa: 60),
      });
      // 7-day window ending 2026-09-30 starts on 2026-09-24.
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.d7, '2026-09-30');

      expect(points.first.key, '2026-09-24');
      expect(points.first.observed, isFalse);
      expect(points.first.cumulative.p, 100);
      expect(points.first.delta.p, 0);

      final last = points.last;
      expect(last.key, '2026-09-30');
      expect(last.delta.p, 30); // 130 - 100, not 130 - 0
      expect(last.delta.qa, 10);
    });

    test('cumulative decreases clamp to zero delta; levels stay signed', () {
      final doc = _doc({
        '2026-09-25': _bucket(p: 100, qa: 50, pc: 70),
        // A correction lowered the stored totals; per-day effort can't be negative.
        '2026-09-26': _bucket(p: 90, qa: 45, pc: 60),
      });
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-26');

      expect(points[1].delta.p, 0);
      expect(points[1].delta.qa, 0);
      // pc/ep/dp report movement, which may legitimately be negative.
      expect(points[1].delta.pc, -10);
    });

    test('seeded flag marks days at or before seededUpTo', () {
      final doc = _doc({
        '2026-09-25': _bucket(p: 1000, qa: 500),
        '2026-09-26': _bucket(p: 1010, qa: 502),
        '2026-09-27': _bucket(p: 1020, qa: 505),
      }, seededUpTo: '2026-09-26');
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-27');

      expect(points[0].seeded, isTrue);
      expect(points[1].seeded, isTrue);
      expect(points[2].seeded, isFalse);
    });

    test('range all starts at firstDay', () {
      final doc = _doc({
        '2026-08-01': _bucket(p: 5),
        '2026-09-30': _bucket(p: 50),
      }, firstDay: '2026-08-01');
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-30');
      expect(points.first.key, '2026-08-01');
      // Aug 1 → Sep 30 inclusive.
      expect(points.length, 1 + diffDayKeys('2026-08-01', '2026-09-30'));
    });

    test('window in the future yields no points', () {
      final doc = _doc({'2026-09-25': _bucket(p: 10)});
      // todayKey before the only snapshot: span < 0.
      expect(buildAnalyticsSeries(doc, AnalyticsRange.d7, '2026-09-20'), isEmpty);
    });
  });

  group('sumDelta / effortOf', () {
    test('sums one delta field; effort counts qa+ea+da+ta+ga+rd', () {
      final doc = _doc({
        '2026-09-25': _bucket(p: 10, qa: 5, ta: 3),
        '2026-09-26': _bucket(p: 16, qa: 8, ta: 7),
      });
      final points =
          buildAnalyticsSeries(doc, AnalyticsRange.all, '2026-09-26');
      expect(sumDelta(points, 'p'), 16);
      expect(sumDelta(points, 'qa'), 8);
      expect(effortOf(points[0]), 5 + 3);
      expect(effortOf(points[1]), 3 + 4);
    });
  });

  group('previousPeriodSeries', () {
    test('returns empty for the unbounded range', () {
      final doc = _doc({'2026-09-25': _bucket(p: 10)});
      expect(previousPeriodSeries(doc, AnalyticsRange.all, '2026-10-01'), isEmpty);
      expect(previousPeriodSeries(null, AnalyticsRange.d7, '2026-10-01'), isEmpty);
    });

    test('shifts the window back by exactly the range length', () {
      final doc = _doc({
        '2026-09-18': _bucket(p: 10),
        '2026-09-25': _bucket(p: 40),
        '2026-10-01': _bucket(p: 90),
      });
      final prev =
          previousPeriodSeries(doc, AnalyticsRange.d7, '2026-10-01');
      // Current window: 09-25..10-01. Previous: 09-18..09-24.
      expect(prev.first.key, '2026-09-18');
      expect(prev.last.key, '2026-09-24');
      expect(prev.length, 7);
    });
  });

  group('computeAnalyticsStreak', () {
    test('empty history has no streak', () {
      final streak = computeAnalyticsStreak({}, '2026-10-01');
      expect(streak.current, 0);
      expect(streak.best, 0);
      expect(streak.lastDay, '');
    });

    test('counts consecutive studied days', () {
      final days = {
        '2026-09-28': _bucket(qa: 3),
        '2026-09-29': _bucket(qa: 8),
        '2026-09-30': _bucket(qa: 12),
      };
      final streak = computeAnalyticsStreak(days, '2026-09-30');
      expect(streak.current, 3);
      expect(streak.best, 3);
      expect(streak.lastDay, '2026-09-30');
    });

    test('a gap breaks the run; best survives', () {
      final days = {
        '2026-09-25': _bucket(qa: 3),
        '2026-09-26': _bucket(qa: 8),
        // 09-27: no snapshot at all — the app was not opened.
        '2026-09-28': _bucket(qa: 10),
      };
      final streak = computeAnalyticsStreak(days, '2026-09-28');
      expect(streak.current, 1);
      expect(streak.best, 2);
      expect(streak.lastDay, '2026-09-28');
    });

    test('an unstudied today does not break the current streak', () {
      final days = {
        // Kathmandu midnight boundary: the user studied 09-29 and 09-30,
        // and "today" (10-01) simply has no snapshot yet.
        '2026-09-29': _bucket(qa: 3),
        '2026-09-30': _bucket(qa: 8),
        // A snapshot exists for today but nothing new happened: zero effort.
        '2026-10-01': _bucket(qa: 8),
      };
      final streak = computeAnalyticsStreak(days, '2026-10-01');
      expect(streak.current, 2);
      expect(streak.best, 2);
      // lastDay is the last day with real effort, not today.
      expect(streak.lastDay, '2026-09-30');
    });

    test('effort needs real work: points alone do not extend a streak', () {
      // Only points grew (e.g. time points); no qa/ea/da/ta/ga/rd movement.
      final days = {
        '2026-09-30': _bucket(p: 50),
        '2026-10-01': _bucket(p: 55),
      };
      final streak = computeAnalyticsStreak(days, '2026-10-01');
      expect(streak.current, 0);
      expect(streak.best, 0);
      expect(streak.lastDay, '');
    });
  });

  group('parseAnalyticsDocument', () {
    test('normalises buckets, skips non-day keys, keeps streak', () {
      final doc = parseAnalyticsDocument({
        'courseId': 'c1',
        'percent': 72.5,
        'points': 300,
        'streak': {'current': 4, 'best': 9, 'lastDay': '2026-09-30'},
        'seededUpTo': '2026-09-20',
        'days': {
          '2026-09-25': {'p': 300, 'qa': 'not-a-number', 'pc': 72.5},
          'not-a-day': {'p': 999},
        },
      }, 'sub1');

      expect(doc.courseId, 'c1');
      expect(doc.subcourseId, 'sub1');
      expect(doc.percent, 72.5);
      expect(doc.points, 300);
      expect(doc.streak.current, 4);
      expect(doc.streak.best, 9);
      expect(doc.streak.lastDay, '2026-09-30');
      expect(doc.seededUpTo, '2026-09-20');
      expect(doc.days.keys, ['2026-09-25']);
      expect(doc.days['2026-09-25']!.p, 300);
      expect(doc.days['2026-09-25']!.qa, 0); // coerced
      expect(doc.days['2026-09-25']!.pc, 72.5);
      // firstDay falls back to the earliest stored day.
      expect(doc.firstDay, '2026-09-25');
    });

    test('missing breakdown stays null; subcourseId defaults to the argument', () {
      final doc = parseAnalyticsDocument({'days': {}}, 'fallback-sub');
      expect(doc.breakdown, isNull);
      expect(doc.subcourseId, 'fallback-sub');
      expect(doc.firstDay, '');
    });
  });
}
