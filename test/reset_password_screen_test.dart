import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/auth/reset_password_screen.dart';
import 'package:loksewa_solution/widgets/preloading.dart';

/// Mirrors the `/auth/reset-password` entry in lib/router/app_router.dart:
/// missing/empty oobCode redirects to home.
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
          final oobCode = state.uri.queryParameters['oobCode'];
          return (oobCode == null || oobCode.isEmpty) ? '/' : null;
        },
        builder: (_, __) => const ResetPasswordScreen(),
      ),
    ],
  );
}

/// The shimmer shows first (~1s), then the form reveals.
/// NEVER pumpAndSettle — the preloading spinner is an infinite animation.
Future<void> _pumpScreen(WidgetTester tester, String initialLocation) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router(initialLocation)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 1100)); // shimmer done
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('WITH oobCode shows the new-password form', (tester) async {
    await _pumpScreen(tester, '/auth/reset-password?oobCode=abc123');

    expect(find.byType(PreloadingWidget), findsNothing);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('WITHOUT oobCode redirects to home', (tester) async {
    await _pumpScreen(tester, '/auth/reset-password');

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('New Password'), findsNothing);
    expect(find.byType(ResetPasswordScreen), findsNothing);
  });
}
