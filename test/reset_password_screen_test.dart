import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:loksewa_solution/screens/auth/reset_password_screen.dart';
import 'package:loksewa_solution/services/password_reset_service.dart';
import 'package:loksewa_solution/widgets/preloading.dart';

/// Mirrors the `/auth/reset-password` entry in lib/router/app_router.dart:
/// missing/empty token redirects to home.
GoRouter _router(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home'))),
      GoRoute(
        path: '/auth/reset-password',
        redirect: (_, state) {
          final token = state.uri.queryParameters['token'];
          return (token == null || token.isEmpty) ? '/' : null;
        },
        builder: (_, __) => const ResetPasswordScreen(),
      ),
    ],
  );
}

/// The form shows instantly (no preloading shimmer since 2026-10-10).
/// Extra pumps are harmless; kept for router redirect timing.
/// NEVER pumpAndSettle — other spinners on screen are infinite animations.
Future<void> _pumpScreen(WidgetTester tester, String initialLocation) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router(initialLocation)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 1100)); // shimmer done
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _fillAndSubmit(
    WidgetTester tester, String password, String confirm) async {
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), password);
  await tester.enterText(fields.at(1), confirm);
  await tester.tap(find.text('Change Password'));
  // Let the mocked worker future resolve and the state rebuild.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  tearDown(() {
    // Never leak a mock client into another test.
    PasswordResetService.setTestClient(null);
  });

  testWidgets('WITH token shows the new-password form', (tester) async {
    await _pumpScreen(tester, '/auth/reset-password?token=abc123');

    expect(find.byType(PreloadingWidget), findsNothing);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('WITHOUT token redirects to home', (tester) async {
    await _pumpScreen(tester, '/auth/reset-password');

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('New Password'), findsNothing);
    expect(find.byType(ResetPasswordScreen), findsNothing);
  });

  testWidgets('submit POSTs {token, newPassword} to /complete-password-reset',
      (tester) async {
    Uri? seenUrl;
    Map<String, dynamic>? seenBody;
    PasswordResetService.setTestClient(
      MockClient((request) async {
        seenUrl = request.url;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=tok123');
    await _fillAndSubmit(tester, 'newpass1', 'newpass1');

    expect(seenUrl.toString(),
        'https://loksewa-push-worker.loksewasolutionapi.workers.dev/complete-password-reset');
    expect(seenBody, {'token': 'tok123', 'newPassword': 'newpass1'});
    expect(find.text('Password reset successful'), findsOneWidget);
  });

  testWidgets('worker ok:true shows the success state', (tester) async {
    PasswordResetService.setTestClient(
      MockClient((_) async => http.Response('{"ok":true}', 200)),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=tok123');
    await _fillAndSubmit(tester, 'newpass1', 'newpass1');

    expect(find.text('Password reset successful'), findsOneWidget);
    expect(find.text('Back to Login'), findsOneWidget);
  });

  testWidgets('invalid_token shows the invalid/expired link state',
      (tester) async {
    PasswordResetService.setTestClient(
      MockClient(
          (_) async => http.Response('{"ok":false,"reason":"invalid_token"}', 200)),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=bogus');
    await _fillAndSubmit(tester, 'newpass1', 'newpass1');

    expect(find.text('This link is invalid or has expired.'), findsOneWidget);
    expect(find.textContaining('new reset link'), findsOneWidget);
    expect(find.text('Password reset successful'), findsNothing);
  });

  testWidgets('expired_token shows the invalid/expired link state',
      (tester) async {
    PasswordResetService.setTestClient(
      MockClient(
          (_) async => http.Response('{"ok":false,"reason":"expired_token"}', 200)),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=oldtok');
    await _fillAndSubmit(tester, 'newpass1', 'newpass1');

    expect(find.text('This link is invalid or has expired.'), findsOneWidget);
  });

  testWidgets('update_failed shows the generic error state', (tester) async {
    PasswordResetService.setTestClient(
      MockClient(
          (_) async => http.Response('{"ok":false,"reason":"update_failed"}', 200)),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=tok123');
    await _fillAndSubmit(tester, 'newpass1', 'newpass1');

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.text('This link is invalid or has expired.'), findsNothing);
  });

  testWidgets('transport failure shows the generic error state',
      (tester) async {
    PasswordResetService.setTestClient(
      MockClient((_) async => throw http.ClientException('offline')),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=tok123');
    await _fillAndSubmit(tester, 'newpass1', 'newpass1');

    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('weak_password stays on the form with an inline toast',
      (tester) async {
    PasswordResetService.setTestClient(
      MockClient(
          (_) async => http.Response('{"ok":false,"reason":"weak_password"}', 200)),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=tok123');
    await _fillAndSubmit(tester, 'newpass1', 'newpass1');

    // Inline validation via toast — still on the form, no state change.
    expect(find.text('This password is too weak. Please choose a stronger password.'),
        findsOneWidget);
    expect(find.text('Password reset successful'), findsNothing);
    expect(find.text('Something went wrong.'), findsNothing);
  });

  testWidgets('short password is rejected client-side (no worker call)',
      (tester) async {
    var calls = 0;
    PasswordResetService.setTestClient(
      MockClient((_) async {
        calls++;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=tok123');
    await _fillAndSubmit(tester, 'abc', 'abc');

    expect(calls, 0);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
  });

  testWidgets('mismatched passwords are rejected client-side (no worker call)',
      (tester) async {
    var calls = 0;
    PasswordResetService.setTestClient(
      MockClient((_) async {
        calls++;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await _pumpScreen(tester, '/auth/reset-password?token=tok123');
    await _fillAndSubmit(tester, 'newpass1', 'different');

    expect(calls, 0);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });
}
