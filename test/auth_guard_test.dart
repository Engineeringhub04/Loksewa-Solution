import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/router/app_router.dart';
import 'package:loksewa_solution/services/reset_link_service.dart';

/// Global auth guard: without an account, NO protected page (home
/// included) may open — every such navigation bounces to /onboarding.
/// Public pages (login, reset-password, info pages…) stay reachable.
void main() {
  group('authGuardRedirect (pure decision)', () {
    test('logged out + / -> /onboarding', () {
      expect(authGuardRedirect(loggedIn: false, path: '/'), '/onboarding');
    });

    test('logged out + protected pages -> /onboarding', () {
      for (final p in [
        '/profile',
        '/subjects',
        '/exam-results',
        '/settings/security',
        '/admin',
        '/admin/subscriptions',
        '/checkout',
        '/bookmarks',
        '/delete-account',
        '/some-unknown-path',
      ]) {
        expect(authGuardRedirect(loggedIn: false, path: p), '/onboarding',
            reason: p);
      }
    });

    test('logged out + public pages -> no redirect', () {
      for (final p in [
        '/splash',
        '/onboarding',
        '/login',
        '/signup',
        '/forgot-password',
        '/auth/reset-password',
        '/blocking/maintenance',
        '/blocking/no-internet',
        '/about',
        '/contact-us',
        '/privacy-policy',
        '/terms-conditions',
        '/terms-of-service',
        '/help-center',
        '/help',
        '/app-info',
        '/feedback',
        '/under-construction',
      ]) {
        expect(authGuardRedirect(loggedIn: false, path: p), isNull, reason: p);
      }
    });

    test('logged in -> never redirects (role checks stay separate)', () {
      for (final p in ['/', '/profile', '/admin', '/login']) {
        expect(authGuardRedirect(loggedIn: true, path: p), isNull, reason: p);
      }
    });
  });

  group('deep-link whitelist', () {
    test('only /auth/reset-password is registered', () {
      expect(ResetLinkService.kHandledDeepLinkPaths, {'/auth/reset-password'});
    });

    test('unknown kbr.com.np link is discarded (cold)', () {
      ResetLinkService.resetForTest();
      ResetLinkService.handleInitialUri(
          Uri.parse('https://kbr.com.np/contact'));
      expect(ResetLinkService.consumePendingToken(), isNull);
      ResetLinkService.resetForTest();
    });

    test('unknown kbr.com.np link is discarded (warm)', () {
      ResetLinkService.resetForTest();
      var called = false;
      ResetLinkService.onWarmResetLink = (_) async {
        called = true;
      };
      ResetLinkService.handleIncomingUri(
          Uri.parse('https://www.kbr.com.np/pricing'));
      expect(called, isFalse);
      ResetLinkService.resetForTest();
    });
  });

  group('router wiring (fresh router, logged out)', () {
    GoRouter testRouter() => GoRouter(
          initialLocation: '/splash',
          redirect: (context, state) => authGuardRedirect(
            loggedIn: false,
            path: state.uri.path,
          ),
          routes: [
            GoRoute(
                path: '/splash',
                builder: (_, __) => const Text('SPLASH_MARKER')),
            GoRoute(path: '/', builder: (_, __) => const Text('HOME_MARKER')),
            GoRoute(
                path: '/onboarding',
                builder: (_, __) => const Text('ONBOARDING_MARKER')),
            GoRoute(
                path: '/auth/reset-password',
                builder: (_, __) => const Text('RESET_MARKER')),
            GoRoute(
                path: '/login', builder: (_, __) => const Text('LOGIN_MARKER')),
          ],
        );

    testWidgets('logged out go("/") lands on /onboarding', (tester) async {
      final router = testRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('SPLASH_MARKER'), findsOneWidget);

      router.go('/');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('ONBOARDING_MARKER'), findsOneWidget);
      expect(find.text('HOME_MARKER'), findsNothing);
    });

    testWidgets('logged out can still open reset link with token',
        (tester) async {
      final router = testRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.go('/auth/reset-password?token=abc123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('RESET_MARKER'), findsOneWidget);
      expect(find.text('ONBOARDING_MARKER'), findsNothing);
    });
  });
}
