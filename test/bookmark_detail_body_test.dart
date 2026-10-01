import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/user/bookmark_detail_screen.dart';
import 'package:loksewa_solution/screens/user/bookmark_remove_dialog.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

Map<String, dynamic> _questionBookmark() => {
      'title': 'What is the capital of Nepal?',
      'context': 'practice',
      'sourceLabel': 'Practice Mode · General Knowledge',
      'preview': 'Kathmandu is the capital city.',
      'createdAt': '2026-09-30T10:00:00.000Z',
      'payload': {
        'question': 'What is the capital of Nepal?',
        'options': ['Pokhara', 'Kathmandu', 'Biratnagar', 'Dharan'],
        'answerIndex': 1,
        'explanation': 'Kathmandu has been the capital for centuries.',
        'meta': [
          {'label': 'Chapter', 'value': 'General Knowledge'},
        ],
      },
    };

void main() {
  group('BookmarkDetailBody — reveal gating (explanation bug)', () {
    testWidgets('explanation is hidden until Reveal is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookmarkDetailBody(bookmark: _questionBookmark()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Question + options visible, explanation + correct mark hidden.
      expect(find.text('What is the capital of Nepal?'), findsOneWidget);
      expect(find.text('Kathmandu'), findsOneWidget);
      expect(find.text('Kathmandu has been the capital for centuries.'),
          findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      // Reveal → explanation and the correct option appear.
      await tester.tap(find.text('Reveal answer'));
      await tester.pumpAndSettle();
      expect(find.text('Kathmandu has been the capital for centuries.'),
          findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Hide → explanation disappears again.
      await tester.tap(find.text('Hide answer'));
      await tester.pumpAndSettle();
      expect(find.text('Kathmandu has been the capital for centuries.'),
          findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('subject track hero shows SUBJECT QUESTION',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookmarkDetailBody(bookmark: _questionBookmark()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SUBJECT QUESTION'), findsOneWidget);
    });

    testWidgets('GK sourceLabel bookmark shows the GK track hero',
        (WidgetTester tester) async {
      final b = _questionBookmark()
        ..['sourceLabel'] = 'gk · Read Mode';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookmarkDetailBody(bookmark: b),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('GK'), findsOneWidget);
      expect(find.text('SUBJECT QUESTION'), findsNothing);
    });
  });

  group('BookmarkDetailBody — article layout', () {
    testWidgets('article bookmark renders the premium article card',
        (WidgetTester tester) async {
      final b = {
        'title': 'Gorkhapatra headline',
        'context': 'article',
        'sourceLabel': 'Gorkhapatra',
        'payload': {
          'body': 'This is the full article body text for reading.'
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookmarkDetailBody(bookmark: b),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This is the full article body text for reading.'),
          findsOneWidget);
      // No question UI for articles.
      expect(find.text('Reveal answer'), findsNothing);
      expect(find.text('ARTICLE'), findsOneWidget);
    });
  });

  group('BookmarkDetailScreen — header delete flow', () {
    testWidgets(
        'tapping the header delete icon, confirming in the modal, removes '
        'the bookmark and pops back', (WidgetTester tester) async {
      final removedIds = <String>[];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
              path: '/',
              builder: (_, __) =>
                  const Scaffold(body: Center(child: Text('home')))),
          GoRoute(
            path: '/bookmarks/:id',
            builder: (_, s) => BookmarkDetailScreen(
              id: s.pathParameters['id']!,
              loadBookmark: () async => _questionBookmark(),
              deleteBookmark: (id, _) async {
                removedIds.add(id);
              },
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      // push (not go) so '/' stays underneath — the delete flow pops back.
      router.push('/bookmarks/practice__q1');
      // Let the injected load complete and the entrance animations settle
      // (pump with durations — never pumpAndSettle — per repo test lessons).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('home'), findsNothing);
      // Modern delete icon (delete_outline) rendered in the header.
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('Remove this bookmark?'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(removedIds, ['practice__q1']);
      // The bookmark is gone, so the detail route popped back home.
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('dismissing the confirm modal removes nothing',
        (WidgetTester tester) async {
      final removedIds = <String>[];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
              path: '/',
              builder: (_, __) =>
                  const Scaffold(body: Center(child: Text('home')))),
          GoRoute(
            path: '/bookmarks/:id',
            builder: (_, s) => BookmarkDetailScreen(
              id: s.pathParameters['id']!,
              loadBookmark: () async => _questionBookmark(),
              deleteBookmark: (id, _) async {
                removedIds.add(id);
              },
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.push('/bookmarks/practice__q1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppModalShell), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(removedIds, isEmpty);
      // Still on the detail page — nothing was deleted.
      expect(find.text('home'), findsNothing);
      expect(find.text('What is the capital of Nepal?'), findsOneWidget);
    });
  });

  group('BookmarkRemoveDialog — AppModalShell global modal', () {
    testWidgets('uses AppModalShell; Remove pops true',
        (WidgetTester tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await AppModalShell.show<bool>(
                  context: context,
                  builder: (c) => const BookmarkRemoveDialog(
                      item: {'title': 'Sample bookmark'}),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('Remove this bookmark?'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('Cancel pops false', (WidgetTester tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await AppModalShell.show<bool>(
                  context: context,
                  builder: (c) => const BookmarkRemoveDialog(
                      item: {'title': 'Sample bookmark'}),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
