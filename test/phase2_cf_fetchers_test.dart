// Phase-2 (Exam tree → loksewa-api) focused tests:
// - NOTE-9: fetchExamProvinces parses courseIds/subcourseIds and drops
//   out-of-scope provinces (empty scope = All), order-sorted with the
//   text 'order' column coerced to int.
// - NOTE-8: saveExamAttempt's POST /exam/attempts body carries the
//   set's provinceId/sectionId/contentType (the ranking row's fields)
//   alongside the historical attempt fields.
// - Daily guard: a 409 from POST /daily-test/results maps to
//   DailyTestAlreadyAttemptedException, and GET results?modelId= with
//   {row: null} reads as "no result yet".
// - Theory stamp: CfApi.patchExamAnswer issues a PATCH carrying
//   downloadedDay/downloadedAt.
//
// Network is fully mocked through CfApi.setTestClient (MockClient) —
// the phase1_cf_fetchers_test pattern.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/exam_service.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(json.encode(body)), status);

http.Response _notFound() => _json({'ok': false, 'error': 'not_found'}, 404);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    CfApi.setTestClient(null);
  });

  test('NOTE-9: fetchExamProvinces filters by course/subcourse scope',
      () async {
    CfApi.setTestClient(MockClient((req) async {
      if (req.url.path.contains('/exam/provinces')) {
        return _json({
          'ok': true,
          'rows': [
            {
              'id': 'p-other-sub',
              'nameEn': 'Other Sub',
              'order': 0,
              'courseIds': ['c1'],
              'subcourseIds': ['scX'],
            },
            // Text order (D1 stores what Firestore held) must coerce.
            {'id': 'p-all', 'nameEn': 'All', 'order': '2'},
            {
              'id': 'p-scoped',
              'nameEn': 'Scoped',
              'order': 1,
              'courseIds': ['c1'],
              'subcourseIds': ['sc1'],
            },
            {
              'id': 'p-other-course',
              'nameEn': 'Other Course',
              'order': 0,
              'courseIds': ['cX'],
            },
          ],
        });
      }
      return _notFound();
    }));

    final provinces =
        await fetchExamProvinces(courseId: 'c1', subcourseId: 'sc1');
    // Out-of-scope rows dropped; survivors sorted by coerced order.
    expect(provinces.map((p) => p.id).toList(), ['p-scoped', 'p-all']);
    expect(provinces.first.courseIds, ['c1']);
    expect(provinces.first.subcourseIds, ['sc1']);
    expect(provinces.first.inScope(courseId: 'c1', subcourseId: 'sc1'),
        isTrue);
    expect(provinces.first.inScope(courseId: 'cX'), isFalse);
    // No scope passed → everything shows (ExamTab always passes its
    // scope, but the fetcher default stays permissive).
    final all = await fetchExamProvinces();
    expect(all.length, 4);
  });

  test('NOTE-8: saveExamAttempt POST body carries the ranking fields',
      () async {
    Map<String, dynamic>? body;
    CfApi.setTestClient(MockClient((req) async {
      if (req.method == 'POST' && req.url.path.contains('/exam/attempts')) {
        body = json.decode(req.body) as Map<String, dynamic>;
        return _json({'ok': true, 'attemptId': 'att1'});
      }
      return _notFound();
    }));

    final set = ExamSet.fromMap({
      'id': 's1',
      'title': 'Set One',
      'courseId': 'c1',
      'subcourseId': 'sc1',
      'provinceId': 'p1',
      'sectionId': 'sec1',
      'contentType': 'mcq',
      'questions': [
        {
          'question': 'Q1',
          'options': ['a', 'b'],
          'correctIndex': 0,
          'explanation': '',
        },
      ],
    });
    final score = scoreExamAttempt(set.questions, [0], set.passPercent);
    await saveExamAttempt(
      uid: 'u1',
      set: set,
      score: score,
      attemptNumber: 1,
      timeTakenSeconds: 42,
      answers: const [0],
      name: 'Test User',
      isPro: false,
    );
    expect(body, isNotNull);
    // NOTE-8: the three fields the ranking row needs, copied from the set.
    expect(body?['provinceId'], 'p1');
    expect(body?['sectionId'], 'sec1');
    expect(body?['contentType'], 'mcq');
    // The historical attempt fields ride along unchanged.
    expect(body?['examSetId'], 's1');
    expect(body?['courseId'], 'c1');
    expect(body?['subcourseId'], 'sc1');
    expect(body?['attemptNumber'], 1);
    expect(body?['score'], score.percent);
    expect(body?['totalQuestions'], 1);
    expect(body?['correct'], 1);
    expect(body?['passed'], score.passed ? 1 : 0);
    expect(body?['timeTakenSeconds'], 42);
  });

  test('daily: POST 409 maps to DailyTestAlreadyAttemptedException',
      () async {
    CfApi.setTestClient(MockClient((req) async {
      if (req.method == 'POST' &&
          req.url.path.contains('/daily-test/results')) {
        return _json({'ok': false, 'error': 'already_attempted'}, 409);
      }
      return _notFound();
    }));
    final model = DailyTestModel.fromMap({
      'id': 'm1',
      'courseId': 'c1',
      'subcourseId': 'sc1',
      'questions': [
        {
          'question': 'Q1',
          'options': ['a', 'b'],
          'correctIndex': 0,
          'explanation': '',
        },
      ],
    });
    final score = scoreDailyTest(model, model.questions, [0]);
    await expectLater(
      saveDailyTestResult(
        uid: 'u1',
        model: model,
        score: score,
        answers: const [0],
        timeTakenSeconds: 10,
      ),
      throwsA(isA<DailyTestAlreadyAttemptedException>()),
    );
  });

  test('daily: results?modelId= with {row: null} reads as no result',
      () async {
    CfApi.setTestClient(MockClient((req) async {
      if (req.method == 'GET' &&
          req.url.path.contains('/daily-test/results')) {
        return _json({'ok': true, 'row': null});
      }
      return _notFound();
    }));
    expect(await fetchDailyTestResultForModel('u1', 'm1'), isNull);
  });

  test('theory: PATCH stamp sends downloadedDay/downloadedAt', () async {
    String? method;
    String? path;
    Map<String, dynamic>? body;
    CfApi.setTestClient(MockClient((req) async {
      method = req.method;
      path = req.url.path;
      body = json.decode(req.body) as Map<String, dynamic>;
      return _json({'ok': true});
    }));
    await CfApi.patchExamAnswer('a1', {
      'downloadedDay': '2026-10-28',
      'downloadedAt': '2026-10-28T00:00:00.000Z',
    });
    expect(method, 'PATCH');
    expect(path, contains('/exam-answers/a1'));
    expect(body?['downloadedDay'], '2026-10-28');
    expect(body?['downloadedAt'], '2026-10-28T00:00:00.000Z');
  });
}
