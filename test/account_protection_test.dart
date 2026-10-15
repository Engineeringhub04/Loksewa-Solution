// Tests for the account-protection service (NOTE 1 blacklist + NOTE 3
// platform backfill). Pure logic / fail-safe behavior only — the Firestore
// queries themselves are fail-open by contract and never throw.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/services/account_protection.dart';
import 'package:loksewa_solution/services/app_language.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await AppLanguage.setLanguage('en');
  });

  group('blacklistedMessage', () {
    test('returns the English message in English mode', () async {
      await AppLanguage.setLanguage('en');
      final msg = AccountProtection.blacklistedMessage();
      expect(msg, contains('removed'));
      expect(msg, contains('support'));
    });

    test('returns the Devanagari message in Nepali mode', () async {
      await AppLanguage.setLanguage('ne');
      final msg = AccountProtection.blacklistedMessage();
      expect(msg, contains('खाता'));
    });
  });

  group('isEmailBlacklisted', () {
    test('empty email is never blacklisted (no network call)', () async {
      expect(await AccountProtection.isEmailBlacklisted(''), isFalse);
      expect(await AccountProtection.isEmailBlacklisted('   '), isFalse);
    });

    test('never throws — fail-open on any query failure', () async {
      // In the test sandbox there is no Firestore access; the query fails
      // and the check must fail OPEN (false), never throw.
      final result =
          await AccountProtection.isEmailBlacklisted('nobody@example.com');
      expect(result, isFalse);
    });
  });

  group('backfillPlatformIfMissing', () {
    test('empty uid completes without throwing', () async {
      await AccountProtection.backfillPlatformIfMissing('');
    });

    test('never throws on network failure', () async {
      await AccountProtection.backfillPlatformIfMissing('some-uid');
    });
  });
}
