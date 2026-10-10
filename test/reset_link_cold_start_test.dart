import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/splash_screen.dart';
import 'package:loksewa_solution/services/password_reset_service.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/services/reset_link_service.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

/// Cold-start routing for the password-reset App Link, through the REAL
/// SplashScreen (which consumes ResetLinkService's stash in _decide).
///
/// v1.0.87: the tapped token is validated SILENTLY first
/// ([PasswordResetService.validateToken], mocked here), then the splash
/// routes per the reset-link matrix:
///   valid + logged out   → the reset form (existing path)
///   invalid/expired      → AppModalShell popup, then /login (logged out)
///   validation unreachable (network) + logged out → the reset form anyway
///     (the submit call surfaces the real error)
///
/// The production bug this pins: GoRouter(overridePlatformDefaultLocation:
/// true) forces every cold start to /splash, discarding the tapped link's
/// token.
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
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('login-stub'))),
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

  tearDown(() {
    // Never leak a mock client into another test.
    PasswordResetService.setTestClient(null);
  });

  testWidgets('cold start with a VALID reset link routes to the reset form',
      (tester) async {
    PasswordResetService.setTestClient(
      MockClient((_) async => http.Response('{"valid":true}', 200)),
    );
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
        i < 20 && find.byType(SplashScreen).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('reset-stub:abc123'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets(
      'cold start with an INVALID link: /login FIRST, popup only after it lands',
      (tester) async {
    // v1.0.88: the v1.0.87 bug showed the invalid-link popup OVER THE
    // SPLASH (before any navigation). Now the splash navigates to /login
    // first and the popup appears only after /login has landed.
    PasswordResetService.setTestClient(
      MockClient((_) async =>
          http.Response('{"valid":false,"reason":"expired_token"}', 200)),
    );
    ResetLinkService.handleInitialUri(Uri.parse(
        'https://kbr.com.np/auth/reset-password?token=deadbeef'));
    _mockPlatform(tester);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter()));

    // Poll frame by frame: record whether /login is already on screen at
    // the exact moment the popup first appears.
    var popupSeen = false;
    var loginAlreadyThere = false;
    for (var i = 0; i < 40 && !popupSeen; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      popupSeen = find
          .textContaining('already been used or has expired')
          .evaluate()
          .isNotEmpty;
      if (popupSeen) {
        loginAlreadyThere = find.text('login-stub').evaluate().isNotEmpty;
      }
    }

    expect(popupSeen, isTrue, reason: 'the invalid-link popup never appeared');
    expect(
      loginAlreadyThere,
      isTrue,
      reason: 'POPUP-ON-SPLASH BUG: the popup appeared before /login landed',
    );
    expect(find.byType(AppModalShell), findsOneWidget);
    // The reset form is NOT opened for a dead link.
    expect(find.textContaining('reset-stub'), findsNothing);

    // Dismiss the popup → still on /login, splash gone.
    await tester.tap(find.text('OK'));
    for (var i = 0;
        i < 20 && find.byType(AppModalShell).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(AppModalShell), findsNothing);
    expect(find.text('login-stub'), findsOneWidget);
    // Let go_router's page transition finish — the outgoing splash stays
    // mounted for a few frames in the test binding.
    for (var i = 0;
        i < 20 && find.byType(SplashScreen).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets(
      'cold start with UNREACHABLE validation still opens the reset form',
      (tester) async {
    // Transport failure → networkError → logged out still goes to the
    // form; the submit call surfaces the real error.
    PasswordResetService.setTestClient(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    ResetLinkService.handleInitialUri(Uri.parse(
        'https://kbr.com.np/auth/reset-password?token=abc123'));
    _mockPlatform(tester);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter()));
    for (var i = 0;
        i < 20 && find.byType(SplashScreen).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('reset-stub:abc123'), findsOneWidget);
    expect(find.byType(AppModalShell), findsNothing);
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
