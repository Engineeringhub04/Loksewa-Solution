// Tests for the account-protection service (NOTE 1 blacklist + NOTE 3
// platform backfill). Pure logic / fail-safe behavior only — the Firestore
// queries themselves are fail-open by contract and never throw.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  group('isEmailBlacklistedViaWorker', () {
    const workerBase =
        'https://loksewa-push-worker.loksewasolutionapi.workers.dev';
    tearDown(() => AccountProtection.setTestClient(null));

    test('posts the email to /check-blacklist and honors blocked:true',
        () async {
      Uri? seenUrl;
      Map<String, String>? seenHeaders;
      Map<String, dynamic>? seenBody;
      AccountProtection.setTestClient(
        MockClient((request) async {
          seenUrl = request.url;
          seenHeaders = request.headers;
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"blocked":true}', 200);
        }),
      );
      expect(
          await AccountProtection.isEmailBlacklistedViaWorker('bad@x.com'),
          isTrue);
      expect(seenUrl.toString(), '$workerBase/check-blacklist');
      expect(seenHeaders!['Content-Type'], 'application/json');
      expect(seenBody, {'email': 'bad@x.com'});
    });

    test('blocked:false → false', () async {
      AccountProtection.setTestClient(
        MockClient((_) async => http.Response('{"blocked":false}', 200)),
      );
      expect(
          await AccountProtection.isEmailBlacklistedViaWorker('ok@x.com'),
          isFalse);
    });

    test('non-200 fails open (false), never throws', () async {
      AccountProtection.setTestClient(
        MockClient((_) async => http.Response('boom', 500)),
      );
      expect(
          await AccountProtection.isEmailBlacklistedViaWorker('a@b.c'),
          isFalse);
    });

    test('bad JSON fails open (false)', () async {
      AccountProtection.setTestClient(
        MockClient((_) async => http.Response('not-json{{{', 200)),
      );
      expect(
          await AccountProtection.isEmailBlacklistedViaWorker('a@b.c'),
          isFalse);
    });

    test('transport error fails open (false), never throws', () async {
      AccountProtection.setTestClient(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(
          await AccountProtection.isEmailBlacklistedViaWorker('a@b.c'),
          isFalse);
    });

    test('empty email never hits the network', () async {
      var called = false;
      AccountProtection.setTestClient(
        MockClient((_) async {
          called = true;
          return http.Response('{"blocked":true}', 200);
        }),
      );
      expect(await AccountProtection.isEmailBlacklistedViaWorker('  '), isFalse);
      expect(called, isFalse);
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
