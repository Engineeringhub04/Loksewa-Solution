import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/password_reset_service.dart';
import 'package:loksewa_solution/services/reset_link_service.dart';

/// Pins the deliberate deep-link rule: ONLY the exact
/// /auth/reset-password path on kbr.com.np (or www) WITH a non-empty token
/// is intercepted. Plain-domain links (the share-link case) and everything
/// else keep today's behavior — boot to /splash, no forced navigation.
///
/// Plus the v1.0.87 routing matrix: tapped links are SILENTLY validated
/// first ([ResetLinkService.decideDisposition]), then routed per login
/// state — [handleColdToken]/[handleWarmToken] are exercised with injected
/// fakes so no widgets or network are needed.
void main() {
  setUp(ResetLinkService.resetForTest);

  group('isResetLink', () {
    test('accepts the exact reset path with an token', () {
      expect(
        ResetLinkService.isResetLink(Uri.parse(
            'https://kbr.com.np/auth/reset-password?token=abc123')),
        isTrue,
      );
    });

    test('accepts the www host', () {
      expect(
        ResetLinkService.isResetLink(Uri.parse(
            'https://www.kbr.com.np/auth/reset-password?token=abc123')),
        isTrue,
      );
    });

    test('accepts extra query params alongside the token', () {
      expect(
        ResetLinkService.isResetLink(Uri.parse(
            'https://kbr.com.np/auth/reset-password?mode=resetPassword&token=abc123&lang=en')),
        isTrue,
      );
    });

    test('rejects the plain domain (no path) — the share-link case', () {
      expect(
        ResetLinkService.isResetLink(Uri.parse('https://kbr.com.np')),
        isFalse,
      );
    });

    test('rejects the plain domain with a trailing slash', () {
      expect(
        ResetLinkService.isResetLink(Uri.parse('https://kbr.com.np/')),
        isFalse,
      );
    });

    test('rejects the reset path without an token (normal open)', () {
      expect(
        ResetLinkService.isResetLink(
            Uri.parse('https://kbr.com.np/auth/reset-password')),
        isFalse,
      );
    });

    test('rejects the reset path with an empty token', () {
      expect(
        ResetLinkService.isResetLink(Uri.parse(
            'https://kbr.com.np/auth/reset-password?token=')),
        isFalse,
      );
    });

    test('rejects other paths even with an token', () {
      expect(
        ResetLinkService.isResetLink(
            Uri.parse('https://kbr.com.np/other?token=abc123')),
        isFalse,
      );
    });

    test('rejects foreign hosts', () {
      expect(
        ResetLinkService.isResetLink(Uri.parse(
            'https://evil.com/auth/reset-password?token=abc123')),
        isFalse,
      );
    });

    test('rejects null', () {
      expect(ResetLinkService.isResetLink(null), isFalse);
    });
  });

  group('cold-start stash (handleInitialUri / consumePendingToken)', () {
    test('stashes a reset link and consumes the raw token once', () {
      ResetLinkService.handleInitialUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=abc123'));

      expect(ResetLinkService.consumePendingToken(), 'abc123');
      // Consume-once.
      expect(ResetLinkService.consumePendingToken(), isNull);
    });

    test('ignores a plain-domain link — consume returns null', () {
      ResetLinkService.handleInitialUri(Uri.parse('https://kbr.com.np'));

      expect(ResetLinkService.consumePendingToken(), isNull);
    });

    test('ignores a reset path without token — consume returns null', () {
      ResetLinkService.handleInitialUri(
          Uri.parse('https://kbr.com.np/auth/reset-password'));

      expect(ResetLinkService.consumePendingToken(), isNull);
    });

    test('a cold-start consume marks the token handled for the stream', () {
      final got = <String>[];
      ResetLinkService.onWarmResetLink = (location) async {
        got.add(location);
      };

      // Cold start: splash consumes the stash...
      ResetLinkService.handleInitialUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=cold1'));
      ResetLinkService.consumePendingToken();
      // ...then the platform re-emits the same link on the stream.
      ResetLinkService.handleIncomingUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=cold1'));

      expect(got, isEmpty);
    });
  });

  group('warm links (handleIncomingUri)', () {
    test('fires onWarmResetLink for a reset link', () async {
      String? got;
      ResetLinkService.onWarmResetLink = (location) async {
        got = location;
      };

      ResetLinkService.handleIncomingUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=warm1'));
      // The callback is async (it validates the token first) — let the
      // microtask run.
      await Future<void>.delayed(Duration.zero);

      expect(got, '/auth/reset-password?token=warm1');
    });

    test('ignores non-reset links', () async {
      var calls = 0;
      ResetLinkService.onWarmResetLink = (_) async {
        calls++;
      };

      ResetLinkService.handleIncomingUri(Uri.parse('https://kbr.com.np'));
      ResetLinkService.handleIncomingUri(
          Uri.parse('https://kbr.com.np/some/page'));
      await Future<void>.delayed(Duration.zero);

      expect(calls, 0);
    });

    test('dedupes a repeated identical link (cold-start race guard)', () async {
      final got = <String>[];
      ResetLinkService.onWarmResetLink = (location) async {
        got.add(location);
      };

      final uri = Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=dedupe1');
      ResetLinkService.handleIncomingUri(uri);
      ResetLinkService.handleIncomingUri(uri);
      await Future<void>.delayed(Duration.zero);

      expect(got, ['/auth/reset-password?token=dedupe1']);
    });

    test('a different code still navigates', () async {
      final got = <String>[];
      ResetLinkService.onWarmResetLink = (location) async {
        got.add(location);
      };

      ResetLinkService.handleIncomingUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=one'));
      ResetLinkService.handleIncomingUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=two'));
      await Future<void>.delayed(Duration.zero);

      expect(got, [
        '/auth/reset-password?token=one',
        '/auth/reset-password?token=two',
      ]);
    });
  });

  group('decideDisposition — the routing matrix', () {
    test('valid token → openReset regardless of login state', () {
      expect(
          ResetLinkService.decideDisposition(
              loggedIn: false, validation: TokenValidationResult.valid),
          ResetLinkDisposition.openReset);
      expect(
          ResetLinkService.decideDisposition(
              loggedIn: true, validation: TokenValidationResult.valid),
          ResetLinkDisposition.openReset);
    });

    test('invalid/expired + logged out → invalidLoggedOut', () {
      for (final v in [
        TokenValidationResult.invalid,
        TokenValidationResult.expired
      ]) {
        expect(
            ResetLinkService.decideDisposition(loggedIn: false, validation: v),
            ResetLinkDisposition.invalidLoggedOut,
            reason: '$v');
      }
    });

    test('invalid/expired + logged in → invalidLoggedIn', () {
      for (final v in [
        TokenValidationResult.invalid,
        TokenValidationResult.expired
      ]) {
        expect(
            ResetLinkService.decideDisposition(loggedIn: true, validation: v),
            ResetLinkDisposition.invalidLoggedIn,
            reason: '$v');
      }
    });

    test('network failure + logged out → networkLoggedOut', () {
      expect(
          ResetLinkService.decideDisposition(
              loggedIn: false,
              validation: TokenValidationResult.networkError),
          ResetLinkDisposition.networkLoggedOut);
    });

    test('network failure + logged in → networkLoggedIn', () {
      expect(
          ResetLinkService.decideDisposition(
              loggedIn: true, validation: TokenValidationResult.networkError),
          ResetLinkDisposition.networkLoggedIn);
    });
  });

  group('handleColdToken (injected effects)', () {
    Future<TokenValidationResult> Function(String) validateAs(
            TokenValidationResult v) =>
        (_) async => v;

    test('valid + logged out → go(reset location)', () async {
      final went = <String>[];
      var stashed = 0;
      var popups = 0;
      final d = await ResetLinkService.handleColdToken(
        'tok1',
        loggedIn: false,
        validate: validateAs(TokenValidationResult.valid),
        go: went.add,
        stashAutoOpen: (_) => stashed++,
        showInvalidPopup: () async => popups++,
      );
      expect(d, ResetLinkDisposition.openReset);
      expect(went, ['/auth/reset-password?token=tok1']);
      expect(stashed, 0);
      expect(popups, 0);
    });

    test('valid + logged in → stash for post-home auto-open (no popup)',
        () async {
      final went = <String>[];
      final stashed = <String>[];
      var popups = 0;
      final d = await ResetLinkService.handleColdToken(
        'tok2',
        loggedIn: true,
        validate: validateAs(TokenValidationResult.valid),
        go: went.add,
        stashAutoOpen: stashed.add,
        showInvalidPopup: () async => popups++,
      );
      expect(d, ResetLinkDisposition.openReset);
      expect(went, isEmpty);
      expect(stashed, ['/auth/reset-password?token=tok2']);
      expect(popups, 0);
    });

    test('invalid + logged out → popup then go(/login)', () async {
      final order = <String>[];
      final d = await ResetLinkService.handleColdToken(
        'tok3',
        loggedIn: false,
        validate: validateAs(TokenValidationResult.expired),
        go: (l) => order.add('go:$l'),
        stashAutoOpen: (_) {},
        showInvalidPopup: () async => order.add('popup'),
      );
      expect(d, ResetLinkDisposition.invalidLoggedOut);
      expect(order, ['popup', 'go:/login']);
    });

    test('invalid + logged in → popup, no navigation (splash routes home)',
        () async {
      final went = <String>[];
      var popups = 0;
      final d = await ResetLinkService.handleColdToken(
        'tok4',
        loggedIn: true,
        validate: validateAs(TokenValidationResult.invalid),
        go: went.add,
        stashAutoOpen: (_) {},
        showInvalidPopup: () async => popups++,
      );
      expect(d, ResetLinkDisposition.invalidLoggedIn);
      expect(went, isEmpty);
      expect(popups, 1);
    });

    test('network failure + logged out → go(reset location)', () async {
      final went = <String>[];
      final d = await ResetLinkService.handleColdToken(
        'tok5',
        loggedIn: false,
        validate: validateAs(TokenValidationResult.networkError),
        go: went.add,
        stashAutoOpen: (_) {},
        showInvalidPopup: () async {},
      );
      expect(d, ResetLinkDisposition.networkLoggedOut);
      expect(went, ['/auth/reset-password?token=tok5']);
    });

    test('network failure + logged in → nothing', () async {
      final went = <String>[];
      final stashed = <String>[];
      var popups = 0;
      final d = await ResetLinkService.handleColdToken(
        'tok6',
        loggedIn: true,
        validate: validateAs(TokenValidationResult.networkError),
        go: went.add,
        stashAutoOpen: stashed.add,
        showInvalidPopup: () async => popups++,
      );
      expect(d, ResetLinkDisposition.networkLoggedIn);
      expect(went, isEmpty);
      expect(stashed, isEmpty);
      expect(popups, 0);
    });
  });

  group('handleWarmToken (injected effects)', () {
    Future<TokenValidationResult> Function(String) validateAs(
            TokenValidationResult v) =>
        (_) async => v;

    test('valid → navigate to the reset form (either login state)', () async {
      for (final loggedIn in [false, true]) {
        final went = <String>[];
        var popups = 0;
        await ResetLinkService.handleWarmToken(
          'tok7',
          loggedIn: loggedIn,
          validate: validateAs(TokenValidationResult.valid),
          navigate: went.add,
          showInvalidPopup: () async => popups++,
        );
        expect(went, ['/auth/reset-password?token=tok7'],
            reason: 'loggedIn=$loggedIn');
        expect(popups, 0, reason: 'loggedIn=$loggedIn');
      }
    });

    test('invalid + logged out → /login + popup', () async {
      final order = <String>[];
      await ResetLinkService.handleWarmToken(
        'tok8',
        loggedIn: false,
        validate: validateAs(TokenValidationResult.invalid),
        navigate: (l) => order.add('nav:$l'),
        showInvalidPopup: () async => order.add('popup'),
      );
      expect(order, ['nav:/login', 'popup']);
    });

    test('invalid + logged in → popup in place, no navigation', () async {
      final went = <String>[];
      var popups = 0;
      await ResetLinkService.handleWarmToken(
        'tok9',
        loggedIn: true,
        validate: validateAs(TokenValidationResult.expired),
        navigate: went.add,
        showInvalidPopup: () async => popups++,
      );
      expect(went, isEmpty);
      expect(popups, 1);
    });

    test('network failure + logged out → still navigate to the form',
        () async {
      final went = <String>[];
      await ResetLinkService.handleWarmToken(
        'tok10',
        loggedIn: false,
        validate: validateAs(TokenValidationResult.networkError),
        navigate: went.add,
        showInvalidPopup: () async {},
      );
      expect(went, ['/auth/reset-password?token=tok10']);
    });

    test('network failure + logged in → stay, no popup', () async {
      final went = <String>[];
      var popups = 0;
      await ResetLinkService.handleWarmToken(
        'tok11',
        loggedIn: true,
        validate: validateAs(TokenValidationResult.networkError),
        navigate: went.add,
        showInvalidPopup: () async => popups++,
      );
      expect(went, isEmpty);
      expect(popups, 0);
    });
  });
}
