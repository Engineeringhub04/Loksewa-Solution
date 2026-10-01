// Premium redesign tests for the admin Subscription Requests screens:
// - loading / denied (no signed-in user) states render with the same
//   language-aware strings as before the redesign (logic preserved);
// - the action zone (Approve/Reject) only exists once a record loads — it
//   must NOT render in loading or denied states;
// - both screens pump cleanly in light AND dark themes.
//
// Test lessons applied: tall physicalSize, many small pumps (never
// pumpAndSettle — the preloader spinner is an infinite animation).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/admin/admin_subscriptions_screen.dart';
import 'package:loksewa_solution/screens/admin/admin_subscription_detail_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
import 'package:loksewa_solution/widgets/subpage_header.dart';

/// Pumps [screen] under [theme]; advances with small pumps so the infinite
/// preloader animation never blocks the test.
Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(720, 1612);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: screen,
  ));
  await tester.pump();
  // No signed-in user -> _load throws _Denied quickly; a few small pumps
  // are enough for the FutureBuilder to land in the error branch.
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await AppLanguage.setLanguage('en');
  });

  group('admin subscriptions list (redesign)', () {
    testWidgets('shows the loading state on the very first frame',
        (tester) async {
      // Immediately after pumpWidget the FutureBuilder has not yet heard
      // the (fast-failing, no-user) future, so the loader branch renders.
      await tester.pumpWidget(
          const MaterialApp(home: AdminSubscriptionsScreen()));
      expect(find.byType(PreloadingWidget), findsOneWidget);
      expect(find.text('Loading Subscription...'), findsOneWidget);
    });

    testWidgets('no signed-in user -> access denied (logic preserved)',
        (tester) async {
      await _pumpScreen(tester, const AdminSubscriptionsScreen());
      expect(find.text('Access denied'), findsOneWidget);
      // Hero / filter / cards only render after data loads.
      expect(find.text('Subscription Requests'), findsOneWidget); // header
    });

    testWidgets('nepali strings in the denied branch', (tester) async {
      await AppLanguage.setLanguage('ne');
      await _pumpScreen(tester, const AdminSubscriptionsScreen());
      expect(find.text('पहुँच अस्वीकृत'), findsOneWidget);
    });

    testWidgets('action-free denied state in dark theme', (tester) async {
      await _pumpScreen(tester, const AdminSubscriptionsScreen(),
          theme: AppTheme.dark);
      expect(find.text('Access denied'), findsOneWidget);
      expect(find.byType(SubpageHeader), findsOneWidget);
    });

    testWidgets('scaffold keeps Column > header structure', (tester) async {
      await _pumpScreen(tester, const AdminSubscriptionsScreen());
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.body, isA<Column>());
      expect(
        find.descendant(
            of: find.byWidget(scaffold.body as Column),
            matching: find.byType(SubpageHeader)),
        findsOneWidget,
      );
    });
  });

  group('admin subscription detail (redesign)', () {
    testWidgets('shows the loading state on the very first frame',
        (tester) async {
      // Immediately after pumpWidget the FutureBuilder has not yet heard
      // the (fast-failing, no-user) future, so the loader branch renders.
      await tester.pumpWidget(const MaterialApp(
          home: AdminSubscriptionDetailScreen(id: 'test-id')));
      expect(find.byType(PreloadingWidget), findsOneWidget);
      expect(find.text('Loading Subscription...'), findsOneWidget);
      // The premium action zone must not exist before the record loads.
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('no signed-in user -> access denied, no action zone',
        (tester) async {
      await _pumpScreen(
          tester, const AdminSubscriptionDetailScreen(id: 'test-id'));
      expect(find.text('Access denied'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('nepali denied string', (tester) async {
      await AppLanguage.setLanguage('ne');
      await _pumpScreen(
          tester, const AdminSubscriptionDetailScreen(id: 'test-id'));
      expect(find.text('पहुँच अस्वीकृत'), findsOneWidget);
    });

    testWidgets('busy barrier stack structure preserved (no regression)',
        (tester) async {
      await _pumpScreen(
          tester, const AdminSubscriptionDetailScreen(id: 'test-id'));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final body = scaffold.body;
      expect(body, isA<Stack>(),
          reason: 'Scaffold body must stay a Stack so the busy dim barrier '
              'sits above the header');
      final first = (body as Stack).children.first;
      expect(first, isA<Column>());
      expect(
        find.descendant(
            of: find.byWidget(first), matching: find.byType(SubpageHeader)),
        findsOneWidget,
      );
    });

    testWidgets('pumps cleanly in dark theme', (tester) async {
      await _pumpScreen(
          tester, const AdminSubscriptionDetailScreen(id: 'test-id'),
          theme: AppTheme.dark);
      expect(find.text('Access denied'), findsOneWidget);
      expect(find.byType(SubpageHeader), findsOneWidget);
    });
  });
}
