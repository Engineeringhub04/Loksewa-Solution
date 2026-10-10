import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/services/change_password_service.dart';

void main() {
  const apiBase = 'https://identitytoolkit.googleapis.com/v1/accounts';

  tearDown(() {
    // Never leak a mock client into another test.
    ChangePasswordService.setTestClient(null);
  });

  group('verifyOldPassword', () {
    test('POSTs signInWithPassword and returns the fresh idToken on success',
        () async {
      Uri? seenUrl;
      Map<String, dynamic>? seenBody;
      ChangePasswordService.setTestClient(
        MockClient((request) async {
          seenUrl = request.url;
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
              '{"idToken":"fresh-id-token","localId":"u1"}', 200);
        }),
      );

      final check = await ChangePasswordService.verifyOldPassword(
          'user@example.com', 'oldpass1');

      expect(check.success, isTrue);
      expect(check.wrongPassword, isFalse);
      expect(check.idToken, 'fresh-id-token');
      expect(seenUrl.toString(), '$apiBase:signInWithPassword?key=');
      expect(seenBody!['email'], 'user@example.com');
      expect(seenBody!['password'], 'oldpass1');
      expect(seenBody!['returnSecureToken'], isTrue);
    });

    test('wrong password maps to OldPasswordCheck.wrong', () async {
      for (final raw in [
        'INVALID_LOGIN_CREDENTIALS',
        'INVALID_PASSWORD',
        'EMAIL_NOT_FOUND',
      ]) {
        ChangePasswordService.setTestClient(
          MockClient((_) async => http.Response(
              '{"error":{"message":"$raw"}}', 400)),
        );
        final check = await ChangePasswordService.verifyOldPassword(
            'user@example.com', 'nope');
        expect(check.success, isFalse, reason: raw);
        expect(check.wrongPassword, isTrue, reason: raw);
        expect(check.idToken, isNull, reason: raw);
      }
    });

    test('other API errors map to OldPasswordCheck.error (never throws)',
        () async {
      for (final raw in ['USER_DISABLED', 'TOO_MANY_ATTEMPTS_TRY_LATER']) {
        ChangePasswordService.setTestClient(
          MockClient((_) async => http.Response(
              '{"error":{"message":"$raw"}}', 400)),
        );
        final check = await ChangePasswordService.verifyOldPassword(
            'user@example.com', 'oldpass1');
        expect(check.success, isFalse, reason: raw);
        expect(check.wrongPassword, isFalse, reason: raw);
      }
    });

    test('transport failures and bad JSON map to error (never throws)',
        () async {
      ChangePasswordService.setTestClient(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      final t = await ChangePasswordService.verifyOldPassword(
          'user@example.com', 'oldpass1');
      expect(t.success, isFalse);
      expect(t.wrongPassword, isFalse);

      ChangePasswordService.setTestClient(
        MockClient((_) async => http.Response('not json', 200)),
      );
      final j = await ChangePasswordService.verifyOldPassword(
          'user@example.com', 'oldpass1');
      expect(j.success, isFalse);
      expect(j.wrongPassword, isFalse);
    });
  });

  group('updatePassword', () {
    test('POSTs accounts:update with the fresh idToken', () async {
      Uri? seenUrl;
      Map<String, dynamic>? seenBody;
      ChangePasswordService.setTestClient(
        MockClient((request) async {
          seenUrl = request.url;
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"localId":"u1"}', 200);
        }),
      );

      final ok = await ChangePasswordService.updatePassword(
          'fresh-id-token', 'newpass1');

      expect(ok, isTrue);
      expect(seenUrl.toString(), '$apiBase:update?key=');
      expect(seenBody!['idToken'], 'fresh-id-token');
      expect(seenBody!['password'], 'newpass1');
    });

    test('non-200 and transport failures return false (never throws)',
        () async {
      ChangePasswordService.setTestClient(
        MockClient((_) async =>
            http.Response('{"error":{"message":"INVALID_ID_TOKEN"}}', 400)),
      );
      expect(
          await ChangePasswordService.updatePassword('bad', 'newpass1'),
          isFalse);

      ChangePasswordService.setTestClient(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(
          await ChangePasswordService.updatePassword('tok', 'newpass1'),
          isFalse);
    });
  });
}
