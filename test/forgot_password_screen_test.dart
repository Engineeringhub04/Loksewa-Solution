import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/screens/auth/forgot_password_screen.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/preloading.dart';

GoRouter _router() {
  return GoRouter(
    initialLocation: '/forgot-password',
    routes: [
      GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
    ],
  );
}

/// The form shows instantly — the 1s preloading shimmer was removed
/// (2026-10-10). NEVER pumpAndSettle — the AnimatedSwitcher is mid-flight
/// after taps.
Future<void> _pumpScreen(WidgetTester tester) async {
  // Tall surface: the code step (3 fields + buttons) must fit on screen
  // for taps to land.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
  await tester.pump(const Duration(milliseconds: 100));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _submitEmail(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextField), email);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('Send Code'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Drives step 1 (mocked ok) into the code step, then fills code +
/// passwords so the Reset button enables.
Future<void> _reachVerify(WidgetTester tester) async {
  await _submitEmail(tester, 'user@example.com');
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(1), '123456');
  await tester.enterText(fields.at(2), 'newpass1');
  await tester.enterText(fields.at(3), 'newpass1');
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  tearDown(() {
    // Never leak a mock client into another test.
    CfApi.setTestClient(null);
  });

  testWidgets('rate_limited shows an in-page banner, not a popup',
      (tester) async {
    CfApi.setTestClient(
      MockClient((_) async =>
          http.Response('{"ok":false,"error":"rate_limited"}', 429)),
    );
    await _pumpScreen(tester);

    await _submitEmail(tester, 'user@example.com');

    expect(
      find.textContaining('already requested a code recently'),
      findsOneWidget,
    );
    // The banner is in-page: no modal popup, no code step.
    expect(find.byType(AppModalShell), findsNothing);
    expect(find.text('Verification Code'), findsNothing);
    // The form stays visible so the user can act on the banner.
    expect(find.text('Send Code'), findsOneWidget);
  });

  testWidgets('unknown error shows the generic banner', (tester) async {
    CfApi.setTestClient(
      MockClient((_) async =>
          http.Response('{"ok":false,"error":"server_error"}', 500)),
    );
    await _pumpScreen(tester);

    await _submitEmail(tester, 'user@example.com');

    expect(
      find.textContaining('Something went wrong'),
      findsOneWidget,
    );
    expect(find.byType(AppModalShell), findsNothing);
    expect(find.text('Verification Code'), findsNothing);
  });

  testWidgets('form shows instantly — no preloading shimmer', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pump(const Duration(milliseconds: 100));

    // The form is already there on the first frames: no PreloadingWidget,
    // no 1s shimmer wait.
    expect(find.byType(PreloadingWidget), findsNothing);
    expect(find.text('Send Code'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('account_not_found shows the no-account banner, not a popup',
      (tester) async {
    CfApi.setTestClient(
      MockClient((_) async =>
          http.Response('{"ok":false,"error":"account_not_found"}', 404)),
    );
    await _pumpScreen(tester);

    await _submitEmail(tester, 'ghost@example.com');

    expect(
      find.text('No account found with this email address.'),
      findsOneWidget,
    );
    expect(find.byType(AppModalShell), findsNothing);
    expect(find.text('Verification Code'), findsNothing);
    // The form stays visible so the user can correct the email.
    expect(find.text('Send Code'), findsOneWidget);
  });

  testWidgets('ok:true reveals the code + new-password step', (tester) async {
    CfApi.setTestClient(
      MockClient((_) async => http.Response('{"ok":true}', 200)),
    );
    await _pumpScreen(tester);

    await _submitEmail(tester, 'user@example.com');

    expect(find.text('Enter Code'), findsOneWidget);
    expect(find.text('Verification Code'), findsOneWidget);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets('wrong code shows the AppModalShell error popup',
      (tester) async {
    CfApi.setTestClient(MockClient((req) async {
      if (req.url.path.endsWith('/verify')) {
        return http.Response('{"ok":false,"error":"wrong_code"}', 401);
      }
      return http.Response('{"ok":true}', 200);
    }));
    await _pumpScreen(tester);
    await _reachVerify(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reset Password'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppModalShell), findsOneWidget);
    expect(find.textContaining('incorrect or has expired'), findsOneWidget);
  });

  testWidgets('verify success shows the popup and returns to login',
      (tester) async {
    CfApi.setTestClient(
      MockClient((_) async => http.Response('{"ok":true}', 200)),
    );
    await _pumpScreen(tester);
    await _reachVerify(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reset Password'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppModalShell), findsOneWidget);
    expect(
      find.textContaining('reset successfully'),
      findsOneWidget,
    );

    await tester.tap(find.descendant(
      of: find.byType(AppModalShell),
      matching: find.text('Back to Login'),
    ));
    // Dialog pop + GoRouter page transition both need to run out.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(ForgotPasswordScreen), findsNothing);
  });
}
