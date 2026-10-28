import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/exam_service.dart';

/// Phase-1: the Home-tree fetchers in exam_service.dart + the Phase-1
/// CfApi endpoints, exercised against a MockClient loksewa-api. The CF
/// session is empty in tests, so requests go out without a Bearer header
/// (CfApi only adds one when a session exists) — the mock ignores auth.
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

  group('CfApi Phase-1 endpoints', () {
    test('getSubjectDetail unwraps {row} and normalizes JSON strings',
        () async {
      CfApi.setTestClient(MockClient((request) async {
        expect(request.url.path, '/subjects/details/c__s__general-awareness');
        return _json({
          'ok': true,
          'row': {
            'id': 'c__s__general-awareness',
            'name': 'General Awareness',
            'order': '2',
          },
        });
      }));
      final row = await CfApi.getSubjectDetail('c__s__general-awareness');
      expect(row, isNotNull);
      expect(row!['name'], 'General Awareness');
      expect(row['order'], '2');
    });

    test('getSubjectDetail returns null on 404', () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({'ok': false, 'error': 'not_found'}, 404);
      }));
      expect(await CfApi.getSubjectDetail('missing'), isNull);
    });

    test('getNotifications splits the three feeds and decodes JSON text',
        () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({
          'ok': true,
          'personal': [
            {'id': 'n1', 'title': 'Hi', 'read': 'false'},
          ],
          'global': [
            {'id': 'g1', 'title': 'All'},
          ],
          'exam': [
            {'id': 'e1', 'type': 'exam', 'examSetIds': '["set-1"]'},
          ],
        });
      }));
      final feed = await CfApi.getNotifications();
      expect(feed.personal.single['id'], 'n1');
      expect(feed.global.single['id'], 'g1');
      expect(feed.exam.single['examSetIds'], ['set-1']);
    });

    test('bookmarks: save posts id+fields, delete issues DELETE', () async {
      final seen = <String>[];
      Map<String, dynamic>? savedBody;
      CfApi.setTestClient(MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          savedBody = json.decode(request.body) as Map<String, dynamic>;
        }
        return _json({'ok': true});
      }));
      await CfApi.saveBookmark('practice__q1', {'title': 'T'});
      await CfApi.deleteBookmark('practice__q1');
      expect(seen, [
        'POST /bookmarks',
        'DELETE /bookmarks/practice__q1',
      ]);
      expect(savedBody?['id'], 'practice__q1');
      expect(savedBody?['title'], 'T');
    });

    test('getBookmark returns null on 404', () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({'ok': false, 'error': 'not_found'}, 404);
      }));
      expect(await CfApi.getBookmark('nope'), isNull);
    });
  });

  group('exam_service CF fetchers', () {
    test('fetchSubjectDetails reads the 3 deterministic ids, skips 404s, '
        'sorts by order', () async {
      final paths = <String>[];
      CfApi.setTestClient(MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('general-awareness')) {
          return _json({
            'ok': true,
            'row': {'name': 'GA', 'order': 2},
          });
        }
        if (request.url.path.endsWith('public-management')) {
          return _json({'ok': false, 'error': 'not_found'}, 404);
        }
        return _json({
          'ok': true,
          'row': {'name': 'Tech', 'order': 1},
        });
      }));
      final out = await fetchSubjectDetails('course-x', 'sub-x');
      expect(paths.length, 3);
      expect(out.map((e) => e['name']), ['Tech', 'GA']);
      expect(out.first['id'], 'course-x__sub-x__technical-subject');
    });

    test('fetchSubjectChaptersWithProgress shapes entries and coerces '
        'string progress counts', () async {
      CfApi.setTestClient(MockClient((request) async {
        expect(request.url.path, '/subjects/chapters');
        expect(request.url.queryParameters['subjectId'], 'subj-y');
        return _json({
          'ok': true,
          'chapters': [
            {
              'id': 'ch-1',
              'name': 'One',
              'order': '1',
              'progress': {
                'chapterId': 'ch-1',
                'attempted': '3',
                'correct': '2',
                'totalQuestions': '4',
                'completed': 'false',
              },
            },
            {
              'id': 'ch-2',
              'order': 2,
              // no progress key at all -> zero progress attached
            },
          ],
        });
      }));
      final out =
          await fetchSubjectChaptersWithProgress('c', 's', 'subj-y', 'uid-1');
      expect(out.length, 2);
      final first = out.first;
      expect(first['name'], 'One');
      final progress = first['progress'] as Map<String, dynamic>;
      expect(progress['attempted'], 3);
      expect(progress['correct'], 2);
      expect(progress['totalQuestions'], 4);
      expect(progress['percentage'], 75);
      expect(progress['completed'], isFalse);
      final second = out[1]['progress'] as Map<String, dynamic>;
      expect(second['attempted'], 0);
      expect(second['completed'], isFalse);
    });

    test('fetchSubjectChapters strips progress', () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({
          'ok': true,
          'chapters': [
            {
              'id': 'ch-9',
              'name': 'Nine',
              'order': 1,
              'progress': {'attempted': 5},
            },
          ],
        });
      }));
      final out = await fetchSubjectChapters('c2', 's2', 'subj-z');
      expect(out.single['name'], 'Nine');
      expect(out.single.containsKey('progress'), isFalse);
    });

    test('fetchGorkhapatraPosts drops hidden and derives the cursor',
        () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({
          'ok': true,
          'rows': [
            {
              'id': 'p1',
              'title': 'New',
              'publishedAt': '2026-10-27T00:00:00.000Z',
              'isQuestionSet': 'true',
            },
            {
              'id': 'p2',
              'title': 'Hidden',
              'status': 'hidden',
              'publishedAt': '2026-10-26T00:00:00.000Z',
            },
            {
              'id': 'p3',
              'title': 'Old',
              'publishedAt': '2026-10-25T00:00:00.000Z',
            },
          ],
        });
      }));
      final page = await fetchGorkhapatraPosts();
      expect(page.items.map((p) => p.slug), ['p1', 'p3']);
      expect(page.items.first.isQuestionSet, isTrue);
      expect(page.items.first.publishedAt,
          DateTime.parse('2026-10-27T00:00:00.000Z'));
      expect(
          page.nextCursor,
          DateTime.parse('2026-10-25T00:00:00.000Z')
              .subtract(const Duration(milliseconds: 1)));
    });

    test('fetchMyContentPurchases sorts newest first with _ts', () async {
      CfApi.setTestClient(MockClient((request) async {
        expect(request.url.path, '/purchases/content');
        return _json({
          'ok': true,
          'rows': [
            {'id': 'a', 'createdAt': '2026-10-01T00:00:00.000Z'},
            {'id': 'b', 'createdAt': '2026-10-20T00:00:00.000Z'},
          ],
        });
      }));
      final out = await fetchMyContentPurchases('uid-1');
      expect(out.map((e) => e['id']), ['b', 'a']);
      expect(out.first['_ts'], isNonZero);
    });

    test('saveLearningProgress posts the canonical payload', () async {
      Map<String, dynamic>? body;
      CfApi.setTestClient(MockClient((request) async {
        expect(request.url.path, '/progress/learning');
        body = json.decode(request.body) as Map<String, dynamic>;
        return _json({'ok': true});
      }));
      await saveLearningProgress(
        'uid-1',
        subjectId: 'course__sub__general-awareness',
        chapterId: 'chapter-one',
        courseId: 'course',
        subcourseId: 'sub',
        attemptedQuestionIds: const ['q1'],
        correctQuestionIds: const ['q1'],
        totalQuestions: 5,
        completed: true,
      );
      expect(body?['subjectId'], 'general-awareness');
      expect(body?['chapterId'], 'chapter-one');
      expect(body?['attemptedQuestionIds'], ['q1']);
      expect(body?['totalQuestions'], 5);
      expect(body?['completed'], isTrue);
      expect(body?['lastMode'], 'practice');
    });

    test('recordAppActivity posts the usage count and never throws',
        () async {
      Map<String, dynamic>? body;
      CfApi.setTestClient(MockClient((request) async {
        expect(request.url.path, '/progress/usage');
        body = json.decode(request.body) as Map<String, dynamic>;
        return _json({'ok': true});
      }));
      await recordAppActivity('uid-1', 3);
      expect(body?['count'], 3);
    });
  });

  group('leaderboard fetchers', () {
    MockClient boardClient() => MockClient((request) async {
          if (request.url.path == '/me') {
            return _json({
              'ok': true,
              'user': {'courseId': 'course-l', 'subcourseId': 'sub-l'},
            });
          }
          expect(request.url.path, '/leaderboard');
          return _json({
            'ok': true,
            'rows': [
              {'id': 'u1__sub-l', 'uid': 'u1', 'name': 'A', 'points': 300},
              {'id': 'u2__sub-l', 'uid': 'u2', 'name': 'B', 'points': '200'},
              {'id': 'u3__sub-l', 'uid': 'u3', 'name': 'C', 'points': 200},
              {'id': 'u4__sub-l', 'uid': 'u4', 'name': 'D', 'points': 50},
            ],
            'own': {'uid': 'u2', 'points': 200},
          });
        });

    test('fetchMainLeaderboardPage slices in points order after the cursor',
        () async {
      CfApi.setTestClient(boardClient());
      noteLeaderboardScope('course-l', 'sub-l');
      final page1 = await fetchMainLeaderboardPage('sub-l', limit: 2);
      expect(page1.map((r) => r.uid), ['u1', 'u2']);
      final page2 = await fetchMainLeaderboardPage('sub-l',
          limit: 2, startAfter: page1.last);
      expect(page2.map((r) => r.uid), ['u3', 'u4']);
    });

    test('countMainLeaderboardRank counts strictly-greater rows', () async {
      CfApi.setTestClient(boardClient());
      expect(await countMainLeaderboardRank('sub-l', 200), 2);
      expect(await countMainLeaderboardRank('sub-l', 300), 1);
    });

    test('fetchMainLeaderboard dedupes per uid keeping the better row',
        () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({
          'ok': true,
          'rows': [
            {'id': 'old', 'uid': 'u1', 'name': 'A', 'points': 10},
            {'id': 'new', 'uid': 'u1', 'name': 'A', 'points': 90},
            {'id': 'x', 'uid': 'u2', 'name': 'B', 'points': 50},
          ],
        });
      }));
      noteLeaderboardScope('course-l', 'sub-l2');
      final rows = await fetchMainLeaderboard('sub-l2');
      expect(rows.map((r) => r.uid), ['u1', 'u2']);
      expect(rows.first.points, 90);
    });
  });

  group('submitQotdAnswer', () {
    QotdQuestion questionFor(String dateKey) => QotdQuestion(
          id: 'q1',
          dateKey: dateKey,
          showingDate: dateKey,
          courseId: 'c',
          courseName: 'C',
          subcourseId: 's',
          subcourseName: 'S',
          content: '2+2?',
          options: [QotdOption(id: 'A', content: '4')],
          correctOptionId: 'A',
          explanation: '',
          correctGreeting: '',
          wrongGreeting: '',
          difficulty: 'easy',
          categories: const [],
          version: 1,
          isPublished: true,
        );

    test('expired question throws before any network call', () async {
      var called = false;
      CfApi.setTestClient(MockClient((request) async {
        called = true;
        return _json({'ok': true});
      }));
      await expectLater(
        submitQotdAnswer(
          'uid-1',
          questionFor('1999-01-01'),
          'A',
          QotdSummary(totalAttempts: 0, correct: 0, averagePercent: 0),
        ),
        throwsException,
      );
      expect(called, isFalse);
    });

    test('happy path posts the attempt and builds the summary locally '
        'when the response carries none', () async {
      Map<String, dynamic>? body;
      CfApi.setTestClient(MockClient((request) async {
        expect(request.url.path, '/qotd/answer');
        body = json.decode(request.body) as Map<String, dynamic>;
        return _json({'ok': true});
      }));
      final saved = await submitQotdAnswer(
        'uid-1',
        questionFor(todayDateKey()),
        'A',
        QotdSummary(totalAttempts: 2, correct: 1, averagePercent: 50),
      );
      expect(body?['attemptId'], startsWith(todayDateKey()));
      expect(body?['selectedOptionId'], 'A');
      expect(body?['isCorrect'], isTrue);
      expect(body?['snapshot'], isA<Map>());
      expect(saved.result.isCorrect, isTrue);
      expect(saved.summary.totalAttempts, 3);
      expect(saved.summary.correct, 2);
      expect(saved.summary.averagePercent, 66.67);
    });

    test('server result/summary in the response are adopted', () async {
      CfApi.setTestClient(MockClient((request) async {
        return _json({
          'ok': true,
          'result': {
            'dateKey': todayDateKey(),
            'courseId': 'c',
            'subcourseId': 's',
            'selectedOptionId': 'A',
            'isCorrect': true,
            'answeredAt': '2026-10-28T00:00:00.000Z',
            'snapshot': {
              'id': 'q1',
              'content': '2+2?',
              'options': [
                {'id': 'A', 'content': '4'},
              ],
              'correctOptionId': 'A',
            },
          },
          'summary': {'totalAttempts': 9, 'correct': 9, 'averagePercent': 100},
        });
      }));
      final saved = await submitQotdAnswer(
        'uid-1',
        questionFor(todayDateKey()),
        'A',
        QotdSummary(totalAttempts: 0, correct: 0, averagePercent: 0),
      );
      expect(saved.summary.totalAttempts, 9);
      expect(saved.result.answeredAt, isNotNull);
      expect(saved.result.snapshot?.content, '2+2?');
    });
  });
}
