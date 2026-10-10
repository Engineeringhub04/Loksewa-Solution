import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/reset_link_service.dart';

/// Pins the deliberate deep-link rule: ONLY the exact
/// /auth/reset-password path on kbr.com.np (or www) WITH a non-empty token
/// is intercepted. Plain-domain links (the share-link case) and everything
/// else keep today's behavior — boot to /splash, no forced navigation.
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

  group('cold-start stash (handleInitialUri / consumePendingResetLocation)',
      () {
    test('stashes a reset link and consumes it as an encoded location', () {
      ResetLinkService.handleInitialUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=abc123'));

      expect(ResetLinkService.consumePendingResetLocation(),
          '/auth/reset-password?token=abc123');
    });

    test('ignores a plain-domain link — consume returns null', () {
      ResetLinkService.handleInitialUri(Uri.parse('https://kbr.com.np'));

      expect(ResetLinkService.consumePendingResetLocation(), isNull);
    });

    test('ignores a reset path without token — consume returns null', () {
      ResetLinkService.handleInitialUri(
          Uri.parse('https://kbr.com.np/auth/reset-password'));

      expect(ResetLinkService.consumePendingResetLocation(), isNull);
    });

    test('consume is once-only', () {
      ResetLinkService.handleInitialUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=abc123'));

      expect(ResetLinkService.consumePendingResetLocation(), isNotNull);
      expect(ResetLinkService.consumePendingResetLocation(), isNull);
    });

    test('the token is URI-encoded in the location', () {
      // Dart decodes '+' as space in queryParameters — the stash holds the
      // decoded code, and locationFor re-encodes it.
      ResetLinkService.handleInitialUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=a+b/c%3Dd'));

      final location = ResetLinkService.consumePendingResetLocation();
      expect(location, isNotNull);
      // Round-trips back to the decoded code.
      expect(
        Uri.parse('https://x.test$location').queryParameters['token'],
        'a b/c=d',
      );
    });
  });

  group('warm links (handleIncomingUri)', () {
    test('fires onWarmResetLink for a reset link', () {
      String? got;
      ResetLinkService.onWarmResetLink = (location) => got = location;

      ResetLinkService.handleIncomingUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=warm1'));

      expect(got, '/auth/reset-password?token=warm1');
    });

    test('ignores non-reset links', () {
      var calls = 0;
      ResetLinkService.onWarmResetLink = (_) => calls++;

      ResetLinkService.handleIncomingUri(Uri.parse('https://kbr.com.np'));
      ResetLinkService.handleIncomingUri(
          Uri.parse('https://kbr.com.np/some/page'));

      expect(calls, 0);
    });

    test('dedupes a repeated identical link (cold-start race guard)', () {
      final got = <String>[];
      ResetLinkService.onWarmResetLink = got.add;

      final uri = Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=dedupe1');
      ResetLinkService.handleIncomingUri(uri);
      ResetLinkService.handleIncomingUri(uri);

      expect(got, ['/auth/reset-password?token=dedupe1']);
    });

    test('a cold-start consume marks the code handled for the stream', () {
      final got = <String>[];
      ResetLinkService.onWarmResetLink = got.add;

      // Cold start: splash consumes the stash...
      ResetLinkService.handleInitialUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=cold1'));
      ResetLinkService.consumePendingResetLocation();
      // ...then the platform re-emits the same link on the stream.
      ResetLinkService.handleIncomingUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=cold1'));

      expect(got, isEmpty);
    });

    test('a different code still navigates', () {
      final got = <String>[];
      ResetLinkService.onWarmResetLink = got.add;

      ResetLinkService.handleIncomingUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=one'));
      ResetLinkService.handleIncomingUri(Uri.parse(
          'https://kbr.com.np/auth/reset-password?token=two'));

      expect(got, [
        '/auth/reset-password?token=one',
        '/auth/reset-password?token=two',
      ]);
    });
  });
}
