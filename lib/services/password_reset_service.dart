library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Worker-backed password-reset flow.
///
/// POSTs the user's email to the loksewa-push-worker
/// (`/request-password-reset`). The worker rate-limits requests (one per
/// day per email), reads its SMTP provider key from Firestore, and sends
/// the reset link `https://kbr.com.np/auth/reset-password?token=...`
/// (the token is a one-time 64-hex string minted by the worker, NOT a
/// Firebase oobCode).
///
/// The worker ALWAYS answers HTTP 200 with `{ok: bool, reason?: string}`:
/// - `{ok: true}` — the reset email was queued/sent.
/// - `{ok: false, reason: "rate_limited"}` — one link already requested
///   today; the previously sent link stays valid for 1 hour.
/// - `{ok: false, reason: "no_provider"}` — the email provider is not
///   configured on the worker yet.
/// - `{ok: false, reason: "invalid_email"}` — the email failed validation.
/// - `{ok: false, reason: "account_not_found"}` — no account uses this email.
///
/// Unlike [AdminNotifyService] the request call is NOT fire-and-forget:
/// the forgot-password screen needs the result to decide what to show, so
/// it awaits it and maps transport failures to [PasswordResetResult.failed].
/// The same applies to [completeReset], which the reset form awaits.
class PasswordResetService {
  /// Base URL of the push worker. Defined ONCE here (see also
  /// AdminNotifyService._workerBase — same worker, different endpoint).
  static const _workerBase =
      'https://loksewa-push-worker.loksewasolutionapi.workers.dev';

  static const _timeout = Duration(seconds: 8);

  /// Injectable HTTP client. Tests set it via [setTestClient]; production
  /// code always falls back to `http.Client()`.
  static http.Client? _testClient;

  /// Overrides the HTTP client (tests only).
  static void setTestClient(http.Client? client) => _testClient = client;

  /// Requests a password-reset email for [email].
  /// Never throws — transport/parse failures map to [PasswordResetResult.failed].
  static Future<PasswordResetResult> requestReset(String email) async {
    final client = _testClient ?? http.Client();
    try {
      final res = await client
          .post(
            Uri.parse('$_workerBase/request-password-reset'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(_timeout);
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) return PasswordResetResult.sent;
      return switch (data['reason']) {
        'rate_limited' => PasswordResetResult.rateLimited,
        'no_provider' => PasswordResetResult.noProvider,
        'invalid_email' => PasswordResetResult.invalidEmail,
        'account_not_found' => PasswordResetResult.accountNotFound,
        _ => PasswordResetResult.failed,
      };
    } catch (_) {
      return PasswordResetResult.failed;
    }
  }

  /// Completes a password reset with the one-time [token] from the reset
  /// link. POSTs to the worker (`/complete-password-reset`); the worker
  /// validates the token server-side and updates the password via the
  /// Firebase Admin SDK — the app never touches Identity Toolkit directly.
  ///
  /// Never throws — transport/parse failures map to
  /// [PasswordResetCompleteResult.failed].
  static Future<PasswordResetCompleteResult> completeReset(
      String token, String newPassword) async {
    final client = _testClient ?? http.Client();
    try {
      final res = await client
          .post(
            Uri.parse('$_workerBase/complete-password-reset'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'token': token, 'newPassword': newPassword}),
          )
          .timeout(_timeout);
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) return PasswordResetCompleteResult.success;
      return switch (data['reason']) {
        'invalid_token' => PasswordResetCompleteResult.invalidToken,
        'expired_token' => PasswordResetCompleteResult.expiredToken,
        'weak_password' => PasswordResetCompleteResult.weakPassword,
        _ => PasswordResetCompleteResult.failed,
      };
    } catch (_) {
      return PasswordResetCompleteResult.failed;
    }
  }

  /// Validates a one-time reset-link [token] WITHOUT consuming it.
  /// POSTs to the worker (`/validate-reset-token`); the worker answers
  /// `{valid: true}` or `{valid: false, reason: "invalid_token" |
  /// "expired_token"}`. Used by the deep-link routing matrix so a tapped
  /// link is checked SILENTLY before the app decides where to go.
  ///
  /// Never throws — transport/parse failures map to
  /// [TokenValidationResult.networkError].
  static Future<TokenValidationResult> validateToken(String token) async {
    final client = _testClient ?? http.Client();
    try {
      final res = await client
          .post(
            Uri.parse('$_workerBase/validate-reset-token'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'token': token}),
          )
          .timeout(_timeout);
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['valid'] == true) return TokenValidationResult.valid;
      return switch (data['reason']) {
        'invalid_token' => TokenValidationResult.invalid,
        'expired_token' => TokenValidationResult.expired,
        // Unknown reason on a valid:false answer — fail closed: treat the
        // link as unusable rather than opening the reset form.
        _ => TokenValidationResult.invalid,
      };
    } catch (_) {
      return TokenValidationResult.networkError;
    }
  }
}

/// Outcome of [PasswordResetService.requestReset].
enum PasswordResetResult {
  /// The reset email was queued/sent — show the "check your email" UI.
  sent,

  /// One link was already requested today — show the in-page
  /// already-requested banner (NOT a popup).
  rateLimited,

  /// The worker has no email provider configured — show the in-page
  /// service-unavailable banner.
  noProvider,

  /// The email failed the worker's validation.
  invalidEmail,

  /// The worker has no account for this email — show the in-page
  /// "no account found" banner (NOT a popup).
  accountNotFound,

  /// Transport error, non-JSON answer, or unknown reason.
  failed,
}

/// Outcome of [PasswordResetService.validateToken].
enum TokenValidationResult {
  /// The token is live — open the reset form.
  valid,

  /// The token is unknown or was already used — show the
  /// invalid/expired-link popup.
  invalid,

  /// The token expired — show the invalid/expired-link popup.
  expired,

  /// The worker could not be reached (or answered garbage) — the routing
  /// matrix decides per login state (logged out: still open the form, the
  /// submit surfaces the error; logged in: stay, no auto-open).
  networkError,
}

/// Outcome of [PasswordResetService.completeReset].
enum PasswordResetCompleteResult {
  /// The password was updated — show the success state.
  success,

  /// The token is unknown — show the invalid/expired link state.
  invalidToken,

  /// The token expired — show the invalid/expired link state.
  expiredToken,

  /// The new password is too weak — show inline validation.
  weakPassword,

  /// Transport error, non-JSON answer, or unknown reason
  /// (`update_failed`, `internal_error`, `invalid_request`, ...) —
  /// show the generic error state.
  failed,
}
