import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'device_session_service.dart';
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

  /// v1.0.110: logout hooks — services with user-specific in-memory or
  /// disk caches register a wipe function here (avoids circular imports:
  /// AuthService cannot import the services that import it). All hooks run
  /// on every logout so the next login starts 100% fresh.
  static final List<Future<void> Function()> _logoutHooks = [];

  /// Registers a cleanup to run on logout. Idempotent per function.
  static void addLogoutHook(Future<void> Function() hook) {
    if (!_logoutHooks.contains(hook)) _logoutHooks.add(hook);
  }

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
  ///
  /// v1.0.110: when the Google email already has a password account
  /// (account-exists-with-different-credential), the Google account is
  /// AUTO-LINKED via the worker (the Google ID token proves email
  /// ownership) instead of blocking. No new account is created, the
  /// password is untouched, and both login methods keep working.
  static Future<({AppUser user, bool isNewUser})> signInWithGoogleIdToken(
    String idToken, {
    required bool allowCreate,
    String? googlePhotoUrl,
  }) async {
    try {
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
      // EMAIL_EXISTS instead of issuing a second account.
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
      await _maybeSyncGooglePhoto(_session!.user.uid, googlePhotoUrl);
      // Move FCM token to the user collection (best effort).
      PushNotificationService.onSignIn().catchError((_) {});
      return (user: _session!.user, isNewUser: isNewUser);
    } on AuthError catch (e) {
      if (e.code == 'auth/account-exists-with-different-credential') {
        // Auto-link: hand the Google ID token to the worker, which verifies
        // email ownership and returns a custom token for the EXISTING user.
        return _linkGoogleToExisting(idToken, googlePhotoUrl);
      }
      rethrow;
    }
  }

  /// v1.0.110: links a Google credential to an existing password account.
  /// The worker verifies the Google ID token (proving the caller owns the
  /// email), finds the existing user by email, and mints a custom token.
  /// The app signs in with it — same account, password untouched.
  static const _workerBase =
      'https://loksewa-push-worker.loksewasolutionapi.workers.dev';

  static Future<({AppUser user, bool isNewUser})> _linkGoogleToExisting(
    String googleIdToken,
    String? googlePhotoUrl,
  ) async {
    final res = await http.post(
      Uri.parse('$_workerBase/auth/link-google'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'googleIdToken': googleIdToken}),
    );
    final data = json.decode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || data['ok'] != true) {
      // Worker refused (bad token, blacklisted, etc.) — surface the
      // original conflict so the UI can explain.
      throw AuthError('auth/account-exists-with-different-credential');
    }
    final customToken = data['customToken'] as String?;
    if (customToken == null || customToken.isEmpty) {
      throw AuthError('auth/account-exists-with-different-credential');
    }
    final signInRes = await _identityRequest('signInWithCustomToken', {
      'token': customToken,
      'returnSecureToken': true,
    });
    await _storeSession(signInRes);
    await _maybeSyncGooglePhoto(_session!.user.uid, googlePhotoUrl);
    PushNotificationService.onSignIn().catchError((_) {});
    return (user: _session!.user, isNewUser: data['isNewUser'] == true);
  }

  /// v1.0.110: profile photo rules for Google sign-in.
  /// - Manual (user-uploaded) photo → NEVER overwritten by Google's image.
  /// - No photo or Google-sourced photo → save Google's image.
  /// First-time Google signup therefore keeps Google's photo; a later
  /// manual upload flips the source to 'manual' and sticks.
  static Future<void> _maybeSyncGooglePhoto(
      String uid, String? googlePhotoUrl) async {
    if (googlePhotoUrl == null || googlePhotoUrl.isEmpty) return;
    try {
      final token = await getValidIdToken();
      if (token.isEmpty) return;
      final doc = await FirestoreRest.getDocument('users/$uid', idToken: token);
      final source = doc?['photoURLSource']?.toString() ?? 'none';
      if (source == 'manual') return; // user-uploaded — hands off.
      final current = doc?['photoURL']?.toString() ?? '';
      if (current == googlePhotoUrl) return;
      await FirestoreRest.setDocument(
        'users/$uid',
        {
          'photoURL': googlePhotoUrl,
          'photoURLSource': 'google',
        },
        idToken: token,
        merge: true,
      );
    } catch (_) {}
  }

  static Future<void> logout() async {
    final uid = _session?.user.uid;
    // Capture the ID token BEFORE clearing the session — onSignOut needs it
    // for the Firestore token move (after _session = null the token is gone).
    final idToken = await getValidIdToken().catchError((_) => '');
    _session = null;
    await PrefsService.remove(PrefsService.sessionKey);
    // v1.0.110: wipe ALL user-specific caches (ProfileStore, pending
    // payments, etc.) so the next login fetches 100% fresh data — no
    // stale state from the previous account.
    for (final hook in List.of(_logoutHooks)) {
      try {
        await hook();
      } catch (_) {}
    }
    if (uid != null) {
      // Release the one-device claim (best effort) — only when it still
      // names THIS device, so a displaced phone never wipes the new holder.
      await DeviceSessionService.releaseDeviceSession(uid).catchError((_) {});
      // Move FCM token from user collection to anonymous (best effort).
      await PushNotificationService.onSignOut(uid, idToken: idToken).catchError((_) {});
    }
    DeviceSessionService.resetCaches();
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
