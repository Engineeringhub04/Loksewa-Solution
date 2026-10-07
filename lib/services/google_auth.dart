import 'package:google_sign_in/google_sign_in.dart';

import 'app_config.dart';

/// google_sign_in v7 bootstrap (Credential Manager on Android).
///
/// v7 replaced the instantiable `GoogleSignIn(...)` with the
/// `GoogleSignIn.instance` singleton. [initialize] must be called exactly
/// once — and its future allowed to complete — before any other method
/// ([authenticate], [signOut]) is used. This helper makes that safe to call
/// from any screen: the first call initializes, later calls are no-ops.
///
/// v7 behavior changes vs v6:
/// - `authenticate()` THROWS [GoogleSignInException] with
///   `code == GoogleSignInExceptionCode.canceled` when the user dismisses the
///   picker (v6 returned null).
/// - `account.authentication` is now a SYNC getter (tokens arrive with the
///   authenticate() result); no `await` needed.
/// - On Android the account picker is the system Credential Manager
///   bottom sheet ("Choose an account") — drawn by the OS, not the app.
class GoogleAuth {
  static bool _initialized = false;
  static Future<void>? _initFuture;

  /// Ensures `GoogleSignIn.instance.initialize(...)` has completed.
  /// Safe to call repeatedly; concurrent callers share one future.
  static Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    _initFuture ??= GoogleSignIn.instance.initialize(
      serverClientId: AppConfig.googleWebClientId,
    );
    return _initFuture!.then((_) => _initialized = true);
  }

  /// True when the user dismissed the Google account picker / consent.
  static bool isUserCancelled(Object e) =>
      e is GoogleSignInException &&
      e.code == GoogleSignInExceptionCode.canceled;
}
