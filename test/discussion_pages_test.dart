import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/screens/user/discussion_create_screen.dart';
import 'package:loksewa_solution/screens/user/discussion_detail_screen.dart';

/// Widget tests for the rebuilt Discussion detail + create pages.
///
/// Network is faked with http.runWithClient + MockClient so the CfApi
/// client never leaves the test (Phase-4: the worker endpoints below).
/// AuthService has no session in tests → signed out (like toggles revert,
/// composers hidden on detail).
///
/// Conventions: no pumpAndSettle while infinite animations exist (all page
/// animations here are finite); UTF-8 Response.bytes for Devanagari bodies.

http.Response _json(Object body, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(json.encode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// Flat CF row for the detail post (Firestore field names, ISO timestamps).
Map<String, dynamic> _postRow() => {
      'id': 'p1',
      'title': 'Exam tips',
      'body': 'Study daily and revise weekly.',
      'category': 'tips',
      'authorName': 'Ram Sharma',
      'authorId': 'u1',
      'isAdmin': true,
      'isSeed': false,
      'likeCount': 5,
      'commentCount': 2,
      'createdAt': '2026-10-02T08:30:00Z',
    };

Map<String, dynamic> _commentRow(String id, String body, String author) => {
      'id': id,
      'body': body,
      'authorName': author,
      'authorId': 'u2',
      'likeCount': 1,
      'createdAt': '2026-10-02T09:00:00Z',
    };

/// Fake loksewa-api: post row + comments list. [postStatus] lets tests
/// simulate a deleted post (404).
MockClient _mockDetail({int postStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/discussions/p1') {
      if (postStatus != 200) return _json({}, postStatus);
      return _json({'row': _postRow()});
    }
    if (request.method == 'GET' && path == '/discussions/p1/comments') {
      return _json({
        'items': [
          _commentRow('c1', 'Great tips!', 'Sita'),
          _commentRow('c2', 'Thanks!', 'Hari'),
        ],
      });
    }
    return _json({}, 404);
  });
}

Widget _app(Widget home) => MaterialApp(
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
      ),
      home: home,
    );

void main() {
  group('DiscussionDetailScreen', () {
    testWidgets('renders post card + comments after load',
        (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
              _app(const DiscussionDetailScreen(id: 'p1')));
          // Loading gate.
          expect(find.text('Loading comments...'), findsOneWidget);
          await tester.pumpAndSettle();
          // Post header (shared card) with title + body.
          expect(find.text('Exam tips'), findsOneWidget);
          expect(
              find.textContaining('Study daily and revise',
                  findRichText: true),
              findsOneWidget);
          // Comments heading with live count pill (header title + section).
          expect(find.text('Comments'), findsNWidgets(2));
          expect(find.text('2'), findsWidgets);
          // Both comments rendered.
          expect(
              find.textContaining('Great tips!', findRichText: true),
              findsOneWidget);
          expect(find.textContaining('Thanks!', findRichText: true),
              findsOneWidget);
          // Signed out → no bottom composer.
          expect(find.text('Write a comment...'), findsNothing);
        },
        () => _mockDetail(),
      );
    });

    testWidgets('deleted post shows the deleted state', (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
              _app(const DiscussionDetailScreen(id: 'p1')));
          await tester.pumpAndSettle();
          expect(find.text('This post has been deleted'),
              findsOneWidget);
        },
        () => _mockDetail(postStatus: 404),
      );
    });

    testWidgets('reply thread expands on View replies tap',
        (tester) async {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/discussions/p1') {
          return _json({'row': _postRow()});
        }
        if (request.method == 'GET' && path == '/discussions/p1/comments') {
          return _json({
            'items': [_commentRow('c1', 'Great tips!', 'Sita')],
          });
        }
        if (request.method == 'GET' &&
            path == '/discussions/p1/comments/c1/replies') {
          return _json({
            'items': [_commentRow('r1', 'Agreed!', 'Gita')],
          });
        }
        return _json({}, 404);
      });
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
              _app(const DiscussionDetailScreen(id: 'p1')));
          await tester.pumpAndSettle();
          // Open the single reply thread.
          await tester.tap(find.text('View replies').first);
          await tester.pumpAndSettle();
          expect(
              find.textContaining('Agreed!', findRichText: true),
              findsOneWidget);
          // Toggle closes it again.
          await tester.tap(find.text('Hide replies').first);
          await tester.pumpAndSettle();
          expect(
              find.textContaining('Agreed!', findRichText: true),
              findsNothing);
        },
        () => client,
      );
    });
  });

  group('DiscussionCreateScreen', () {
    testWidgets('new-post form: chips, body, disabled submit',
        (tester) async {
      await tester.pumpWidget(_app(const DiscussionCreateScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Create Post'), findsWidgets);
      // Category chips (not a dropdown).
      expect(find.text('Tips'), findsOneWidget);
      expect(find.text('Resources'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Question'), findsOneWidget);
      // Non-admin (no profile in tests) → no title field.
      expect(find.text('Title'), findsNothing);
      // Submit disabled with empty body: the tap target is the GestureDetector
      // wrapping the submit label.
      final submit = find.ancestor(
          of: find.text('Post'), matching: find.byType(GestureDetector));
      expect(submit, findsOneWidget);
      expect(tester.widget<GestureDetector>(submit).onTap, isNull);
      // Typing a body enables the preview section toggle.
      await tester.enterText(
          find.byType(TextField).last, 'Hello discussion');
      await tester.pump();
      expect(find.text('Preview'), findsOneWidget);
    });

    testWidgets('chip selection toggles', (tester) async {
      await tester.pumpWidget(_app(const DiscussionCreateScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tips'));
      await tester.pump();
      // Tapping again clears the selection (no assertion on visuals —
      // just that it doesn't throw and stays interactive).
      await tester.tap(find.text('Tips'));
      await tester.pump();
      expect(find.text('Tips'), findsOneWidget);
    });
  });
}
