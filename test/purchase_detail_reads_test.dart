import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/exam_purchases.dart';

/// Phase-5: fetchExamPurchaseById / fetchContentPurchaseById resolve
/// through GET /purchases/mine on loksewa-api (CF Bearer) — the owner
/// lists carry every purchase the caller owns, and the by-id lookups
/// find their row in the matching list. An id the caller does not own
/// (or that does not exist) resolves to null.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CfApi.storeAuthResult(const CfAuthResult(
      user: CfUser(uid: 'u1', email: 'a@b.c', name: 'Test'),
      accessToken: 'acc-1',
      refreshToken: 'ref-1',
    ));
  });

  tearDown(() {
    CfApi.setTestClient(null);
  });

  Map<String, dynamic> mineBody() => {
        'exam': [
          {
            'id': 'p1',
            'uid': 'u1',
            'status': 'pending',
            'examSetId': 'set-1',
            'amount': 500,
            'submittedAt': '2026-10-01T00:00:00.000Z',
          },
        ],
        'content': [
          {
            'id': 'c9',
            'uid': 'u1',
            'status': 'active',
            'contentType': 'subject',
            'contentId': 'sub-1',
            'amount': 300,
            'submittedAt': '2026-10-02T00:00:00.000Z',
          },
        ],
      };

  void installClient(List<String> seen) {
    CfApi.setTestClient(
      MockClient((request) async {
        seen.add(
            '${request.method} ${request.url.path} ${request.headers['Authorization']}');
        return http.Response(json.encode(mineBody()), 200);
      }),
    );
  }

  test('fetchExamPurchaseById reads /purchases/mine with the CF Bearer',
      () async {
    final seen = <String>[];
    installClient(seen);
    final rec = await fetchExamPurchaseById('p1');
    expect(seen, ['GET /purchases/mine Bearer acc-1']);
    expect(rec?.id, 'p1');
    expect(rec?.uid, 'u1');
    expect(rec?.examSetId, 'set-1');
  });

  test('fetchContentPurchaseById reads /purchases/mine with the CF Bearer',
      () async {
    final seen = <String>[];
    installClient(seen);
    final rec = await fetchContentPurchaseById('c9');
    expect(seen, ['GET /purchases/mine Bearer acc-1']);
    expect(rec?.id, 'c9');
    expect(rec?.uid, 'u1');
    expect(rec?.contentId, 'sub-1');
    expect(rec?.status, 'active');
  });

  test('absent ids resolve to null (no throw)', () async {
    installClient(<String>[]);
    expect(await fetchExamPurchaseById('nope'), isNull);
    expect(await fetchContentPurchaseById('nope'), isNull);
  });
}
