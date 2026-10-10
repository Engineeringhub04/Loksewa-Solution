import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/services/password_reset_service.dart';

void main() {
  const workerBase = 'https://loksewa-push-worker.loksewasolutionapi.workers.dev';

  tearDown(() {
    // Never leak a mock client into another test.
    PasswordResetService.setTestClient(null);
  });

  test('POSTs {email} to /request-password-reset as JSON', () async {
    Uri? seenUrl;
    Map<String, String>? seenHeaders;
    Map<String, dynamic>? seenBody;
    PasswordResetService.setTestClient(
      MockClient((request) async {
        seenUrl = request.url;
        seenHeaders = request.headers;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }),
    );

    final result =
        await PasswordResetService.requestReset('user@example.com');

    expect(result, PasswordResetResult.sent);
    expect(seenUrl.toString(), '$workerBase/request-password-reset');
    expect(seenHeaders!['Content-Type'], 'application/json');
    expect(seenBody, {'email': 'user@example.com'});
  });

  test('maps ok:false reasons to the matching result', () async {
    final cases = {
      'rate_limited': PasswordResetResult.rateLimited,
      'no_provider': PasswordResetResult.noProvider,
      'invalid_email': PasswordResetResult.invalidEmail,
      'something_else': PasswordResetResult.failed,
    };
    for (final entry in cases.entries) {
      PasswordResetService.setTestClient(
        MockClient((_) async =>
            http.Response('{"ok":false,"reason":"${entry.key}"}', 200)),
      );
      expect(
        await PasswordResetService.requestReset('user@example.com'),
        entry.value,
        reason: 'reason=${entry.key}',
      );
    }
  });

  test('maps transport failures and bad JSON to failed (never throws)',
      () async {
    PasswordResetService.setTestClient(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(await PasswordResetService.requestReset('user@example.com'),
        PasswordResetResult.failed);

    PasswordResetService.setTestClient(
      MockClient((_) async => http.Response('not json', 200)),
    );
    expect(await PasswordResetService.requestReset('user@example.com'),
        PasswordResetResult.failed);
  });

  group('completeReset', () {
    test('POSTs {token, newPassword} to /complete-password-reset as JSON',
        () async {
      Uri? seenUrl;
      Map<String, String>? seenHeaders;
      Map<String, dynamic>? seenBody;
      PasswordResetService.setTestClient(
        MockClient((request) async {
          seenUrl = request.url;
          seenHeaders = request.headers;
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }),
      );

      final result = await PasswordResetService.completeReset(
          'tok123', 'newpass1');

      expect(result, PasswordResetCompleteResult.success);
      expect(seenUrl.toString(), '$workerBase/complete-password-reset');
      expect(seenHeaders!['Content-Type'], 'application/json');
      expect(seenBody, {'token': 'tok123', 'newPassword': 'newpass1'});
    });

    test('maps ok:false reasons to the matching result', () async {
      final cases = {
        'invalid_token': PasswordResetCompleteResult.invalidToken,
        'expired_token': PasswordResetCompleteResult.expiredToken,
        'weak_password': PasswordResetCompleteResult.weakPassword,
        // Server-side failures collapse to the generic failed bucket.
        'update_failed': PasswordResetCompleteResult.failed,
        'internal_error': PasswordResetCompleteResult.failed,
        'invalid_request': PasswordResetCompleteResult.failed,
        'something_else': PasswordResetCompleteResult.failed,
      };
      for (final entry in cases.entries) {
        PasswordResetService.setTestClient(
          MockClient((_) async =>
              http.Response('{"ok":false,"reason":"${entry.key}"}', 200)),
        );
        expect(
          await PasswordResetService.completeReset('tok123', 'newpass1'),
          entry.value,
          reason: 'reason=${entry.key}',
        );
      }
    });

    test('maps transport failures and bad JSON to failed (never throws)',
        () async {
      PasswordResetService.setTestClient(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await PasswordResetService.completeReset('tok123', 'newpass1'),
          PasswordResetCompleteResult.failed);

      PasswordResetService.setTestClient(
        MockClient((_) async => http.Response('not json', 200)),
      );
      expect(await PasswordResetService.completeReset('tok123', 'newpass1'),
          PasswordResetCompleteResult.failed);
    });
  });
}
