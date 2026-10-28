library;

import 'cf_api.dart';

/// In-app change-password flow (Security Settings → Change Password).
///
/// Phase-3: a single POST /auth/change-password on the loksewa-api — the
/// worker verifies the old password against the CF password hash (the one
/// login actually checks; the old screen only ever changed the mirrored
/// Firebase password), sets the new hash, and revokes the account's OTHER
/// sessions. This device stays signed in.
///
/// Never throws — transport/server failures map to the error outcome.
class ChangePasswordService {
  /// Changes the signed-in user's password. [PasswordChangeOutcome.ok]
  /// on success, [PasswordChangeOutcome.wrongPassword] when the worker
  /// rejects the old password (401 'wrong_password'), and
  /// [PasswordChangeOutcome.error] for anything else.
  static Future<PasswordChangeOutcome> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    try {
      await CfApi.changePassword(
          oldPassword: oldPassword, newPassword: newPassword);
      return PasswordChangeOutcome.ok;
    } on CfError catch (e) {
      if (e.error == 'wrong_password') {
        return PasswordChangeOutcome.wrongPassword;
      }
      return PasswordChangeOutcome.error;
    } catch (_) {
      return PasswordChangeOutcome.error;
    }
  }
}

/// Outcome of [ChangePasswordService.changePassword].
enum PasswordChangeOutcome { ok, wrongPassword, error }
