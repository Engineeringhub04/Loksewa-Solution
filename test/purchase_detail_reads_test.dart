import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/exam_purchases.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';

/// fetchExamPurchaseById / fetchContentPurchaseById must carry the user's ID
/// token: both collections are owner-only reads, so an unauthenticated read
/// answers 403 ("Could not load this purchase").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Seed a signed-in session with a known, non-expired token (no refresh
    // is attempted, so no network happens here).
    await PrefsService.setString(
      PrefsService.sessionKey,
      json.encode({
        'user': {
          'uid': 'u1',
          'email': 'a@b.c',
          'displayName': 'Test',
          'photoURL': null,
        },
        'idToken': 'test-id-token',
        'refreshToken': 'ref',
        'expiresAt':
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      }),
    );
    await AuthService.peekSavedSession();
  });

  tearDown(() {
    FirestoreRest.setTestClient(null);
  });

  String docJson(String collection, String id) => json.encode({
        'name': 'projects/p/databases/(default)/documents/$collection/$id',
        'fields': {
          'uid': {'stringValue': 'u1'},
          'status': {'stringValue': 'pending'},
        },
      });

  test('fetchExamPurchaseById sends Authorization: Bearer <token>', () async {
    String? auth;
    String? seenPath;
    FirestoreRest.setTestClient(
      MockClient((request) async {
        auth = request.headers['Authorization'];
        seenPath = request.url.path;
        return http.Response(docJson('app_exam_purchases', 'p1'), 200);
      }),
    );
    final rec = await fetchExamPurchaseById('p1');
    expect(auth, 'Bearer test-id-token');
    expect(seenPath, contains('app_exam_purchases/p1'));
    expect(rec?.id, 'p1');
    expect(rec?.uid, 'u1');
  });

  test('fetchContentPurchaseById sends Authorization: Bearer <token>', () async {
    String? auth;
    String? seenPath;
    FirestoreRest.setTestClient(
      MockClient((request) async {
        auth = request.headers['Authorization'];
        seenPath = request.url.path;
        return http.Response(docJson('app_content_purchases', 'c9'), 200);
      }),
    );
    final rec = await fetchContentPurchaseById('c9');
    expect(auth, 'Bearer test-id-token');
    expect(seenPath, contains('app_content_purchases/c9'));
    expect(rec?.id, 'c9');
    expect(rec?.uid, 'u1');
  });

  test('returns null on 404 without throwing', () async {
    FirestoreRest.setTestClient(
      MockClient((_) async => http.Response('{}', 404)),
    );
    expect(await fetchExamPurchaseById('missing'), isNull);
    expect(await fetchContentPurchaseById('missing'), isNull);
  });
}
