import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/splash_screen.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/services/reset_link_service.dart';

/// Cold-start routing for the password-reset App Link, through the REAL
/// SplashScreen (which consumes ResetLinkService's stash in _decide).
///
/// The production bug: GoRouter(overridePlatformDefaultLocation: true)
/// forces every cold start to /splash, discarding the tapped link's token.
/// These tests pin the fix: a reset link lands on the reset form, while a
/// plain-domain link (or a reset path without a code) keeps the normal
/// splash flow.
GoRouter _testRouter() {
  return GoRouter(
    // Mirror production: the platform's initial route is ignored.
    initialLocation: '/splash',
    overridePlatformDefaultLocation: true,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home-stub'))),
      GoRoute(
          path: '/onboarding',
          builder: (_, __) => const Scaffold(body: Text('onboarding-stub'))),
      // No redirect here on purpose: we assert the splash navigated to the
      // exact location, token included.
      GoRoute(
        path: '/auth/reset-password',
        builder: (_, s) => Scaffold(
          body: Text('reset-stub:${s.uri.queryParameters['token']}'),
        ),
      ),
    ],
  );
}

/// Mocks shared_preferences (missing entirely in widget tests) and the
/// connectivity channel so the splash's background _decide never touches
/// real platform I/O.
void _mockPlatform(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  // Must be set on tester.binding INSIDE the testWidgets body.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (MethodCall call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    },
  );
}

void main() {
  setUp(() {
    ResetLinkService.resetForTest();
    // The splash guards on this global; each test gets a fresh cold start.
    splashHasRouted = false;
  });

  testWidgets('cold start with a reset link routes to the reset form',
      (tester) async {
    // Production path minus the platform channel: the plugin's URI is fed
    // through the same filter the real getInitialLink() result goes through.
    ResetLinkService.handleInitialUri(Uri.parse(
        'https://kbr.com.np/auth/reset-password?token=abc123'));
    _mockPlatform(tester);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter()));
    // Pump until the navigation settles: go() replaces the route, but the
    // outgoing splash page disposes a frame or two later in the test
    // binding (on a real device this is sub-frame).
    for (var i = 0;
        i < 10 && find.byType(SplashScreen).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('reset-stub:abc123'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('plain-domain link keeps the normal splash flow (no reset nav)',
      (tester) async {
    // The share-link case: no path → nothing is stashed.
    ResetLinkService.handleInitialUri(Uri.parse('https://kbr.com.np'));
    _mockPlatform(tester);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter()));
    await tester.pump(const Duration(milliseconds: 500));
    // Still on the branded splash (1200ms minimum); crucially it did NOT
    // jump to the reset form.
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.textContaining('reset-stub'), findsNothing);

    // Drain the rest of the splash flow (remote-config timeout, warm-up
    // deadline) in small increments — a single giant pump starves the
    // sequential async gaps in _decide. A plain link must continue to the
    // NORMAL destination.
    for (var i = 0;
        i < 30 && find.text('onboarding-stub').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('onboarding-stub'), findsOneWidget);
    expect(find.textContaining('reset-stub'), findsNothing);
  });

  testWidgets('reset path without token keeps the normal splash flow',
      (tester) async {
    // Not a reset link (no code) → nothing is stashed → normal flow.
    ResetLinkService.handleInitialUri(
        Uri.parse('https://kbr.com.np/auth/reset-password'));
    _mockPlatform(tester);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.textContaining('reset-stub'), findsNothing);

    for (var i = 0;
        i < 30 && find.text('onboarding-stub').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('onboarding-stub'), findsOneWidget);
    expect(find.textContaining('reset-stub'), findsNothing);
  });
}
