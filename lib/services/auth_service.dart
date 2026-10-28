import 'cf_api.dart';
import 'device_session_service.dart';
import 'prefs_service.dart';
import 'push_notification_service.dart';

/// Auth service — Phase-7: Cloudflare-only.
///
/// The ONLY session is the Cloudflare (loksewa-api) session held by
/// [CfApi]: sign-in / sign-up / Google / claim / reset all run against the
/// worker, and [currentUser] / [peekSavedSession] read that session. The
/// Firebase Identity Toolkit mirror that earlier phases kept for unmoved
/// screens is RETIRED — every consumer has migrated, so there is no
/// Firebase token, no mirror sign-in, and no legacy session blob anymore.
/// (Firebase remains in the app solely as the FCM delivery pipe:
/// firebase_core + firebase_messaging for push.)
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

class AuthError implements Exception {
  final String code;
  AuthError(this.code);
  @override
  String toString() => code;
}

class AuthService {
  /// The Cloudflare session's user (the only identity). Null when signed
  /// out.
  static AppUser? _cfUser;

  static void _installCfUser(CfUser user) {
    _cfUser = AppUser(
      uid: user.uid,
      email: user.email,
      displayName: user.name,
      photoURL: user.photoURL,
    );
  }

  /// Maps a worker error string to the AuthError codes the UI already
  /// speaks. needs_claim / blacklisted get their own codes so the login +
  /// signup screens can route/message them distinctly.
  static AuthError _mapCfError(CfError e) {
    switch (e.error) {
      case 'blacklisted':
        return AuthError('auth/blacklisted');
      case 'email_in_use':
        return AuthError('auth/email-already-in-use');
      case 'use_google_or_claim':
        return AuthError('auth/account-exists-with-different-credential');
      case 'needs_claim':
        return AuthError('auth/needs-claim');
      case 'account_not_found':
      case 'wrong_password':
        return AuthError('auth/invalid-credential');
      case 'account_disabled':
        return AuthError('auth/user-disabled');
      case 'invalid_email':
        return AuthError('auth/invalid-email');
      case 'weak_password':
        return AuthError('auth/weak-password');
      case 'too_many_requests':
      case 'rate_limited':
        return AuthError('auth/too-many-requests');
      case 'wrong_code':
        return AuthError('auth/invalid-action-code');
      default:
        return AuthError('auth/unknown-error');
    }
  }

  /// v1.0.110: logout hooks — services with user-specific in-memory or
  /// disk caches register a wipe function here (avoids circular imports:
  /// AuthService cannot import the services that import it). All hooks run
  /// on every logout so the next login starts 100% fresh.
  static final List<Future<void> Function()> _logoutHooks = [];

  /// Registers a cleanup to run on logout. Idempotent per function.
  static void addLogoutHook(Future<void> Function() hook) {
    if (!_logoutHooks.contains(hook)) _logoutHooks.add(hook);
  }

  /// Reads the saved session from disk WITHOUT any network refresh and
  /// installs it in memory. Used by the splash on cold start: a saved
  /// session means the user was logged in. This NEVER wipes — a link tap
  /// or any other cold start can therefore never log the user out.
  /// Returns null when nothing was saved or the saved blob is corrupt
  /// (without deleting anything).
  static Future<AppUser?> peekSavedSession() async {
    // Phase-7: the Cloudflare session is the ONLY identity. A pre-Phase-7
    // install holding only the retired legacy blob is simply signed out —
    // the user signs in again against Cloudflare (claim flow for migrated
    // accounts whose password was never set).
    final cfUser = await CfApi.loadSavedUser();
    if (cfUser != null) {
      _installCfUser(cfUser);
      return _cfUser;
    }
    return null;
  }

  static AppUser? get currentUser => _cfUser;

  static Future<AppUser> signInWithEmail(String email, String password) async {
    final CfAuthResult result;
    try {
      result = await CfApi.login(email: email, password: password);
    } on CfError catch (e) {
      throw _mapCfError(e);
    }
    _installCfUser(result.user);
    // Move FCM token to the user collection (best effort).
    PushNotificationService.onSignIn().catchError((_) {});
    return _cfUser!;
  }

  static Future<AppUser> signUpWithEmail(String email, String password,
      {String? name}) async {
    final CfAuthResult result;
    try {
      result =
          await CfApi.signup(name: name ?? '', email: email, password: password);
    } on CfError catch (e) {
      throw _mapCfError(e);
    }
    _installCfUser(result.user);
    // Move FCM token to the user collection (best effort).
    PushNotificationService.onSignIn().catchError((_) {});
    return _cfUser!;
  }

  // ------------------------------------------------------------ claim flow
  /// NOTE-11 claim, step 1: email a 6-digit code to [email]. The worker
  /// answers ok whether or not the account exists. [CfError] /
  /// [CfNetworkError] propagate for the claim screen to surface.
  static Future<void> requestClaimCode(String email) =>
      CfApi.claimRequest(email);

  /// NOTE-11 claim, step 2: verify the code, set the account's first
  /// password, and log in (CF session stored by [CfApi.claimVerify]).
  static Future<AppUser> claimWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final result = await CfApi.claimVerify(
        email: email, code: code, newPassword: newPassword);
    _installCfUser(result.user);
    PushNotificationService.onSignIn().catchError((_) {});
    return _cfUser!;
  }

  /// Forgot-password (code flow), steps 1 + 2. No session is created —
  /// the user logs in with the new password afterwards.
  static Future<void> requestResetCode(String email) =>
      CfApi.resetRequest(email);

  static Future<void> resetWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      CfApi.resetVerify(email: email, code: code, newPassword: newPassword);

  /// Google Sign-In: the worker verifies the Google ID token and resolves
  /// it to the account (existing uid for migrated users; a Google sign-in
  /// onto an existing password account is auto-linked server-side — the
  /// password is untouched and both login methods keep working). Returns
  /// the user plus whether the account was just created. Login passes
  /// allowCreate: false (lookup only); signup passes allowCreate: true.
  ///
  /// The claim trigger is unchanged: an account whose CF password was
  /// never set (passwordHash null) routes through the claim flow from the
  /// email-login path; the Google path itself needs no claim because the
  /// Google token already proves email ownership.
  static Future<({AppUser user, bool isNewUser})> signInWithGoogleIdToken(
    String idToken, {
    required bool allowCreate,
    String? googlePhotoUrl,
  }) async {
    final CfAuthResult result;
    try {
      result = await CfApi.google(idToken, allowCreate: allowCreate, store: false);
    } on CfError catch (e) {
      throw _mapCfError(e);
    }
    if (!allowCreate && result.isNewUser) {
      // Login screen forbids account creation. The CF account may already
      // exist server-side at this point (the worker creates on first
      // sight), but NO session is persisted — same contract as before.
      throw AuthError('auth/google-account-creation-blocked');
    }
    await CfApi.storeAuthResult(result);
    _installCfUser(result.user);
    // Profile photo sync (manual-wins rule lives in _maybeSyncGooglePhoto).
    await _maybeSyncGooglePhoto(_cfUser!.uid, googlePhotoUrl);
    // Move FCM token to the user collection (best effort).
    PushNotificationService.onSignIn().catchError((_) {});
    return (user: _cfUser!, isNewUser: result.isNewUser);
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
      // Phase-3: the profile lives behind GET /me now; the manual-wins
      // rule is unchanged (a user-uploaded photo is never overwritten).
      final doc = await CfApi.getMe();
      final source = doc?['photoURLSource']?.toString() ?? 'none';
      if (source == 'manual') return; // user-uploaded — hands off.
      final current = doc?['photoURL']?.toString() ?? '';
      if (current == googlePhotoUrl) return;
      await CfApi.patchMe({
        'photoURL': googlePhotoUrl,
        'photoURLSource': 'google',
      });
    } catch (_) {}
  }

  static Future<void> logout() async {
    final uid = currentUser?.uid;
    _cfUser = null;
    if (uid != null) {
      // Phase-5: move the FCM token registration from this user to the
      // anonymous device registration FIRST, while the CF session is
      // still alive — the DELETE /push-tokens needs its Bearer (after
      // the session is cleared the registration could no longer be
      // removed), so the re-register lands as a guest.
      await PushNotificationService.onSignOut(uid).catchError((_) {});
    }
    // Phase-3: revoke the CF refresh token server-side BEFORE the local
    // CF session is cleared (best-effort — a failed revoke never blocks
    // the sign-out; the token simply expires on its own schedule).
    await CfApi.logoutSession().catchError((_) {});
    await CfApi.clearSession().catchError((_) {});
    // Drop any stale pre-Phase-7 legacy session blob: the mirror is
    // retired and nothing may ever read it again.
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
    }
    DeviceSessionService.resetCaches();
  }

  /// Permanently deletes the account: DELETE /auth/account on the worker
  /// (full self-delete, no tombstone), then clears the local session.
  /// Signup rollback uses this same path.
  static Future<void> deleteCurrentAccount() async {
    // Delete while the CF Bearer session is still alive.
    await CfApi.deleteAccount().catchError((_) {});
    _cfUser = null;
    await CfApi.clearSession().catchError((_) {});
    // Drop any stale pre-Phase-7 legacy session blob (see logout).
    await PrefsService.remove(PrefsService.sessionKey);
  }

  /// Sentinel distinguishing "leave this field unchanged" from "clear it".
  /// Plain nullable params cannot express both.
  static const keepField = Object();

  /// Patches the cached session user so Home/Profile headers update
  /// immediately without a re-login. Failures are the caller's to swallow.
  ///
  /// Phase-3: Cloudflare is the identity; the durable write is the Edit
  /// Profile PATCH /me (updateUserProfile) and this method only keeps the
  /// local session + the stored CF user in step.
  static Future<void> updateCurrentUserProfile({
    Object? displayName = keepField,
    Object? photoURL = keepField,
  }) async {
    // Keep the primary (CF) identity in step so headers read the new
    // name/photo without a re-login.
    final cf = _cfUser;
    if (cf != null) {
      _cfUser = AppUser(
        uid: cf.uid,
        email: cf.email,
        displayName:
            displayName == keepField ? cf.displayName : displayName as String?,
        photoURL: photoURL == keepField ? cf.photoURL : photoURL as String?,
      );
      await CfApi.patchStoredUser({
        if (displayName != keepField) 'name': displayName,
        if (photoURL != keepField) 'photoURL': photoURL,
      }).catchError((_) {});
    }
  }
}
