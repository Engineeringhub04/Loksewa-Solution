import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/device_session_service.dart';

void main() {
  group('DeviceSessionService.formatLastActiveForTest', () {
    test('returns "recently" for null/unknown', () {
      expect(DeviceSessionService.formatLastActiveForTest(null), 'recently');
      expect(DeviceSessionService.formatLastActiveForTest('garbage'), 'recently');
      expect(DeviceSessionService.formatLastActiveForTest({}), 'recently');
    });

    test('returns "a few minutes ago" for recent timestamps', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(DeviceSessionService.formatLastActiveForTest(now - 5 * 60 * 1000),
          'a few minutes ago');
    });

    test('returns "about N minutes ago"', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(DeviceSessionService.formatLastActiveForTest(now - 30 * 60 * 1000),
          'about 30 minutes ago');
    });

    test('returns "about N hours ago"', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(DeviceSessionService.formatLastActiveForTest(now - 3 * 60 * 60 * 1000),
          'about 3 hours ago');
      expect(DeviceSessionService.formatLastActiveForTest(now - 60 * 60 * 1000),
          'about 1 hour ago');
    });

    test('returns "N days ago"', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(DeviceSessionService.formatLastActiveForTest(
          now - 2 * 24 * 60 * 60 * 1000), '2 days ago');
      expect(DeviceSessionService.formatLastActiveForTest(
          now - 24 * 60 * 60 * 1000), '1 day ago');
    });

    test('handles Firestore timestamp maps', () {
      final seconds =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 3600;
      expect(
          DeviceSessionService.formatLastActiveForTest({'seconds': seconds}),
          'about 1 hour ago');
    });
  });

  group('DeviceSessionService.evictionPushBodyForTest', () {
    test('greets by name', () {
      expect(DeviceSessionService.evictionPushBodyForTest('Ram'),
          'Hi Ram, you were signed in on another device. Open the app.');
    });

    test('falls back to "there" for blank names', () {
      expect(DeviceSessionService.evictionPushBodyForTest(''),
          'Hi there, you were signed in on another device. Open the app.');
      expect(DeviceSessionService.evictionPushBodyForTest('   '),
          'Hi there, you were signed in on another device. Open the app.');
    });
  });

  group('DeviceSessionService recheck channel', () {
    test('requestRecheck notifies listeners', () {
      var called = 0;
      void listener() => called++;
      DeviceSessionService.onRecheck(listener);
      DeviceSessionService.requestRecheck();
      expect(called, 1);
      DeviceSessionService.offRecheck(listener);
      DeviceSessionService.requestRecheck();
      expect(called, 1); // unsubscribed — not called again
    });

    test('a throwing listener does not stop others', () {
      var secondCalled = false;
      DeviceSessionService.onRecheck(() => throw StateError('boom'));
      DeviceSessionService.onRecheck(() => secondCalled = true);
      DeviceSessionService.requestRecheck();
      expect(secondCalled, isTrue);
    });
  });

  group('SessionCheck / LoginSessionCheck models', () {
    test('const constructors carry verdicts', () {
      const ok = SessionCheck(SessionVerdict.ok, null);
      expect(ok.verdict, SessionVerdict.ok);
      const evicted = SessionCheck(SessionVerdict.evicted, 'Pixel 7');
      expect(evicted.deviceName, 'Pixel 7');
      const loginOk = LoginSessionCheck.ok();
      expect(loginOk.outcome, LoginSessionOutcome.ok);
    });
  });

  group('differentiated push messages', () {
    test('evictionPushBody addresses the displaced device', () {
      expect(
        DeviceSessionService.evictionPushBody('Ram'),
        'Hi Ram, your account was just signed in on another device.',
      );
    });

    test('takeOverConfirmBody confirms the new device', () {
      expect(
        DeviceSessionService.takeOverConfirmBody('Ram'),
        'Hi Ram, this device is now your active login. '
        'Your other device has been signed out.',
      );
    });

    test('messages differ between old and new phone', () {
      expect(
        DeviceSessionService.evictionPushBody('Ram'),
        isNot(DeviceSessionService.takeOverConfirmBody('Ram')),
      );
    });
  });
}
