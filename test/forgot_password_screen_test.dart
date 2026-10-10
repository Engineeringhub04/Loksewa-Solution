import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/screens/auth/forgot_password_screen.dart';
import 'package:loksewa_solution/services/password_reset_service.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

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

/// The shimmer shows first (~1s), then the form reveals.
/// NEVER pumpAndSettle — the preloading spinner is an infinite animation.
Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 1100)); // shimmer done
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _submitEmail(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextField), email);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('Send Reset Link'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() {
    // Never leak a mock client into another test.
    PasswordResetService.setTestClient(null);
  });

  testWidgets('rate_limited shows an in-page banner, not a popup',
      (tester) async {
    PasswordResetService.setTestClient(
      MockClient(
          (_) async => http.Response('{"ok":false,"reason":"rate_limited"}', 200)),
    );
    await _pumpScreen(tester);

    await _submitEmail(tester, 'user@example.com');

    expect(
      find.textContaining("already requested a password reset link today"),
      findsOneWidget,
    );
    // The banner is in-page: no modal popup, no "check your email" state.
    expect(find.byType(AppModalShell), findsNothing);
    expect(find.text('Check Your Email'), findsNothing);
    // The form stays visible so the user can act on the banner.
    expect(find.text('Send Reset Link'), findsOneWidget);
  });

  testWidgets('no_provider shows the service-unavailable banner',
      (tester) async {
    PasswordResetService.setTestClient(
      MockClient(
          (_) async => http.Response('{"ok":false,"reason":"no_provider"}', 200)),
    );
    await _pumpScreen(tester);

    await _submitEmail(tester, 'user@example.com');

    expect(
      find.textContaining('Email service is not configured yet'),
      findsOneWidget,
    );
    expect(find.byType(AppModalShell), findsNothing);
    expect(find.text('Check Your Email'), findsNothing);
  });

  testWidgets('ok:true shows the existing check-your-email UI', (tester) async {
    PasswordResetService.setTestClient(
      MockClient((_) async => http.Response('{"ok":true}', 200)),
    );
    await _pumpScreen(tester);

    await _submitEmail(tester, 'user@example.com');

    expect(find.text('Check Your Email'), findsOneWidget);
    expect(find.textContaining('valid for 1 hour'), findsOneWidget);
  });
}
