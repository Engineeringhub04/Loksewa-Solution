// Widget tests for the analytics screen (lib/screens/user/analytics_screen.dart).
//
// The screen is exercised through its constructor seams — a fake uid, fake
// identity loader, fake document/subcourse fetchers and a fake board fetcher —
// so no test ever touches Firestore. Fixtures are built in pure Dart from
// DayBuckets; the real data-layer functions (buildAnalyticsSeries, summarise,
// deriveInsights, cohortFacts) run against them, so the tests verify the
// screen's wiring to that layer rather than re-implementing it.
//
// All animations on the page are finite draw-ins, so pumps stay bounded — no
// pumpAndSettle (PreloadingWidget's infinite spinner is only on screen before
// the first fake resolves).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/user/analytics_screen.dart';
import 'package:loksewa_solution/services/analytics/analytics_store.dart';
import 'package:loksewa_solution/services/analytics/analytics_types.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/widgets/analytics/analytics_hero.dart';
import 'package:loksewa_solution/services/analytics/analytics_strings.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// A document with [days] consecutive daily snapshots ending today.
///
/// Cumulative totals grow linearly so every derived number is predictable:
/// accuracy settles at [pc], total points at [finalPoints]. Practice is the
/// only touched source (exam/dailyTest/qotd/gkPm/reading stay at zero), which
/// gives the insights section a strength and an untouched focus area.
/// [seededDays] marks the leading days as reconstructed.
AnalyticsDocument _fakeDocument({
  required String subcourseId,
  int days = 20,
  int seededDays = 0,
  double pc = 80,
  int finalPoints = 1234,
}) {
  final now = DateTime.now();
  final first = now.subtract(Duration(days: days - 1));
  final daysMap = <String, DayBucket>{};
  for (var i = 0; i < days; i++) {
    final date = first.add(Duration(days: i));
    final frac = (i + 1) / days;
    daysMap[_dayKey(date)] = DayBucket(
      p: (finalPoints * frac).round(),
      pc: pc,
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
    subcourseId: subcourseId,
    percent: pc,
    points: finalPoints,
    breakdown: const {
      'practice': {'attempted': 200, 'correct': 160},
      'qotd': {'attempts': 40, 'correct': 32},
    },
    seededUpTo: seededDays > 0
        ? _dayKey(first.add(Duration(days: seededDays - 1)))
        : '',
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

/// Subcourse rows carry an empty courseId so the name-resolution path (which
/// would list the course catalogue over HTTP) stays hermetic; the screen falls
/// back to the enrolled identity names.
List<AnalyticsSubcourseRow> _rows(List<String> ids) => ids
    .map((id) => AnalyticsSubcourseRow(
        subcourseId: id, courseId: '', percent: 80, points: 1234))
    .toList();

Widget _wrap(AnalyticsScreen screen) {
  return MaterialApp(home: Scaffold(body: screen));
}

/// Settle that waits out the entrance choreography. The async boot chain mounts
/// the content late (often during the second pump), and each StaggerEntrance
/// then runs a delay (up to 480ms) plus a 450ms slide. Tapping while a
/// SlideTransition is mid-flight misses: the transform shifts the target away
/// from its hit-test position. So after the initial pumps we keep pumping
/// until every SlideTransition has settled at Offset.zero (bounded — no
/// pumpAndSettle, which would hang on the infinite PreloadingWidget and the
/// MethodFooter's 30s timer).
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

/// Pumps the screen on a tall surface so every lazily-built section mounts in
/// the first frame — no scrolling needed. Scrolling would unmount/remount
/// sections, and each StaggerEntrance mount schedules new one-shot delay
/// timers; with everything mounted up front, a single two-phase settle fires
/// them all and none are pending at teardown.
Future<void> _pumpScreen(WidgetTester tester, AnalyticsScreen screen) async {
  tester.view.physicalSize = const Size(800, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(screen));
  await _settle(tester);
}

AnalyticsScreen _screen({
  String debugUid = 'test-uid',
  Future<AnalyticsIdentity> Function(String uid)? loadIdentity,
  Future<AnalyticsDocument?> Function(String uid, String subcourseId)?
      fetchDocument,
  Future<List<AnalyticsSubcourseRow>> Function(String uid)? listSubcourses,
  Future<List<MainLeaderboardRow>> Function(String subcourseId)? fetchBoard,
}) {
  return AnalyticsScreen(
    debugUid: debugUid,
    loadIdentity: loadIdentity ?? (_) async => _identity,
    fetchDocument: fetchDocument ??
        (_, subcourseId) async =>
            _fakeDocument(subcourseId: subcourseId),
    listSubcourses:
        listSubcourses ?? (_) async => _rows(const ['s1']),
    fetchBoard: fetchBoard ?? (_) async => [],
  );
}

void main() {
  group('AnalyticsScreen', () {
    testWidgets('hero shows accuracy, points and course names',
        (tester) async {
      await _pumpScreen(tester, _screen());

      final hero = find.byType(AnalyticsHero);
      expect(hero, findsOneWidget);
      expect(
          find.descendant(of: hero, matching: find.text('80%')),
          findsOneWidget);
      expect(
          find.descendant(of: hero, matching: find.text('1234')),
          findsOneWidget);
      expect(
          find.descendant(
              of: hero, matching: find.text('GK & Current Affairs')),
          findsOneWidget);
      expect(
          find.descendant(of: hero, matching: find.text('GK Basics')),
          findsOneWidget);
    });

    testWidgets('range switch changes the recorded-days caption',
        (tester) async {
      await _pumpScreen(tester, _screen());

      expect(find.text('20 recorded day(s)'), findsOneWidget);

      await tester.tap(find.text('7 days'));
      await tester.pump();

      expect(find.text('7 recorded day(s)'), findsOneWidget);
      expect(find.text('20 recorded day(s)'), findsNothing);
    });

    testWidgets('seeded leading days show the estimate note',
        (tester) async {
      await _pumpScreen(tester, _screen(
        fetchDocument: (_, subcourseId) async =>
            _fakeDocument(subcourseId: subcourseId, seededDays: 13),
      ));

      expect(
          find.text(
              'The first 13 day(s) of this range are estimated from your totals.'),
          findsOneWidget);
    });

    testWidgets('cohort board loads lazily behind the tap', (tester) async {
      var boardCalls = 0;
      MainLeaderboardRow row(String uid, int points) => MainLeaderboardRow(
            id: uid,
            uid: uid,
            name: uid,
            photoURL: null,
            isPro: false,
            percent: 80,
            points: points,
            usageSeconds: 0,
          );
      await _pumpScreen(tester, _screen(
        fetchBoard: (_) async {
          boardCalls++;
          return [row('u-high', 2000), row('test-uid', 1500), row('u-low', 1000)];
        },
      ));

      expect(boardCalls, 0);
      expect(find.text('Where you stand'), findsNothing);

      await tester.tap(find.text('Load comparison'));
      await _settle(tester);

      expect(boardCalls, 1);
      expect(find.text('Where you stand'), findsOneWidget);
      expect(find.text('Top 67%'), findsOneWidget);
    });

    testWidgets('switching subcourse resets selections and reloads',
        (tester) async {
      final docCalls = <String>[];
      await _pumpScreen(tester, _screen(
        listSubcourses: (_) async => _rows(const ['s1', 's2']),
        fetchDocument: (_, subcourseId) async {
          docCalls.add(subcourseId);
          return _fakeDocument(
              subcourseId: subcourseId,
              finalPoints: subcourseId == 's2' ? 9999 : 1234);
        },
      ));
      expect(docCalls, ['s1']);

      // Tap a heatmap day: the detail pill appears.
      final todayKey = _dayKey(DateTime.now());
      final cell = find.byKey(ValueKey('heatmap-cell-$todayKey'));
      await tester.tap(cell);
      await tester.pump();
      expect(
          find.textContaining('activities on this day'), findsOneWidget);

      // Open the picker from the hero and switch subcourse.
      await tester.tap(find.text('GK Basics'));
      // Two pumps: the first runs the build that flips the picker's `visible`
      // flag (the sheet is shown from a post-frame callback), the second
      // runs the bottom sheet's entrance animation. Then wait out the route
      // transition — tapping an option mid-animation misses its hit target.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Unnamed sub-course'), findsOneWidget);
      await tester.tap(find.text('Unnamed sub-course'));
      // The sheet pops, the selection callback fires, and the async reload
      // chain (fetchDocument → setState → rebuild) needs a second pump.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // A fresh document was fetched for s2 and the day selection is gone.
      expect(docCalls, ['s1', 's2']);
      expect(find.textContaining('activities on this day'), findsNothing);
      final hero = find.byType(AnalyticsHero);
      expect(
          find.descendant(of: hero, matching: find.text('9999')),
          findsOneWidget);
    });

    testWidgets('insights section renders from source stats', (tester) async {
      await _pumpScreen(tester, _screen());

      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Your strength'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
    });

    testWidgets('empty uid shows the choose-a-course gate', (tester) async {
      await _pumpScreen(tester, _screen(debugUid: ''));

      expect(
          find.text('Choose a course to see your analytics'), findsOneWidget);
    });

    testWidgets('identity failure shows the error gate with retry',
        (tester) async {
      var identityCalls = 0;
      await _pumpScreen(tester, _screen(
        loadIdentity: (_) async {
          identityCalls++;
          throw Exception('nope');
        },
      ));

      expect(find.text('Data Not Found'), findsOneWidget);
      expect(identityCalls, 1);

      await tester.tap(find.text('Try Again'));
      await _settle(tester);
      expect(identityCalls, 2);
      expect(find.text('Data Not Found'), findsOneWidget);
    });

    testWidgets('Nepali language renders the Nepali error gate', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.setLanguage('ne');
      addTearDown(() => AppLanguage.setLanguage('en'));
      await _pumpScreen(tester, _screen(
        loadIdentity: (_) async => throw Exception('nope'),
      ));

      expect(find.text('डाटा भेटिएन'), findsOneWidget);
      expect(find.text('पुनः प्रयास गर्नुहोस्'), findsOneWidget);
      expect(find.text('Data Not Found'), findsNothing);
    });

    test('AnalyticsStrings switches with the app language', () async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.setLanguage('ne');
      expect(AnalyticsStrings.retry, 'पुनः प्रयास गर्नुहोस्');
      expect(AnalyticsStrings.range7d, '७ दिन');
      expect(AnalyticsStrings.cohortHeadline, 'तपाईं कहाँ हुनुहुन्छ');
      await AppLanguage.setLanguage('en');
      expect(AnalyticsStrings.retry, 'Try Again');
      expect(AnalyticsStrings.range7d, '7 days');
      expect(AnalyticsStrings.cohortHeadline, 'Where you stand');
    });

    testWidgets('missing document shows the no-data gate', (tester) async {
      await _pumpScreen(tester, _screen(
        fetchDocument: (_, __) async => null,
      ));

      expect(find.text('No data yet'), findsOneWidget);
      expect(
          find.textContaining('has not run for this sub-course yet'),
          findsOneWidget);
    });
  });

  group('AnalyticsHero bubbles', () {
    Widget hero({double width = 360}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: AnalyticsHero(
              courseName: 'A Very Long Course Name That Must Ellipsize',
              subcourseName: 'Subcourse With A Long Name Too',
              percent: 80,
              points: 1234,
              streak: 5,
              activeDays: 12,
              rank: 3,
              switchable: true,
              onPress: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('bubbles stay fully inside the card at 360dp',
        (tester) async {
      await tester.pumpWidget(hero());
      // The ring's draw-in is 600ms; a bounded pump, never pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);

      final card = tester.getRect(find.byType(AnalyticsHero));
      for (final key in [
        'hero-bubble-large',
        'hero-bubble-small',
        'hero-bubble-dot'
      ]) {
        final bubble = tester.getRect(find.byKey(ValueKey(key)));
        expect(card.contains(bubble.topLeft), isTrue,
            reason: '$key top-left escapes the card');
        expect(card.contains(bubble.bottomRight), isTrue,
            reason: '$key bottom-right escapes the card');
      }
    });

    testWidgets('no overflow at a narrow 320dp width', (tester) async {
      await tester.pumpWidget(hero(width: 320));
      await tester.pump(const Duration(milliseconds: 700));
      // RenderFlex overflow errors surface as test exceptions.
      expect(tester.takeException(), isNull);
      expect(find.byType(AnalyticsHero), findsOneWidget);
    });
  });
}
