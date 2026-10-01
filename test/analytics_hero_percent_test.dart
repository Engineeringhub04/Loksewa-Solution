// Regression tests for the profile/analytics percent mismatch.
// The hero reads ONLY the canonical leaderboard aggregate
// (computeMainLeaderboardScore + 50pt signup bonus) — the same numbers the
// Profile stats card and the Leaderboard board show. The analytics
// document's stored percent / day-bucket pc are fossils the Flutter app
// never writes; the hero must never render them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loksewa_solution/screens/user/analytics_screen.dart';
import 'package:loksewa_solution/services/analytics/analytics_store.dart';
import 'package:loksewa_solution/services/analytics/analytics_types.dart';
import 'package:loksewa_solution/services/main_leaderboard.dart';
import 'package:loksewa_solution/widgets/analytics/analytics_hero.dart';

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// A document whose top-level stored coverage ([topPercent]) deliberately
/// DIFFERS from the newest day-bucket's pc ([bucketPc]) — the state that
/// used to make the two rings disagree (profile 0%, analytics 1%).
AnalyticsDocument _mismatchDocument({
  required double topPercent,
  required double bucketPc,
}) {
  final now = DateTime.now();
  const days = 20;
  final first = now.subtract(const Duration(days: days - 1));
  final daysMap = <String, DayBucket>{};
  for (var i = 0; i < days; i++) {
    final date = first.add(Duration(days: i));
    final frac = (i + 1) / days;
    daysMap[_dayKey(date)] = DayBucket(
      p: (1234 * frac).round(),
      pc: bucketPc,
      s: 1800 * (i + 1),
      a: 5 * (i + 1),
      qa: 2 * (i + 1),
      qc: (1.6 * (i + 1)).round(),
      ta: 10 * (i + 1),
      tc: 8 * (i + 1),
    );
  }
  return AnalyticsDocument(
    courseId: 'c1',
    subcourseId: 's1',
    percent: topPercent,
    points: 1234,
    breakdown: const {
      'practice': {'attempted': 200, 'correct': 160},
      'qotd': {'attempts': 40, 'correct': 32},
    },
    seededUpTo: '',
    firstDay: _dayKey(first),
    days: daysMap,
  );
}

const _identity = AnalyticsIdentity(
  courseId: 'c1',
  subcourseId: 's1',
  courseName: 'GK & Current Affairs',
  subcourseName: 'GK Basics',
);

Widget _wrap(AnalyticsScreen screen) =>
    MaterialApp(home: Scaffold(body: screen));

/// Settles the entrance choreography without pumpAndSettle (which would hang
/// on the method footer's 30s timer).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 1000));
  for (var i = 0; i < 20; i++) {
    var pending = false;
    for (final e in find.byType(SlideTransition).evaluate()) {
      if ((e.widget as SlideTransition).position.value != Offset.zero) {
        pending = true;
        break;
      }
    }
    if (!pending) break;
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _pumpScreen(WidgetTester tester, AnalyticsScreen screen) async {
  tester.view.physicalSize = const Size(800, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(screen));
  await _settle(tester);
}

AnalyticsScreen _screen({
  required AnalyticsDocument document,
  required CanonicalStats canonical,
}) {
  return AnalyticsScreen(
    debugUid: 'test-uid',
    loadIdentity: (_) async => _identity,
    fetchDocument: (_, subcourseId) async => document,
    listSubcourses: (_) async => const [
      AnalyticsSubcourseRow(
          subcourseId: 's1', courseId: '', percent: 0, points: 1234),
    ],
    fetchBoard: (_) async => [],
    // The hero reads ONLY the canonical aggregate now — the document's
    // stored percent/pc are fossils the Flutter app never writes.
    loadCanonical: (_, __, ___) async => canonical,
  );
}

const _canonical33 = CanonicalStats(
  percent: 33,
  points: 777,
  activityCount: 10,
  breakdown: <String, dynamic>{},
);

const _canonical42 = CanonicalStats(
  percent: 42,
  points: 2000,
  activityCount: 50,
  breakdown: <String, dynamic>{},
);

Widget _hero(double percent) {
  return MaterialApp(
    home: Scaffold(
      body: AnalyticsHero(
        courseName: 'Course',
        subcourseName: 'Sub',
        percent: percent,
        points: 10,
        streak: 2,
        activeDays: 3,
      ),
    ),
  );
}

void main() {
  group('AnalyticsHero coverage percent (Part 4)', () {
    testWidgets(
        'hero shows the canonical percent, not the snapshot fossils',
        (tester) async {
      // Stored coverage 0%, newest bucket pc 1%: the old code rendered the
      // hero as 1% while the profile card showed 0%. The hero now reads only
      // the canonical aggregate (33% here — distinct from both fossils).
      await _pumpScreen(
          tester,
          _screen(
              document: _mismatchDocument(topPercent: 0, bucketPc: 1),
              canonical: _canonical33));

      final hero = find.byType(AnalyticsHero);
      expect(hero, findsOneWidget);
      expect(
          find.descendant(of: hero, matching: find.text('33%')),
          findsOneWidget);
      expect(
          find.descendant(of: hero, matching: find.text('0%')),
          findsNothing);
      expect(
          find.descendant(of: hero, matching: find.text('1%')),
          findsNothing);
    });

    testWidgets('hero agrees with the profile card at a nonzero value',
        (tester) async {
      await _pumpScreen(
          tester,
          _screen(
              document:
                  _mismatchDocument(topPercent: 42, bucketPc: 87),
              canonical: _canonical42));

      final hero = find.byType(AnalyticsHero);
      expect(
          find.descendant(of: hero, matching: find.text('42%')),
          findsOneWidget);
      expect(
          find.descendant(of: hero, matching: find.text('87%')),
          findsNothing);
    });

    testWidgets('hero label keeps one decimal for sub-10% coverage',
        (tester) async {
      await tester.pumpWidget(_hero(0.1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('0.1%'), findsOneWidget);
    });

    testWidgets('hero label stays whole for whole coverage', (tester) async {
      await tester.pumpWidget(_hero(80));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('80%'), findsOneWidget);
    });
  });
}
