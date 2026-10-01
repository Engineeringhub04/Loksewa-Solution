import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/profile_header.dart';
import 'package:loksewa_solution/widgets/profile_rows.dart';
import 'package:loksewa_solution/widgets/profile_stats_card.dart';

void main() {
  group('profile_service pure helpers', () {
    test('formatDob formats ISO dates in English', () {
      expect(formatDob('1990-01-05', nepali: false), '05 Jan 1990');
      expect(formatDob('2000-12-25', nepali: false), '25 Dec 2000');
    });

    test('formatDob formats ISO dates in Devanagari Nepali', () {
      expect(formatDob('1990-01-05', nepali: true), '०५ जन १९९०');
      expect(formatDob('2000-12-25', nepali: true), '२५ डिसे २०००');
    });

    test('formatDob returns invalid input as-is (mirrors the TS original)', () {
      expect(formatDob(null, nepali: false), isNull);
      expect(formatDob('', nepali: false), isNull);
      expect(formatDob('not-a-date', nepali: false), 'not-a-date');
      // Impossible calendar dates are rolled over by DateTime — rejected here.
      expect(formatDob('2001-02-30', nepali: false), '2001-02-30');
      expect(formatDob('1990-13-01', nepali: false), '1990-13-01');
    });

    test('hasActivePremium is stricter than the raw isPremium flag', () {
      expect(hasActivePremium(null), isFalse);

      const base = UserProfile(uid: 'u');
      expect(hasActivePremium(base), isFalse); // not premium at all

      expect(hasActivePremium(base.copyWith(isPremium: true)), isTrue);

      final future = base.copyWith(
        isPremium: true,
        premiumExpiryDate:
            DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      );
      expect(hasActivePremium(future), isTrue);

      final past = base.copyWith(
        isPremium: true,
        premiumExpiryDate:
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      );
      expect(hasActivePremium(past), isFalse);

      final garbage =
          base.copyWith(isPremium: true, premiumExpiryDate: 'soon-ish');
      expect(hasActivePremium(garbage), isFalse);
    });

    test('displayCoveragePercent matches scoring.ts', () {
      expect(displayCoveragePercent(0), 0);
      expect(displayCoveragePercent(double.nan), 0);
      expect(displayCoveragePercent(0.05), 0.1);
      expect(displayCoveragePercent(3.44), 3.4);
      expect(displayCoveragePercent(56.7), 57.0);
      expect(displayCoveragePercent(150), 100);
      expect(displayCoveragePercent(-5), 0);
    });

    test('testsTakenOf sums exam + dailyTest attempts', () {
      expect(
        testsTakenOf({
          'exam': {'attempts': 3},
          'dailyTest': {'attempts': 2},
        }),
        5,
      );
      expect(testsTakenOf({}), 0);
      expect(testsTakenOf({'exam': {}}), 0);
    });

    test('splitName splits legacy full names for the edit form', () {
      final m = splitName('John Michael Doe');
      expect(m['firstName'], 'John');
      expect(m['lastName'], 'Michael Doe');
      final empty = splitName('   ');
      expect(empty['firstName'], '');
      expect(empty['lastName'], '');
    });
  });

  group('profile widgets', () {
    // Many small pumps instead of pumpAndSettle: the stats ring and header
    // carry animations that never settle.
    Future<void> settleSmall(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    testWidgets('ProfileInfoRow empty shows the Add affordance and taps',
        (tester) async {
      useTallScreen(tester);
      var tapped = false;
      await tester.pumpWidget(wrap(ProfileInfoRow(
        icon: const Icon(Icons.person),
        label: 'Full Name',
        value: null,
        addLabel: 'Add your name',
        onAddPress: () => tapped = true,
      )));
      await settleSmall(tester);

      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Add your name'), findsOneWidget);
      await tester.tap(find.text('Add your name'));
      await settleSmall(tester);
      expect(tapped, isTrue);
    });

    testWidgets('ProfileInfoRow filled shows the value and is not pressable',
        (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(wrap(ProfileInfoRow(
        icon: const Icon(Icons.person),
        label: 'Full Name',
        value: 'Jane Doe',
        addLabel: 'Add your name',
        onAddPress: () {},
      )));
      await settleSmall(tester);

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Add your name'), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('ProfileMenuRow destructive renders the danger color',
        (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(wrap(ProfileMenuRow(
        icon: const Icon(Icons.delete_outline),
        label: 'Delete Account',
        destructive: true,
        onPress: () {},
      )));
      await settleSmall(tester);

      final label = tester.widget<Text>(find.text('Delete Account'));
      final danger =
          ExpoPalette.of(tester.element(find.text('Delete Account'))).danger;
      expect(label.style?.color, danger);
    });

    testWidgets('ProfileMenuRow tap fires onPress', (tester) async {
      useTallScreen(tester);
      var tapped = false;
      await tester.pumpWidget(wrap(ProfileMenuRow(
        icon: const Icon(Icons.info_outline),
        label: 'App Info',
        onPress: () => tapped = true,
      )));
      await settleSmall(tester);

      await tester.tap(find.text('App Info'));
      await settleSmall(tester);
      expect(tapped, isTrue);
    });

    testWidgets('ProfileStatsCard empty state invites the first activity',
        (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(wrap(ProfileStatsCard(
        score: null,
        stats: null,
        loading: false,
        subcourseName: null,
        onPress: () {},
      )));
      await settleSmall(tester);

      expect(
        find.text(
            'No stats yet — start any activity and they build up'),
        findsOneWidget,
      );
    });

    testWidgets('ProfileStatsCard renders coverage, points and the strip',
        (tester) async {
      useTallScreen(tester);
      var pressed = false;
      await tester.pumpWidget(wrap(ProfileStatsCard(
        score: const MainLeaderboardScore(
            percent: 45.6, points: 950, activityCount: 4),
        stats: const UserStats(rank: 12, streak: 5, testsTaken: 3),
        loading: false,
        subcourseName: 'Subcourse',
        onPress: () => pressed = true,
      )));
      await settleSmall(tester);

      // 45.6 -> displayCoveragePercent -> 46 -> "46%".
      expect(find.text('46%'), findsOneWidget);
      expect(find.text('950'), findsWidgets);
      expect(find.text('Subcourse'), findsOneWidget);
      expect(find.text('#12'), findsOneWidget); // rank
      expect(find.text('5'), findsWidgets); // streak
      expect(find.text('3'), findsWidgets); // tests

      await tester.tap(find.byType(ProfileStatsCard));
      await settleSmall(tester);
      expect(pressed, isTrue);
    });

    Widget header({required double offset}) => wrap(ProfileHeader(
          scrollOffset: offset,
          displayName: 'Jane Doe',
          photoURL: null,
          subcourseName: 'Subcourse',
          planLabel: 'Free Plan',
          isPremiumPlan: false,
          pro: false,
          languageShortLabel: 'EN',
          languageLabel: 'ENGLISH',
          onToggleLanguage: () {},
          onEditPress: () {},
          isDark: false,
          onToggleTheme: () {},
        ));

    Opacity layerOpacity(WidgetTester tester, String text) =>
        tester.widget<Opacity>(find
            .ancestor(
                of: find.text(text), matching: find.byType(Opacity))
            .first);

    testWidgets('ProfileHeader expanded shows the title, hides collapsed',
        (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(header(offset: 0));
      await settleSmall(tester);

      expect(find.text('Profile'), findsWidgets);
      expect(layerOpacity(tester, 'Edit Profile').opacity, 0.0);
    });

    testWidgets('ProfileHeader collapsed reveals the Edit Profile button',
        (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(header(offset: 150));
      await settleSmall(tester);

      expect(layerOpacity(tester, 'Edit Profile').opacity, 1.0);
      expect(layerOpacity(tester, 'Profile').opacity, 0.0);
    });
  });
}
