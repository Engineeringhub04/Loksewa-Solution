import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/prefs_service.dart';

/// peekSavedSession: the splash's timeout fallback. A timed-out
/// restoreSession is NOT a logout — the token refresh was just slower than
/// the splash deadline. The splash falls back to this disk read (no network):
/// a saved session means the user was logged in.
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
}
