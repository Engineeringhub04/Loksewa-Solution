import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/auth/help_center_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';

GoRouter _router() {
  return GoRouter(
    initialLocation: '/help',
    routes: [
      GoRoute(
          path: '/help', builder: (_, __) => const HelpCenterScreen()),
      GoRoute(
          path: '/settings/report-problem',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('report-marker')))),
      GoRoute(
          path: '/contact-us',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('contact-marker')))),
      GoRoute(
          path: '/feedback',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('feedback-marker')))),
    ],
  );
}

/// Advances the fake clock past every StaggerEntrance delay (≤300ms) plus
/// its 450ms animation — three rounds, because a pump's own frame can mount
/// new (previously below-fold) StaggerEntrances whose timers then need a
/// later pump to fire.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
  await tester.pump();
  await _settle(tester);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await _settle(tester);
}

/// Scrolls to the very bottom so every section is mounted in the tree.
Future<void> _scrollToBottom(WidgetTester tester, String footnote) async {
  await tester.scrollUntilVisible(find.text(footnote), 400, scrollable: find.byType(Scrollable).first);
  await _settle(tester);
}

void main() {
  setUp(() => AppLanguage.current.value = 'en');
  tearDown(() => AppLanguage.current.value = 'en');

  group('HelpCenterScreen', () {
    testWidgets('renders hero, search, chips, FAQ, sections, contacts',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      // Hero.
      expect(find.text('Help Center'), findsWidgets); // header + hero
      expect(find.text('Answers to the questions we hear most.'),
          findsOneWidget);
      // Search.
      expect(find.byType(TextField), findsOneWidget);
      // Topic chips (All + 8 topics).
      expect(find.text('All topics'), findsOneWidget);
      expect(find.text('Getting started'), findsOneWidget);
      expect(find.text('Study & practice'), findsOneWidget);
      expect(find.text('Exams'), findsOneWidget);
      expect(find.text('Daily Test'), findsOneWidget);
      expect(find.text('Current affairs'), findsOneWidget);
      expect(find.text('Progress & points'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('App & settings'), findsOneWidget);
      // All 24 questions visible with no filter.
      expect(find.text('How do I choose my course?'), findsOneWidget);
      expect(find.text('Where do I see my rank?'), findsOneWidget);
      expect(find.text('How do I delete my account?'), findsOneWidget);
      expect(find.text('How do I report a problem?'), findsOneWidget);

      // Sections live below the fold — scroll them into the tree.
      await _scrollToBottom(tester,
          'Most reports get a response within 1-2 working days.');

      // Still stuck + quick actions.
      expect(find.text('Still stuck?'), findsOneWidget);
      expect(find.text('Report a Problem'), findsOneWidget);
      expect(find.text('Contact Us'), findsOneWidget);
      expect(find.text('Feedback'), findsOneWidget);
      // Reach us directly (display-only values).
      expect(find.text('Still stuck? Reach us directly'), findsOneWidget);
      expect(find.text('contact@kbr.com.np'), findsOneWidget);
      expect(find.text('+977-9810768297'), findsOneWidget);
      expect(find.text('kbr.com.np'), findsOneWidget);
      // Footnote.
      expect(
          find.text('Most reports get a response within 1-2 working days.'),
          findsOneWidget);
    });

    testWidgets('search filters questions live', (WidgetTester tester) async {
      await _pumpScreen(tester);

      await _search(tester, 'bookmark');

      expect(find.text('Why does it say my bookmark slots are full?'),
          findsOneWidget);
      expect(find.text('Can I save a question for later?'), findsOneWidget);
      expect(find.text('How do I choose my course?'), findsNothing);
      expect(find.text('Where do I see my rank?'), findsNothing);
    });

    testWidgets('search matches answers too, not just questions',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      // 'coverage' appears only in the progress.1 ANSWER.
      await _search(tester, 'coverage');

      expect(find.text('How is my profile percentage calculated?'),
          findsOneWidget);
      expect(find.text('How often does Analytics refresh?'), findsNothing);
    });

    testWidgets('topic chips hide while a query is active',
        (WidgetTester tester) async {
      await _pumpScreen(tester);
      expect(find.text('All topics'), findsOneWidget);

      await _search(tester, 'exam');
      expect(find.text('All topics'), findsNothing);
      expect(find.text('Exams'), findsNothing);

      // Clearing the query brings the chips back.
      await tester.tap(find.byIcon(Icons.close));
      await _settle(tester);
      expect(find.text('All topics'), findsOneWidget);
      expect(find.text('Exams'), findsOneWidget);
    });

    testWidgets('chip tap filters by topic and clears the open FAQ',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      // Open a question first.
      await tester.tap(find.text('How do I choose my course?'));
      await _settle(tester);
      expect(
          find.text(
              'On your first login the app asks for a course and a sub-course. You can change it any time from Profile → Edit Profile.'),
          findsOneWidget);

      // Selecting a topic filters the list and closes the open row.
      await tester.tap(find.text('Exams'));
      await _settle(tester);
      expect(
          find.text(
              'On your first login the app asks for a course and a sub-course. You can change it any time from Profile → Edit Profile.'),
          findsNothing);
      expect(find.text('When can I start an exam set?'), findsOneWidget);
      expect(find.text('What happens if I leave an exam midway?'),
          findsOneWidget);
      expect(find.text('Where do I see my rank?'), findsOneWidget);
      expect(find.text('How do I choose my course?'), findsNothing);

      // Tapping the active chip again clears the filter.
      await tester.tap(find.text('Exams'));
      await _settle(tester);
      expect(find.text('How do I choose my course?'), findsOneWidget);
      expect(find.text('Where do I see my rank?'), findsOneWidget);
    });

    testWidgets('accordion opens one question at a time',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      const a1 =
          'On your first login the app asks for a course and a sub-course. You can change it any time from Profile → Edit Profile.';
      const a2 =
          'Most practice material is free. A few exam sets and premium notes need a purchase, and that is always marked on the card before you open it.';

      // Nothing open initially.
      expect(find.text(a1), findsNothing);
      expect(find.text(a2), findsNothing);

      await tester.tap(find.text('How do I choose my course?'));
      await _settle(tester);
      expect(find.text(a1), findsOneWidget);
      expect(find.text(a2), findsNothing);

      // Opening a second row closes the first.
      await tester.tap(find.text('Is the app free to use?'));
      await _settle(tester);
      expect(find.text(a1), findsNothing);
      expect(find.text(a2), findsOneWidget);

      // Tapping the open row closes it.
      await tester.tap(find.text('Is the app free to use?'));
      await _settle(tester);
      expect(find.text(a2), findsNothing);
    });

    testWidgets('empty state on no match', (WidgetTester tester) async {
      await _pumpScreen(tester);

      await _search(tester, 'zzz-no-such-faq');
      expect(find.text('No FAQ available yet'), findsOneWidget);
      expect(find.text('We are writing the answers — check back soon.'),
          findsOneWidget);
      expect(find.text('How do I choose my course?'), findsNothing);
    });

    testWidgets('quick actions navigate to their routes',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      await tester.scrollUntilVisible(
          find.text('Report a Problem'), 400,
          scrollable: find.byType(Scrollable).first);
      await _settle(tester);
      await tester.tap(find.text('Report a Problem'));
      await tester.pump();
      await _settle(tester);
      expect(find.text('report-marker'), findsOneWidget);
    });

    testWidgets('renders Nepali strings when language is ne',
        (WidgetTester tester) async {
      AppLanguage.current.value = 'ne';
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pump();
      await _settle(tester);

      expect(find.text('सहायता केन्द्र'), findsWidgets); // header + hero
      expect(find.text('हामीले बेला-बेला सुन्ने प्रश्नका जवाफहरू।'),
          findsOneWidget);
      expect(find.text('सबै विषय'), findsOneWidget);
      expect(find.text('परीक्षा'), findsOneWidget);
      expect(find.text('मेरो कोर्स कसरी छान्ने?'), findsOneWidget);
      expect(find.text('How do I choose my course?'), findsNothing);
      expect(find.text('All topics'), findsNothing);

      await _scrollToBottom(
          tester, 'धेरैजसो रिपोर्टको जवाफ १-२ कार्यदिनभित्र आउँछ।');

      expect(find.text('अझ अप्ठ्यारो भयो?'), findsOneWidget);
      expect(find.text('अझ अप्ठ्यारो भयो? सिधै सम्पर्क गर्नुहोस्'),
          findsOneWidget);
      expect(find.text('समस्या रिपोर्ट गर्नुहोस्'), findsOneWidget);
      expect(find.text('Still stuck?'), findsNothing);
    });
  });
}
