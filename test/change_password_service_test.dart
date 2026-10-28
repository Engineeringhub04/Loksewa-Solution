import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/change_password_service.dart';

/// Phase-3: ChangePasswordService is a thin outcome mapper over
/// CfApi.changePassword (POST /auth/change-password). The HTTP layer is
/// mocked at the CfApi client seam.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    // Never leak a mock client into another test.
    CfApi.setTestClient(null);
  });

  test('POSTs old+new password to /auth/change-password and maps 200 to ok',
      () async {
    Uri? seenUrl;
    Map<String, dynamic>? seenBody;
    CfApi.setTestClient(
      MockClient((request) async {
        seenUrl = request.url;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }),
    );

    final outcome =
        await ChangePasswordService.changePassword('oldpass1', 'newpass2');

    expect(outcome, PasswordChangeOutcome.ok);
    expect(seenUrl!.path, '/auth/change-password');
    expect(seenBody, {'oldPassword': 'oldpass1', 'newPassword': 'newpass2'});
  });

  test('401 wrong_password maps to PasswordChangeOutcome.wrongPassword',
      () async {
    CfApi.setTestClient(
      MockClient((_) async =>
          http.Response('{"ok":false,"error":"wrong_password"}', 401)),
    );
    final outcome =
        await ChangePasswordService.changePassword('nope', 'newpass2');
    expect(outcome, PasswordChangeOutcome.wrongPassword);
  });

  test('other server errors map to error (never throws)', () async {
    for (final (status, err) in [
      (400, 'weak_password'),
      (400, 'no_password_set'),
      (500, 'internal_error'),
    ]) {
      CfApi.setTestClient(
        MockClient((_) async =>
            http.Response(jsonEncode({'ok': false, 'error': err}), status)),
      );
      final outcome =
          await ChangePasswordService.changePassword('oldpass1', 'newpass2');
      expect(outcome, PasswordChangeOutcome.error, reason: err);
    }
  });

  test('transport failures map to error (never throws)', () async {
    CfApi.setTestClient(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    final outcome =
        await ChangePasswordService.changePassword('oldpass1', 'newpass2');
    expect(outcome, PasswordChangeOutcome.error);
  });
}
