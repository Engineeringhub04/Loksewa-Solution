import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/prefs_service.dart';

/// peekSavedSession: the splash's cold-start session read. A saved session on
/// disk means the user is logged in — this read NEVER wipes, so a link tap
/// (or any cold start) can never log the user out. No network is touched;
/// the token refresh happens lazily via getValidIdToken.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Map<String, dynamic> sessionJson({bool expired = true}) => {
        'user': {
          'uid': 'u1',
          'email': 'a@b.c',
          'displayName': 'Test',
          'photoURL': null,
        },
        'idToken': 'tok',
        'refreshToken': 'ref',
        'expiresAt': (expired
                ? DateTime.now().subtract(const Duration(hours: 2))
                : DateTime.now().add(const Duration(hours: 1)))
            .toIso8601String(),
      };

  test('returns the saved user without touching the network', () async {
    // PrefsService caches its instance, so seed via its own write path.
    await PrefsService.setString(
        PrefsService.sessionKey, json.encode(sessionJson()));
    final user = await AuthService.peekSavedSession();
    expect(user?.uid, 'u1');
    // Installed in memory so getValidIdToken retries the refresh itself
    // instead of sending API requests with an empty token.
    expect(AuthService.currentUser?.uid, 'u1');
  });

  test('returns null when nothing was saved', () async {
    await PrefsService.remove(PrefsService.sessionKey);
    expect(await AuthService.peekSavedSession(), isNull);
  });

  test('returns null on a corrupt blob and never throws', () async {
    await PrefsService.setString(PrefsService.sessionKey, 'not-json{{{');
    expect(await AuthService.peekSavedSession(), isNull);
  });

  test('never deletes the saved blob — not even when it is corrupt', () async {
    // Regression: the splash must never wipe the session. A corrupt blob
    // returns null but stays on disk for inspection/repair.
    await PrefsService.setString(PrefsService.sessionKey, 'not-json{{{');
    await AuthService.peekSavedSession();
    expect(await PrefsService.getString(PrefsService.sessionKey),
        'not-json{{{');
  });

  test('never deletes the saved blob for an expired session', () async {
    await PrefsService.setString(
        PrefsService.sessionKey, json.encode(sessionJson(expired: true)));
    final before =
        await PrefsService.getString(PrefsService.sessionKey);
    await AuthService.peekSavedSession();
    expect(await PrefsService.getString(PrefsService.sessionKey), before);
  });
}
