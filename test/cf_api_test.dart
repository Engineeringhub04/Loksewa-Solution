import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round-1 Cloudflare API client: session storage, error surfacing,
/// one-shot 401 refresh, payload unwrapping and defensive decoding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    CfApi.setTestClient(null);
  });

  const loginBody = {
    'ok': true,
    'accessToken': 'acc-1',
    'refreshToken': 'ref-1',
    'user': {
      'uid': 'uid-1',
      'email': 'a@b.com',
      'name': 'A User',
      'photoURL': 'https://x/y.png',
    },
  };

  test('login stores the session and loadSavedUser reads it back', () async {
    CfApi.setTestClient(MockClient((req) async {
      expect(req.url.path, '/auth/login');
      return http.Response(jsonEncode(loginBody), 200);
    }));
    final result = await CfApi.login(email: 'a@b.com', password: 'secret1');
    expect(result.user.uid, 'uid-1');
    expect(result.user.name, 'A User');
    expect(result.isNewUser, false);

    final saved = await CfApi.loadSavedUser();
    expect(saved, isNotNull);
    expect(saved!.uid, 'uid-1');
    expect(saved.email, 'a@b.com');
    expect(saved.photoURL, 'https://x/y.png');
  });

  test('server error string surfaces as CfError', () async {
    CfApi.setTestClient(MockClient((req) async => http.Response(
        jsonEncode({'ok': false, 'error': 'needs_claim'}), 409)));
    await expectLater(
      CfApi.login(email: 'a@b.com', password: 'x'),
      throwsA(isA<CfError>()
          .having((e) => e.error, 'error', 'needs_claim')
          .having((e) => e.statusCode, 'statusCode', 409)),
    );
  });

  test('401 triggers one refresh and retries with the new token', () async {
    var meCalls = 0;
    CfApi.setTestClient(MockClient((req) async {
      if (req.url.path == '/auth/login') {
        return http.Response(jsonEncode(loginBody), 200);
      }
      if (req.url.path == '/auth/refresh') {
        return http.Response(
            jsonEncode({'ok': true, 'accessToken': 'acc-2', 'refreshToken': 'ref-2'}),
            200);
      }
      if (req.url.path == '/me') {
        meCalls++;
        if (req.headers['Authorization'] == 'Bearer acc-1') {
          return http.Response('{"ok":false,"error":"unauthorized"}', 401);
        }
        expect(req.headers['Authorization'], 'Bearer acc-2');
        return http.Response(
            jsonEncode({'ok': true, 'uid': 'uid-1', 'courseId': 'c1'}), 200);
      }
      return http.Response('{}', 404);
    }));
    await CfApi.login(email: 'a@b.com', password: 'secret1');
    final me = await CfApi.getMe();
    expect(me, isNotNull);
    expect(me!['courseId'], 'c1');
    expect(meCalls, 2);
    // The refreshed token is what stays stored.
    final saved = await CfApi.loadSavedUser();
    expect(saved, isNotNull);
  });

  test('clearSession wipes the stored session', () async {
    CfApi.setTestClient(MockClient(
        (req) async => http.Response(jsonEncode(loginBody), 200)));
    await CfApi.login(email: 'a@b.com', password: 'secret1');
    expect(await CfApi.loadSavedUser(), isNotNull);
    await CfApi.clearSession();
    expect(await CfApi.loadSavedUser(), isNull);
  });

  test('getCourses unwraps the courses/subcourses payload', () async {
    CfApi.setTestClient(MockClient((req) async => http.Response(
        jsonEncode({
          'ok': true,
          'courses': [
            {'id': 'c1', 'name': 'Course One', 'order': 1},
          ],
          'subcourses': [
            {'id': 's1', 'name': 'Sub One', 'courseId': 'c1', 'order': '2'},
          ],
        }),
        200)));
    final data = await CfApi.getCourses();
    expect(data.courses.single['id'], 'c1');
    expect(data.subcourses.single['courseId'], 'c1');
  });

  test('getConfig unwraps the appConfig object', () async {
    CfApi.setTestClient(MockClient((req) async => http.Response(
        jsonEncode({
          'ok': true,
          'appConfig': {
            'maintenanceMode': true,
            'maintenanceMessage': 'Down for maintenance',
          },
        }),
        200)));
    final cfg = await CfApi.getConfig();
    expect(cfg['maintenanceMode'], true);
    expect(cfg['maintenanceMessage'], 'Down for maintenance');
  });

  test('JSON-string fields decode defensively', () {
    expect(CfApi.decodeFieldValue('["a","b"]'), ['a', 'b']);
    expect(CfApi.decodeFieldValue('{"x":1}'), {'x': 1});
    expect(CfApi.decodeFieldValue('plain'), 'plain');
    expect(CfApi.decodeFieldValue(42), 42);
    final row = CfApi.normalizeRow({
      'id': 'q1',
      'options': '[{"text":"A"}]',
      'title': 'T',
    });
    expect(row['options'], isA<List>());
    expect((row['options'] as List).single['text'], 'A');
    expect(row['title'], 'T');
  });

  test('CfJson coercions handle D1 text/number shapes', () {
    expect(CfJson.asBool(true), isTrue);
    expect(CfJson.asBool('true'), isTrue);
    expect(CfJson.asBool('false'), isFalse);
    expect(CfJson.asBool(1), isTrue);
    expect(CfJson.asBool(null), isFalse);
    expect(CfJson.asInt('5'), 5);
    expect(CfJson.asInt(5.9), 5);
    expect(CfJson.asInt(null), 0);
    expect(CfJson.asDateTime('2026-01-01T00:00:00Z'), isNotNull);
    expect(CfJson.asDateTime(1700000000000), isNotNull);
    expect(CfJson.asDateTime({'seconds': 1700000000}), isNotNull);
    expect(CfJson.asDateTime('not-a-date'), isNull);
  });
}
