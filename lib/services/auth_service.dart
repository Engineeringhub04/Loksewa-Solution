import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'firestore_rest.dart';
import 'prefs_service.dart';
import 'push_notification_service.dart';

/// Firebase Identity Toolkit REST wrapper — mirrors src/core/firebase/auth.ts.
/// Session is persisted in SharedPreferences (like the Expo app's session.ts).
class AppUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoURL;

  const AppUser({required this.uid, this.email, this.displayName, this.photoURL});

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoURL': photoURL,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        uid: json['uid'] as String,
        email: json['email'] as String?,
        displayName: json['displayName'] as String?,
        photoURL: json['photoURL'] as String?,
      );
}

class _Session {
  final AppUser user;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  _Session({
    required this.user,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'idToken': idToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory _Session.fromJson(Map<String, dynamic> json) => _Session(
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        idToken: json['idToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}

class AuthError implements Exception {
  final String code;
  AuthError(this.code);
  @override
  String toString() => code;
}

/// Identity Toolkit message -> auth/* code map (mirrors auth.ts ERROR_CODE_MAP).
String _mapErrorCode(String raw) {
  // Config-level failures (e.g. a mis-baked API key) get their own code so
  // the UI can tell the user to update instead of retrying blindly.
  if (raw.contains('API key')) return 'auth/invalid-api-key';
  const map = {
    'EMAIL_EXISTS': 'auth/email-already-in-use',
    'EMAIL_NOT_FOUND': 'auth/invalid-credential',
    'INVALID_PASSWORD': 'auth/invalid-credential',
    'INVALID_LOGIN_CREDENTIALS': 'auth/invalid-credential',
    'FEDERATED_USER_ID_ALREADY_LINKED': 'auth/account-exists-with-different-credential',
    'USER_DISABLED': 'auth/user-disabled',
    'WEAK_PASSWORD': 'auth/weak-password',
    'TOO_MANY_ATTEMPTS_TRY_LATER': 'auth/too-many-requests',
    'INVALID_EMAIL': 'auth/invalid-email',
    'INVALID_OOB_CODE': 'auth/invalid-action-code',
    'EXPIRED_OOB_CODE': 'auth/invalid-action-code',
    'MISSING_OOB_CODE': 'auth/invalid-action-code',
    'INVALID_CODE': 'auth/invalid-action-code',
  };
  return map[raw] ?? 'auth/unknown-error';
}

class AuthService {
  static const _identityUrl = 'https://identitytoolkit.googleapis.com/v1/accounts';
  static const _secureTokenUrl = 'https://securetoken.googleapis.com/v1/token';

  static _Session? _session;

  static Future<Map<String, dynamic>> _identityRequest(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final res = await http.post(
      Uri.parse('$_identityUrl:$endpoint?key=${AppConfig.firebaseApiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    final data = json.decode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final raw = (data['error'] as Map?)?['message'] as String? ?? 'UNKNOWN_ERROR';
      throw AuthError(_mapErrorCode(raw));
    }
    return data;
  }

  static AppUser _toAppUser(Map<String, dynamic> res) => AppUser(
        uid: res['localId'] as String,
        email: res['email'] as String?,
        displayName: res['displayName'] as String?,
        photoURL: res['photoUrl'] as String?,
      );

  static Future<void> _storeSession(Map<String, dynamic> res, [AppUser? override]) async {
    final user = override ?? _toAppUser(res);
    final expiresIn = int.tryParse('${res['expiresIn'] ?? '3600'}') ?? 3600;
    _session = _Session(
      user: user,
      idToken: res['idToken'] as String,
      refreshToken: res['refreshToken'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
    await PrefsService.setString(PrefsService.sessionKey, json.encode(_session!.toJson()));
  }

  /// Reads the saved session from disk WITHOUT any network refresh and
  /// installs it in memory. Used by the splash on cold start: a saved
  /// session means the user was logged in. This NEVER wipes — a link tap
  /// or any other cold start can therefore never log the user out.
  /// Installing it in memory matters — [getValidIdToken] then retries the
  /// refresh itself on its next call instead of sending API requests with an
  /// empty token. Returns null when nothing was saved or the saved blob is
  /// corrupt (without deleting anything).
  static Future<AppUser?> peekSavedSession() async {
    try {
      final raw = await PrefsService.getString(PrefsService.sessionKey);
      if (raw == null) return null;
      _session = _Session.fromJson(json.decode(raw) as Map<String, dynamic>);
      return _session!.user;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _refreshToken() async {
    final refreshToken = _session?.refreshToken;
    if (refreshToken == null) throw AuthError('auth/no-session');
    final res = await http.post(
      Uri.parse('$_secureTokenUrl?key=${AppConfig.firebaseApiKey}'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=refresh_token&refresh_token=${Uri.encodeComponent(refreshToken)}',
    );
    // HTTP 400 (e.g. invalid_grant) means the refresh token is truly dead —
    // the session must be wiped. Any other non-200 is treated as transient:
    // the caller keeps the existing session and retries later.
    if (res.statusCode == 400) throw AuthError('auth/session-expired');
    if (res.statusCode != 200) throw AuthError('auth/session-transient');
    final data = json.decode(res.body) as Map<String, dynamic>;
    final expiresIn = int.tryParse('${data['expires_in'] ?? '3600'}') ?? 3600;
    _session = _Session(
      user: _session!.user,
      idToken: data['id_token'] as String,
      refreshToken: data['refresh_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
    await PrefsService.setString(PrefsService.sessionKey, json.encode(_session!.toJson()));
  }

  /// A valid (refreshed if needed) ID token for Firestore REST calls.
  static Future<String> getValidIdToken() async {
    if (_session == null) return '';
    if (_session!.isExpired) {
      await _refreshToken();
    }
    return _session!.idToken;
  }

  static AppUser? get currentUser => _session?.user;

  static Future<AppUser> signInWithEmail(String email, String password) async {
    final res = await _identityRequest('signInWithPassword', {
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });
    await _storeSession(res);
    // Move FCM token to the user collection (best effort).
    PushNotificationService.onSignIn().catchError((_) {});
    return _session!.user;
  }

  static Future<AppUser> signUpWithEmail(String email, String password) async {
    final res = await _identityRequest('signUp', {
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });
    await _storeSession(res);
    // Move FCM token to the user collection (best effort).
    PushNotificationService.onSignIn().catchError((_) {});
    return _session!.user;
  }

  /// Google Sign-In via Identity Toolkit signInWithIdp — mirrors
  /// signInWithGoogleIdTokenResult in auth.ts. Returns the user plus whether
  /// the account was just created. Login passes allowCreate: false (lookup
  /// only); signup passes allowCreate: true.
  static Future<({AppUser user, bool isNewUser})> signInWithGoogleIdToken(
    String idToken, {
    required bool allowCreate,
  }) async {
    final res = await _identityRequest('signInWithIdp', {
      // Keep the OAuth token URL-safe in the REST postBody.
      'postBody':
          'id_token=${Uri.encodeComponent(idToken)}&providerId=google.com',
      'requestUri': 'http://localhost',
      'returnSecureToken': true,
      // Ask Firebase to return the provider-conflict marker instead of
      // silently linking or creating.
      'returnIdpCredential': true,
      'autoCreate': allowCreate,
    });
    // With one-account-per-email enabled, Firebase can return HTTP 200 with
    // EMAIL_EXISTS instead of issuing a second account — never authenticate
    // an email/password account through a Google credential silently.
    if (res['needConfirmation'] == true ||
        res['errorMessage'] == 'EMAIL_EXISTS' ||
        res['errorMessage'] == 'FEDERATED_USER_ID_ALREADY_LINKED') {
      throw AuthError('auth/account-exists-with-different-credential');
    }
    final isNewUser = res['isNewUser'] == true;
    if (!allowCreate && isNewUser) {
      // Defensive guard in case the backend ignores autoCreate. Never persist
      // a session for an unexpected new account on the login screen.
      throw AuthError('auth/google-account-creation-blocked');
    }
    await _storeSession(res);
    // Move FCM token to the user collection (best effort).
    PushNotificationService.onSignIn().catchError((_) {});
    return (user: _session!.user, isNewUser: isNewUser);
  }

  static Future<void> sendPasswordReset(String email) async {
    await _identityRequest('sendOobCode', {
      'requestType': 'PASSWORD_RESET',
      'email': email,
    });
  }

  /// Validates a Firebase action-link oobCode — mirrors
  /// verifyPasswordResetCode in auth.ts.
  static Future<({String? email, String? requestType})>
      verifyPasswordResetCode(String oobCode) async {
    final res = await _identityRequest('resetPassword', {'oobCode': oobCode});
    return (
      email: res['email'] as String?,
      requestType: res['requestType'] as String?,
    );
  }

  /// Completes a password reset — mirrors confirmPasswordReset in auth.ts.
  static Future<void> confirmPasswordReset(
      String oobCode, String newPassword) async {
    await _identityRequest(
        'resetPassword', {'oobCode': oobCode, 'newPassword': newPassword});
  }

  static Future<void> logout() async {
    final uid = _session?.user.uid;
    // Capture the ID token BEFORE clearing the session — onSignOut needs it
    // for the Firestore token move (after _session = null the token is gone).
    final idToken = await getValidIdToken().catchError((_) => '');
    _session = null;
    await PrefsService.remove(PrefsService.sessionKey);
    if (uid != null) {
      // Release the one-device claim (best effort).
      await FirestoreRest.deleteDocument('users/$uid/session/active').catchError((_) {});
      // Move FCM token from user collection to anonymous (best effort).
      await PushNotificationService.onSignOut(uid, idToken: idToken).catchError((_) {});
    }
  }

  /// Permanently deletes the Firebase Auth identity (Identity Toolkit
  /// `accounts:delete`), then clears the local session.
  /// Mirrors `deleteCurrentAccount` in `src/core/firebase/auth.ts`.
  ///
  /// Callers must delete the user's Firestore profile document FIRST —
  /// once the auth identity is gone the request is no longer authorised
  /// to touch the document.
  static Future<void> deleteCurrentAccount() async {
    final idToken = await getValidIdToken();
    if (idToken.isEmpty) return;
    final uid = _session?.user.uid;
    if (uid != null) {
      // Drop this device's session claim while we still have auth.
      await FirestoreRest.deleteDocument('users/$uid/session/active')
          .catchError((_) {});
    }
    await _identityRequest('delete', {'idToken': idToken});
    _session = null;
    await PrefsService.remove(PrefsService.sessionKey);
  }

  /// Sentinel distinguishing "leave this field unchanged" from "clear it".
  /// Identity Toolkit treats an explicit null as a clear, so plain nullable
  /// params cannot express both.
  static const keepField = Object();

  /// Updates the Firebase Auth user profile (Identity Toolkit `accounts:update`)
  /// and patches the cached session user so Home/Profile headers update
  /// immediately without a re-login. Mirrors `updateCurrentUserProfile` in
  /// src/core/firebase/auth.ts. Failures are the caller's to swallow.
  static Future<void> updateCurrentUserProfile({
    Object? displayName = keepField,
    Object? photoURL = keepField,
  }) async {
    final idToken = await getValidIdToken();
    if (idToken.isEmpty) return;
    await _identityRequest('update', {
      'idToken': idToken,
      if (displayName != keepField) 'displayName': displayName,
      if (photoURL != keepField) 'photoUrl': photoURL,
      'returnSecureToken': false,
    });
    final session = _session;
    if (session != null) {
      final user = session.user;
      _session = _Session(
        user: AppUser(
          uid: user.uid,
          email: user.email,
          displayName: displayName == keepField
              ? user.displayName
              : displayName as String?,
          photoURL:
              photoURL == keepField ? user.photoURL : photoURL as String?,
        ),
        idToken: session.idToken,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt,
      );
      await PrefsService.setString(
          PrefsService.sessionKey, json.encode(_session!.toJson()));
    }
  }
}
