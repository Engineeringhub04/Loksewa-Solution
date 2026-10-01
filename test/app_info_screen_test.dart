import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/auth/app_info_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/widgets/status_pill.dart';

// The screen is a lazily-built ListView whose sections and rows each carry a
// SyllabusEntrance (delayed AnimationController + Future.delayed). Pump it on
// a very tall test surface so every section builds at once — no scrolling,
// no half-built sections, no timers left pending at dispose.
// (pumpAndSettle never settles while the entrance animations are scheduled,
// so settle with explicit durations instead. NOTE: settle with many small
// pumps, not one big jump — a single large pump() leaves taps on
// below-the-fold rows unregistered by the gesture arena.)
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpAppInfo(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    const MaterialApp(home: AppInfoScreen()),
  );
  await _settle(tester);
}

Future<void> _pumpAppInfoRouter(
    WidgetTester tester, GoRouter router) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await _settle(tester);
}

void main() {
  tearDown(() => AppLanguage.current.value = 'en');

  group('AppInfoScreen — identity block', () {
    testWidgets('logo, app name, tagline and version pill render',
        (WidgetTester tester) async {
      await _pumpAppInfo(tester);

      expect(find.text('Loksewa Solution'), findsOneWidget);
      expect(find.text('Prepare Smarter, Score Higher'), findsOneWidget);
      expect(find.text('Version 1.0.36'), findsOneWidget);
      expect(find.byType(StatusPill), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });
  });

  group('AppInfoScreen — sections', () {
    testWidgets('About section shows the description',
        (WidgetTester tester) async {
      await _pumpAppInfo(tester);

      expect(find.text('About'), findsOneWidget);
      expect(
          find.text(
              "Nepal's trusted digital preparation platform for Loksewa and other competitive government exams."),
          findsOneWidget);
    });

    testWidgets('all five highlight rows render with titles',
        (WidgetTester tester) async {
      await _pumpAppInfo(tester);

      expect(find.text('What you get'), findsOneWidget);
      for (final title in [
        'Complete syllabus',
        'Mock tests & quizzes',
        'Daily current affairs',
        'Progress analytics',
        'Discussion forum',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(
          find.text(
              'Subject-wise notes and chapters mapped to the Loksewa syllabus.'),
          findsOneWidget);
    });

    testWidgets('Reach us rows show the website and support values',
        (WidgetTester tester) async {
      await _pumpAppInfo(tester);

      expect(find.text('Reach us'), findsOneWidget);
      expect(find.text('kbr.com.np'), findsOneWidget);
      expect(find.text('contact@kbr.com.np'), findsOneWidget);
    });

    testWidgets('four social brand buttons render in one row',
        (WidgetTester tester) async {
      await _pumpAppInfo(tester);

      expect(find.text('Follow Us'), findsOneWidget);
      for (final label in ['Facebook', 'YouTube', 'Instagram', 'X']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('legal rows render with chevrons',
        (WidgetTester tester) async {
      await _pumpAppInfo(tester);

      expect(find.text('Legal'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms and Conditions'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    });

    testWidgets('footer line keeps the flag emoji verbatim',
        (WidgetTester tester) async {
      await _pumpAppInfo(tester);

      expect(find.text('Made for Nepali students 🇳🇵'), findsOneWidget);
    });
  });

  group('AppInfoScreen — Nepali strings', () {
    testWidgets('Nepali language renders Devanagari section strings',
        (WidgetTester tester) async {
      AppLanguage.current.value = 'ne';
      await _pumpAppInfo(tester);

      expect(find.text('एप जानकारी'), findsOneWidget);
      expect(find.text('राम्रो तयारी, उच्च अंक'), findsOneWidget);
      expect(find.text('संस्करण १.०.३६'), findsOneWidget);
      expect(find.text('बारेमा'), findsOneWidget);
      expect(find.text('तपाईंले पाउने कुरा'), findsOneWidget);
      expect(find.text('सम्पर्क'), findsOneWidget);
      expect(find.text('हामीलाई फलो गर्नुहोस्'), findsOneWidget);
      expect(find.text('कानुनी'), findsOneWidget);
      expect(find.text('पूर्ण पाठ्यक्रम'), findsOneWidget);
      expect(find.text('वेबसाइट'), findsOneWidget);
      expect(find.text('सहयोग'), findsOneWidget);
      expect(find.text('गोपनीयता नीति'), findsOneWidget);
      // Brand name stays English in both languages.
      expect(find.text('Loksewa Solution'), findsOneWidget);
    });
  });

  group('AppInfoScreen — legal navigation', () {
    GoRouter buildRouter() => GoRouter(
          initialLocation: '/app-info',
          routes: [
            GoRoute(
                path: '/app-info',
                builder: (_, __) => const AppInfoScreen()),
            GoRoute(
                path: '/privacy-policy',
                builder: (_, __) =>
                    const Scaffold(body: Text('privacy-route'))),
            GoRoute(
                path: '/terms-conditions',
                builder: (_, __) =>
                    const Scaffold(body: Text('terms-route'))),
          ],
        );

    testWidgets('tapping Privacy Policy pushes /privacy-policy',
        (WidgetTester tester) async {
      await _pumpAppInfoRouter(tester, buildRouter());

      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('privacy-route'), findsOneWidget);
    });

    testWidgets('tapping Terms and Conditions pushes /terms-conditions',
        (WidgetTester tester) async {
      await _pumpAppInfoRouter(tester, buildRouter());

      await tester.tap(find.text('Terms and Conditions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('terms-route'), findsOneWidget);
    });
  });
}
