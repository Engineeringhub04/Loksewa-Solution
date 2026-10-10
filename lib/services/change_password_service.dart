library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// In-app change-password flow (Security Settings → Change Password).
///
/// The old password is verified by re-authenticating with Identity Toolkit
/// `accounts:signInWithPassword` — the returned fresh idToken is then used
/// for `accounts:update` with the new password. The stored session is never
/// touched: the re-auth is a throwaway check, not a sign-in.
///
/// Both calls never throw — transport/parse failures map to the error
/// outcomes below.
class ChangePasswordService {
  static const _identityUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts';
  static const _timeout = Duration(seconds: 10);

  /// Injectable HTTP client. Tests set it via [setTestClient]; production
  /// code always falls back to `http.Client()`.
  static http.Client? _testClient;

  /// Overrides the HTTP client (tests only).
  static void setTestClient(http.Client? client) => _testClient = client;

  /// Re-authenticates [email] with [oldPassword]. Returns the fresh idToken
  /// on success, [OldPasswordCheck.wrong] when the password is wrong, and
  /// [OldPasswordCheck.error] on transport errors or anything else.
  /// Never throws.
  static Future<OldPasswordCheck> verifyOldPassword(
    String email,
    String oldPassword,
  ) async {
    final client = _testClient ?? http.Client();
    try {
      final res = await client
          .post(
            Uri.parse(
                '$_identityUrl:signInWithPassword?key=${AppConfig.firebaseApiKey}'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': email,
              'password': oldPassword,
              'returnSecureToken': true,
            }),
          )
          .timeout(_timeout);
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        final idToken = data['idToken'] as String?;
        if (idToken != null && idToken.isNotEmpty) {
          return OldPasswordCheck.ok(idToken);
        }
        return OldPasswordCheck.error;
      }
      final raw =
          (data['error'] as Map?)?['message'] as String? ?? 'UNKNOWN_ERROR';
      // Wrong password (older APIs say INVALID_PASSWORD, newer ones
      // INVALID_LOGIN_CREDENTIALS). EMAIL_NOT_FOUND also means "these
      // credentials don't work" — surfaced as the same inline error.
      if (raw.contains('INVALID_PASSWORD') ||
          raw.contains('INVALID_LOGIN_CREDENTIALS') ||
          raw.contains('EMAIL_NOT_FOUND')) {
        return OldPasswordCheck.wrong;
      }
      return OldPasswordCheck.error;
    } catch (_) {
      return OldPasswordCheck.error;
    }
  }

  /// Sets the new password with the fresh [idToken] from [verifyOldPassword].
  /// Returns true on success. Never throws.
  static Future<bool> updatePassword(
    String idToken,
    String newPassword,
  ) async {
    final client = _testClient ?? http.Client();
    try {
      final res = await client
          .post(
            Uri.parse('$_identityUrl:update?key=${AppConfig.firebaseApiKey}'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'idToken': idToken,
              'password': newPassword,
              'returnSecureToken': false,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return false;
      final data = json.decode(res.body) as Map<String, dynamic>;
      // accounts:update echoes the localId on success.
      return (data['localId'] as String?)?.isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }
}

/// Outcome of [ChangePasswordService.verifyOldPassword].
class OldPasswordCheck {
  /// The password is correct; [idToken] is the fresh token to use for
  /// [ChangePasswordService.updatePassword].
  final bool success;

  /// Fresh idToken — non-null only when [success] is true.
  final String? idToken;

  /// True when the old password was rejected (wrong credentials).
  final bool wrongPassword;

  const OldPasswordCheck._(this.success, this.idToken, this.wrongPassword);

  /// The password is correct.
  const OldPasswordCheck.ok(String token) : this._(true, token, false);

  /// The password was rejected.
  static const wrong = OldPasswordCheck._(false, null, true);

  /// Transport error or anything else — show the generic error.
  static const error = OldPasswordCheck._(false, null, false);
}
