import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/prefs_service.dart';

/// peekSavedSession: the splash's cold-start session read. A saved CF
/// session on disk means the user is logged in — this read NEVER wipes, so
/// a link tap (or any cold start) can never log the user out. No network
/// is touched; the CfApi layer refreshes the access token lazily on its
/// next authenticated call.
///
/// Phase-7: the Cloudflare session is the ONLY session. The retired
/// pre-Phase-7 legacy blob (PrefsService.sessionKey) no longer counts as
/// a login on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Map<String, dynamic> sessionJson() => {
        'user': {
          'uid': 'u1',
          'email': 'a@b.c',
          'name': 'Test',
          'photoURL': null,
        },
        'accessToken': 'tok',
        'refreshToken': 'ref',
      };

  test('returns the saved user without touching the network', () async {
    // PrefsService caches its instance, so seed via its own write path.
    await PrefsService.setString(
        CfApi.sessionPrefsKey, json.encode(sessionJson()));
    final user = await AuthService.peekSavedSession();
    expect(user?.uid, 'u1');
    expect(user?.displayName, 'Test');
    // Installed in memory so the app is signed in from the first frame.
    expect(AuthService.currentUser?.uid, 'u1');
  });

  test('returns null when nothing was saved', () async {
    await PrefsService.remove(CfApi.sessionPrefsKey);
    expect(await AuthService.peekSavedSession(), isNull);
  });

  test('a legacy-only blob no longer counts as a session', () async {
    await PrefsService.remove(CfApi.sessionPrefsKey);
    await PrefsService.setString(
        PrefsService.sessionKey,
        json.encode({
          'user': {
            'uid': 'legacy-u',
            'email': 'a@b.c',
            'displayName': 'Legacy',
            'photoURL': null,
          },
          'idToken': 'tok',
          'refreshToken': 'ref',
          'expiresAt':
              DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        }));
    expect(await AuthService.peekSavedSession(), isNull);
  });

  test('returns null on a corrupt blob and never throws', () async {
    await PrefsService.setString(CfApi.sessionPrefsKey, 'not-json{{{');
    expect(await AuthService.peekSavedSession(), isNull);
  });

  test('never deletes the saved blob — not even when it is corrupt',
      () async {
    // Regression: the splash must never wipe the session. A corrupt blob
    // returns null but stays on disk for inspection/repair.
    await PrefsService.setString(CfApi.sessionPrefsKey, 'not-json{{{');
    await AuthService.peekSavedSession();
    expect(await PrefsService.getString(CfApi.sessionPrefsKey), 'not-json{{{');
  });

  test('never modifies the saved blob on a successful peek', () async {
    await PrefsService.setString(
        CfApi.sessionPrefsKey, json.encode(sessionJson()));
    final before = await PrefsService.getString(CfApi.sessionPrefsKey);
    await AuthService.peekSavedSession();
    expect(await PrefsService.getString(CfApi.sessionPrefsKey), before);
  });
}
