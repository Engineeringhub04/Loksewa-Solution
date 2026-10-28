import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/learn/discussion_tab.dart';
import 'package:loksewa_solution/services/admin_notify_service.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/discussion_service.dart';
import 'package:loksewa_solution/services/prefs_service.dart';

/// Phase-4 focused tests: the Discussion tree at the CfApi HTTP seam —
/// feed fetch + pinned re-sort, reaction toggles applying the server
/// likeCount, comment create using the returned row, and discussion
/// reports posting source + target fields to POST /reports with the
/// Discord relay firing exactly once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DiscussionService.clearReactionCache();
    await CfApi.storeAuthResult(const CfAuthResult(
      user: CfUser(uid: 'u1', email: 'a@b.c', name: 'Test User'),
      accessToken: 'acc-1',
      refreshToken: 'ref-1',
    ));
    // Seed the CF session so AuthService.currentUser
    // exists (reaction + report paths require a signed-in user).
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
  });

  tearDown(() {
    CfApi.setTestClient(null);
    AdminNotifyService.setTestClient(null);
  });

  Map<String, dynamic> postRow(
    String id, {
    String title = 'Post',
    bool pinned = false,
    String createdAt = '2026-10-02T08:30:00Z',
  }) =>
      {
        'id': id,
        'title': title,
        'body': 'body of $id',
        'category': 'tips',
        'authorName': 'Ram Sharma',
        'authorId': 'u9',
        'isPinned': pinned,
        'likeCount': 2,
        'commentCount': 0,
        'createdAt': createdAt,
      };

  group('fetchDiscussions → GET /discussions', () {
    test('passes limit=30 and maps flat rows (text scalars coerced)',
        () async {
      String? seenPath;
      String? seenLimit;
      CfApi.setTestClient(MockClient((request) async {
        seenPath = request.url.path;
        seenLimit = request.url.queryParameters['limit'];
        return http.Response(
          json.encode({
            'items': [
              postRow('p2', title: 'Newer'),
              {
                ...postRow('p1',
                    title: 'Pinned', pinned: true, createdAt: '2026-10-01T08:30:00Z'),
                'isPinned': 'true', // D1 text boolean
                'likeCount': '7', // D1 text number
              },
            ],
          }),
          200,
        );
      }));

      final posts = await DiscussionService.fetchDiscussions();
      expect(seenPath, '/discussions');
      expect(seenLimit, '30');
      expect(posts.map((p) => p.id), ['p2', 'p1']); // server order kept
      expect(posts[1].isPinned, isTrue);
      expect(posts[1].likeCount, 7);
      expect(posts[1].createdAt, DateTime.parse('2026-10-01T08:30:00Z'));
    });
  });

  group('DiscussionTab feed', () {
    testWidgets('pinned post re-sorts above the newer unpinned post',
        (tester) async {
      // The tab's online pre-check uses the connectivity platform
      // channel, which never answers in fake-async without a handler.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => ['wifi'],
      );
      CfApi.setTestClient(MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/discussions') {
          return http.Response(
            json.encode({
              'items': [
                postRow('p2',
                    title: 'Newer unpinned', createdAt: '2026-10-03T08:30:00Z'),
                postRow('p1',
                    title: 'Older pinned',
                    pinned: true,
                    createdAt: '2026-10-01T08:30:00Z'),
              ],
            }),
            200,
          );
        }
        if (request.method == 'GET' && path == '/discussion-guidelines') {
          return http.Response('{"row":null}', 200);
        }
        if (request.method == 'POST' &&
            path == '/discussions/reactions/state') {
          return http.Response('{"liked":[]}', 200);
        }
        return http.Response('{}', 404);
      }));

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        ),
        home: const DiscussionTab(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Older pinned'), findsOneWidget);
      expect(find.text('Newer unpinned'), findsOneWidget);
      final pinnedY = tester.getTopLeft(find.text('Older pinned')).dy;
      final newerY = tester.getTopLeft(find.text('Newer unpinned')).dy;
      expect(pinnedY, lessThan(newerY));
    });
  });

  group('reaction toggles apply the server likeCount', () {
    test('post toggle: state check → toggle → returns server count',
        () async {
      var stateCalls = 0;
      Map<String, dynamic>? toggleBody;
      CfApi.setTestClient(MockClient((request) async {
        final path = request.url.path;
        if (path == '/discussions/reactions/state') {
          stateCalls++;
          return http.Response('{"liked":[]}', 200);
        }
        if (path == '/discussions/reactions/toggle') {
          toggleBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"liked":true,"likeCount":7}', 200);
        }
        return http.Response('{}', 404);
      }));

      final count = await DiscussionService.toggleLikeDiscussion('p1', true);
      expect(count, 7);
      expect(toggleBody, {
        'targetType': 'post',
        'targetId': 'p1',
        'discussionId': 'p1',
      });
      // The toggle updated the cache — a state read now answers locally.
      expect(await DiscussionService.isDiscussionLiked('p1'), isTrue);
      expect(stateCalls, 1);
      // Toggling to the already-current state is a no-op (no server call).
      expect(await DiscussionService.toggleLikeDiscussion('p1', true), isNull);
      expect(stateCalls, 1);
    });

    test('comment toggle: comment target shape + server count', () async {
      Map<String, dynamic>? toggleBody;
      CfApi.setTestClient(MockClient((request) async {
        final path = request.url.path;
        if (path == '/discussions/reactions/state') {
          return http.Response('{"liked":[]}', 200);
        }
        if (path == '/discussions/reactions/toggle') {
          toggleBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"liked":true,"likeCount":3}', 200);
        }
        return http.Response('{}', 404);
      }));

      final count =
          await DiscussionService.toggleCommentLike('p1', 'c1', true);
      expect(count, 3);
      expect(toggleBody, {
        'targetType': 'comment',
        'targetId': 'c1',
        'discussionId': 'p1',
      });
    });
  });

  group('comment create uses the returned row', () {
    test('addComment returns the server id; body carries content only',
        () async {
      Map<String, dynamic>? seenBody;
      CfApi.setTestClient(MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/discussions/p1/comments') {
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({
              'row': {
                'id': 'c-new',
                'body': 'Hello',
                'authorName': 'Test User',
                'authorId': 'u1',
                'likeCount': 0,
                'createdAt': '2026-10-28T00:00:00Z',
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }));

      final id = await DiscussionService.addComment(
        'p1',
        body: 'Hello',
        authorName: 'Test User',
        authorId: 'u1',
      );
      expect(id, 'c-new');
      // Author snapshot is composed server-side — not sent by the client.
      expect(seenBody, {'content': 'Hello'});
    });

    test('createDiscussion returns the server id; content key used',
        () async {
      Map<String, dynamic>? seenBody;
      CfApi.setTestClient(MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/discussions') {
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"row":{"id":"p-new"}}', 200);
        }
        return http.Response('{}', 404);
      }));

      final id = await DiscussionService.createDiscussion(
        title: 'T',
        body: 'Body text',
        category: 'tips',
        authorName: 'Test User',
        authorId: 'u1',
        isAdmin: true,
      );
      expect(id, 'p-new');
      expect(seenBody!['title'], 'T');
      expect(seenBody!['content'], 'Body text');
      expect(seenBody!['category'], 'tips');
      expect(seenBody!.containsKey('authorName'), isFalse);
      expect(seenBody!.containsKey('likeCount'), isFalse);
    });
  });

  group('reportContent → POST /reports + single Discord relay', () {
    test('post report: source discussion + targets; relay fires once',
        () async {
      Map<String, dynamic>? reportBody;
      CfApi.setTestClient(MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/reports') {
          reportBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true,"id":"rep-9"}', 200);
        }
        return http.Response('{}', 404);
      }));
      AdminNotifyService.setTestClient(
          MockClient((_) async => http.Response('{}', 200)));

      var relayCalls = 0;
      String? relayReportId;
      final zoneClient = MockClient((request) async {
        if (request.url.host.contains('docs.google.com')) {
          return http.Response('', 200);
        }
        if (request.url.host.contains('script.google.com')) {
          relayCalls++;
          final payload =
              jsonDecode(request.body) as Map<String, dynamic>;
          relayReportId = payload['reportId'] as String?;
          return http.Response('{}', 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(
        () => DiscussionService.reportContent(
          'post',
          'p1',
          'Spam: junk',
          title: 'A title',
          preview: 'body preview',
          authorName: 'Ram Sharma',
          authorPhoto: 'https://img.example/a.png',
        ),
        () => zoneClient,
      );
      // The relay is fire-and-forget — let it land.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(reportBody, isNotNull);
      expect(reportBody!['source'], 'discussion');
      expect(reportBody!['targetType'], 'post');
      expect(reportBody!['targetId'], 'p1');
      expect(reportBody!['targetTitle'], 'A title');
      expect(reportBody!['targetPreview'], 'body preview');
      expect(reportBody!['targetAuthorName'], 'Ram Sharma');
      expect(reportBody!['targetAuthorPhoto'], 'https://img.example/a.png');
      expect(reportBody!['reason'], 'Spam: junk');
      expect(reportBody!['description'], '');
      // Reporter fields are composed by the worker.
      expect(reportBody!.containsKey('reporterId'), isFalse);
      expect(reportBody!.containsKey('status'), isFalse);
      // Exactly ONE relay call, carrying the REAL report id.
      expect(relayCalls, 1);
      expect(relayReportId, 'rep-9');
    });

    test('reply report arrives as a comment target with the reply id',
        () async {
      Map<String, dynamic>? reportBody;
      CfApi.setTestClient(MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/reports') {
          reportBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true,"id":"rep-10"}', 200);
        }
        return http.Response('{}', 404);
      }));
      AdminNotifyService.setTestClient(
          MockClient((_) async => http.Response('{}', 200)));
      final zoneClient = MockClient((request) async {
        return http.Response('', 200);
      });

      await http.runWithClient(
        () => DiscussionService.reportContent('comment', 'r1', 'Abuse: x'),
        () => zoneClient,
      );

      expect(reportBody!['source'], 'comment');
      expect(reportBody!['targetType'], 'comment');
      expect(reportBody!['targetId'], 'r1');
    });
  });

  group('guidelines', () {
    test('missing row → hardcoded defaults (fromDefaults)', () async {
      CfApi.setTestClient(MockClient((request) async {
        if (request.url.path == '/discussion-guidelines') {
          return http.Response('{"row":null}', 200);
        }
        return http.Response('{}', 404);
      }));
      final g = await DiscussionService.fetchDiscussionGuidelines();
      expect(g.fromDefaults, isTrue);
      expect(g.title, 'Community Guidelines');
    });

    test('row parses, bullets decoded from a JSON string', () async {
      CfApi.setTestClient(MockClient((request) async {
        if (request.url.path == '/discussion-guidelines') {
          return http.Response(
            json.encode({
              'row': {
                'id': 'default',
                'title': 'Rules!',
                'body': 'Be nice.',
                'bullets': '["One","Two"]',
                'version': 2,
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }));
      final g = await DiscussionService.fetchDiscussionGuidelines();
      expect(g.fromDefaults, isFalse);
      expect(g.title, 'Rules!');
      expect(g.bullets, ['One', 'Two']);
      expect(g.version, 2);
    });
  });
}
