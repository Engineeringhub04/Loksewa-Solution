import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/services/analytics/analytics_store.dart';
import 'package:loksewa_solution/services/cf_api.dart';

/// listAnalyticsSubcourses against a MockClient loksewa-api: the CF
/// session is empty in tests, so requests go out without a Bearer token
/// (CfApi only adds one when a session exists) — the mock ignores auth.
/// The rows mimic the worker's GET /analytics/list payload: flat D1 rows
/// (`id` = `<uid>__<subcourseId>`, numbers carried as text).
http.Response _json(Map<String, dynamic> body, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(json.encode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    CfApi.setTestClient(null);
  });

  group('listAnalyticsSubcourses', () {
    test('maps rows and coerces D1 text percent/points', () async {
      CfApi.setTestClient(MockClient((request) async {
        expect(request.url.path, '/analytics/list');
        return _json({
          'ok': true,
          'rows': [
            {
              'id': 'u1__sub-b',
              'parent_id': 'u1',
              'subcourseId': 'sub-b',
              'courseId': 'course-1',
              'percent': '59.72',
              'points': '594',
            },
            {
              'id': 'u1__sub-a',
              'parent_id': 'u1',
              'subcourseId': 'sub-a',
              'courseId': 'course-1',
              'percent': 12.5,
              'points': 40,
            },
          ],
        });
      }));
      final rows = await listAnalyticsSubcourses('u1');
      expect(rows, hasLength(2));
      // Sorted by subcourseId, like the old Firestore list (doc id order).
      expect(rows[0].subcourseId, 'sub-a');
      expect(rows[0].courseId, 'course-1');
      expect(rows[0].percent, 12.5);
      expect(rows[0].points, 40);
      expect(rows[1].subcourseId, 'sub-b');
      expect(rows[1].percent, 59.72);
      expect(rows[1].points, 594);
    });

    test('falls back to the row id (prefix stripped) without a field',
        () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({
          'ok': true,
          'rows': [
            {
              'id': 'u1__sub-x',
              'parent_id': 'u1',
              'courseId': 'course-9',
              'percent': '1.5',
              'points': '7',
            },
            // No subcourseId and an id that yields nothing: skipped.
            {'id': 'u1__', 'parent_id': 'u1'},
          ],
        });
      }));
      final rows = await listAnalyticsSubcourses('u1');
      expect(rows, hasLength(1));
      expect(rows.single.subcourseId, 'sub-x');
      expect(rows.single.courseId, 'course-9');
      expect(rows.single.percent, 1.5);
      expect(rows.single.points, 7);
    });

    test('returns an empty list on a server error (never throws)', () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({'ok': false, 'error': 'boom'}, 500);
      }));
      expect(await listAnalyticsSubcourses('u1'), isEmpty);
    });

    test('empty uid short-circuits without a request', () async {
      var called = false;
      CfApi.setTestClient(MockClient((request) async {
        called = true;
        return _json({'ok': true, 'rows': []});
      }));
      expect(await listAnalyticsSubcourses(''), isEmpty);
      expect(called, isFalse);
    });
  });
}
