import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/services/admin_gate.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/services/report_service.dart';

/// Phase-3 focused tests: the PATCH /me profile payload, the POST /reports
/// body shape, and the unified admin gate — all at the CfApi HTTP seam.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CfApi.storeAuthResult(const CfAuthResult(
      user: CfUser(uid: 'u1', email: 'a@b.c', name: 'Test User'),
      accessToken: 'acc-1',
      refreshToken: 'ref-1',
    ));
  });

  tearDown(() {
    CfApi.setTestClient(null);
  });

  group('updateUserProfile → PATCH /me payload', () {
    test('full field set, name composed, photo source included', () async {
      String? seenMethod;
      String? seenPath;
      Map<String, dynamic>? seenBody;
      CfApi.setTestClient(MockClient((request) async {
        seenMethod = request.method;
        seenPath = request.url.path;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }));

      await updateUserProfile(
        'u1',
        firstName: ' Ram ',
        lastName: 'Sharma',
        dob: '2000-01-02',
        gender: 'male',
        photoURL: 'https://img.example/p.png',
        photoURLSource: 'manual',
      );

      expect(seenMethod, 'PATCH');
      expect(seenPath, '/me');
      expect(seenBody, {
        'firstName': 'Ram',
        'lastName': 'Sharma',
        'name': 'Ram Sharma',
        'dob': '2000-01-02',
        'gender': 'male',
        'photoURL': 'https://img.example/p.png',
        'photoURLSource': 'manual',
      });
    });

    test('cleared fields send explicit nulls; photo clears as empty string',
        () async {
      Map<String, dynamic>? seenBody;
      CfApi.setTestClient(MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }));

      await updateUserProfile(
        'u1',
        firstName: 'Ram',
        lastName: '',
        dob: null,
        gender: null,
        photoURL: null,
        photoURLSource: 'none',
      );

      // The worker's PATCH merge treats explicit null as a CLEAR for
      // dob/gender/photoURLSource; photoURL is stringified server-side,
      // so its clear encoding is ''.
      expect(seenBody!.containsKey('dob'), isTrue);
      expect(seenBody!['dob'], isNull);
      expect(seenBody!.containsKey('gender'), isTrue);
      expect(seenBody!['gender'], isNull);
      expect(seenBody!['photoURL'], '');
      expect(seenBody!['photoURLSource'], 'none');
    });

    test('photoURLSource omitted when the photo was untouched', () async {
      Map<String, dynamic>? seenBody;
      CfApi.setTestClient(MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }));

      await updateUserProfile(
        'u1',
        firstName: 'Ram',
        lastName: 'Sharma',
        photoURL: 'https://img.example/p.png',
      );

      expect(seenBody!.containsKey('photoURLSource'), isFalse);
    });
  });

  group('ReportService history → POST /reports shape', () {
    test('problem report sends content fields only (reporter server-side)',
        () async {
      // Seed the CF session so AuthService.currentUser
      // exists (the history write requires a signed-in user).
      await PrefsService.setString(
        CfApi.sessionPrefsKey,
        json.encode({
          'user': {
            'uid': 'u1',
            'email': 'a@b.c',
            'name': 'Test User',
            'photoURL': null,
          },
          'accessToken': 'test-access-token',
          'refreshToken': 'ref',
        }),
      );
      await AuthService.peekSavedSession();

      Map<String, dynamic>? reportBody;
      final client = MockClient((request) async {
        if (request.url.host.contains('docs.google.com')) {
          return http.Response('', 200);
        }
        if (request.url.path == '/reports') {
          reportBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true,"id":"rep-1"}', 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(
        () => ReportService.submitProblemReport(
          category: 'Payment issue',
          description: 'Charged twice',
        ),
        () => client,
      );

      expect(reportBody, isNotNull);
      expect(reportBody!['source'], 'app');
      expect(reportBody!['targetType'], 'app');
      expect(reportBody!['targetId'], 'app-problem');
      expect(reportBody!['targetTitle'], 'Payment issue');
      expect(reportBody!['contextLabel'], 'App · Report a Problem');
      expect(reportBody!['reason'], 'Payment issue');
      expect(reportBody!['description'], 'Charged twice');
      // Reporter fields / status / timestamps are composed by the worker.
      expect(reportBody!.containsKey('reporterId'), isFalse);
      expect(reportBody!.containsKey('reporterName'), isFalse);
      expect(reportBody!.containsKey('status'), isFalse);
      expect(reportBody!.containsKey('createdAt'), isFalse);
    });
  });

  group('changePassword → POST /auth/change-password body', () {
    test('includes the current session refresh token (spares this device)',
        () async {
      String? seenMethod;
      String? seenPath;
      Map<String, dynamic>? seenBody;
      CfApi.setTestClient(MockClient((request) async {
        seenMethod = request.method;
        seenPath = request.url.path;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }));

      await CfApi.changePassword(
          oldPassword: 'old-pass', newPassword: 'new-pass');

      expect(seenMethod, 'POST');
      expect(seenPath, '/auth/change-password');
      // 'ref-1' is the refresh token storeAuthResult seeded in setUp —
      // the same _session source the refresh/logout paths read. The
      // worker revokes every OTHER session; omitting it signs this
      // device out too once the access token expires.
      expect(seenBody, {
        'oldPassword': 'old-pass',
        'newPassword': 'new-pass',
        'refreshToken': 'ref-1',
      });
    });

    test('no session → refreshToken omitted, passwords only', () async {
      await CfApi.clearSession();
      Map<String, dynamic>? seenBody;
      CfApi.setTestClient(MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }));

      await CfApi.changePassword(
          oldPassword: 'old-pass', newPassword: 'new-pass');

      expect(seenBody, {
        'oldPassword': 'old-pass',
        'newPassword': 'new-pass',
      });
    });
  });

  group('admin gate (isAdminMe)', () {
    test('role admin passes', () {
      expect(isAdminMe({'role': 'admin'}), isTrue);
    });

    test('legacy isAdmin flag passes (bool and text forms)', () {
      expect(isAdminMe({'isAdmin': true}), isTrue);
      expect(isAdminMe({'isAdmin': 'true'}), isTrue);
    });

    test('plain users and missing rows fail', () {
      expect(isAdminMe({'role': 'user'}), isFalse);
      expect(isAdminMe({'isAdmin': false}), isFalse);
      expect(isAdminMe({}), isFalse);
      expect(isAdminMe(null), isFalse);
    });

    test('fetchIsAdmin reads GET /me', () async {
      CfApi.setTestClient(MockClient((request) async {
        expect(request.url.path, '/me');
        return http.Response(
            jsonEncode({
              'ok': true,
              'user': {'uid': 'u1', 'role': 'admin'},
            }),
            200);
      }));
      expect(await fetchIsAdmin(), isTrue);
    });
  });
}
