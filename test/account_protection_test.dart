// Tests for the account-protection service (NOTE 1 blacklist message +
// NOTE 3 platform backfill).
//
// Phase-3: the client-side blacklist CHECKS are retired — the loksewa-api
// refuses blacklisted emails server-side during signup/login and the auth
// screens map 'auth/blacklisted' to blacklistedMessage(). What remains
// client-side: the message itself and the PATCH /me platform backfill.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/services/account_protection.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/cf_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    CfApi.setTestClient(null);
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

  group('backfillPlatformIfMissing', () {
    test('empty uid completes without throwing (no network call)', () async {
      var called = false;
      CfApi.setTestClient(MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }));
      await AccountProtection.backfillPlatformIfMissing('');
      expect(called, isFalse);
    });

    test('never throws on network failure', () async {
      CfApi.setTestClient(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      await AccountProtection.backfillPlatformIfMissing('some-uid');
    });

    test('PATCHes platform App when the profile has none', () async {
      final seen = <String>[];
      Map<String, dynamic>? patchBody;
      CfApi.setTestClient(MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.url.path == '/me' && request.method == 'GET') {
          return http.Response(
              jsonEncode({
                'ok': true,
                'user': {'uid': 'u1', 'email': 'a@b.c'},
              }),
              200);
        }
        if (request.url.path == '/me' && request.method == 'PATCH') {
          patchBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('{}', 404);
      }));
      await AccountProtection.backfillPlatformIfMissing('u1');
      expect(seen, ['GET /me', 'PATCH /me']);
      expect(patchBody, {'platform': 'App'});
    });

    test('does not PATCH when a platform is already set', () async {
      var patchCalls = 0;
      CfApi.setTestClient(MockClient((request) async {
        if (request.method == 'PATCH') patchCalls++;
        return http.Response(
            jsonEncode({
              'ok': true,
              'user': {'uid': 'u1', 'platform': 'Website'},
            }),
            200);
      }));
      await AccountProtection.backfillPlatformIfMissing('u1');
      expect(patchCalls, 0);
    });
  });
}
