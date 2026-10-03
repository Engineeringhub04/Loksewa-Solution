// Widget tests for the discussion widgets:
// - DiscussionHeartLike: optimistic toggle + count, revert on failed future
// - DiscussionPostCard: title/body/category chip/admin accent/footer
// - DiscussionCommentCard: reply indentation, editedAt never displayed
// - DiscussionActionMenu: items, danger color, select + barrier dismiss
// - DiscussionReportDialog: chip selection + submit success/failure paths
// - DiscussionGuidelinesDialog: seed success/failure paths
//
// Conventions: small pump durations (never pumpAndSettle across the finite
// heart-pop/menu/dialog animations); no path_provider anywhere here.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/discussion_service.dart';
import 'package:loksewa_solution/widgets/discussion/discussion_action_menu.dart';
import 'package:loksewa_solution/widgets/discussion/discussion_comment_card.dart';
import 'package:loksewa_solution/widgets/discussion/discussion_guidelines_dialog.dart';
import 'package:loksewa_solution/widgets/discussion/discussion_heart_like.dart';
import 'package:loksewa_solution/widgets/discussion/discussion_post_card.dart';
import 'package:loksewa_solution/widgets/discussion/discussion_report_dialog.dart';

void main() {
  setUp(() {
    AppLanguage.current.value = 'en';
  });

  Widget wrap({required Widget Function(BuildContext) launcher}) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB)),
      ),
      home: Scaffold(body: Builder(builder: launcher)),
    );
  }

  group('DiscussionHeartLike', () {
    testWidgets('toggles liked state and updates the count', (tester) async {
      final toggledTo = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiscussionHeartLike(
            initialLiked: false,
            likeCount: 5,
            onToggle: (v) async {
              toggledTo.add(v);
            },
          ),
        ),
      ));
      expect(find.text('5'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.byType(DiscussionHeartLike));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(toggledTo, [true]);
      expect(find.text('6'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      // Toggle back.
      await tester.tap(find.byType(DiscussionHeartLike));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(toggledTo, [true, false]);
      expect(find.text('5'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('reverts the optimistic flip when the future fails',
        (tester) async {
      // A controllable future: lets the test observe the optimistic flip
      // while the toggle is in flight, then fail it.
      final toggle = Completer<void>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiscussionHeartLike(
            initialLiked: false,
            likeCount: 5,
            onToggle: (_) => toggle.future,
          ),
        ),
      ));

      await tester.tap(find.byType(DiscussionHeartLike));
      await tester.pump();
      // Optimistic flip is visible while the toggle is in flight.
      expect(find.text('6'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      // The failed future reverts locally and surfaces nothing (the
      // parent owns any toast).
      toggle.completeError(Exception('network down'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('5'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('comment/reply pop params are honored', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiscussionHeartLike(
            initialLiked: false,
            likeCount: 0,
            onToggle: (_) async {},
            popScale: 1.24,
            popUpMs: 110,
            popDownMs: 150,
          ),
        ),
      ));
      // The widget accepts the comment/reply tuning without error; the
      // finite pop completes and the count still updates.
      await tester.tap(find.byType(DiscussionHeartLike));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('DiscussionPostCard', () {
    testWidgets('shows title, body, admin badge and title accent',
        (tester) async {
      final post = DiscussionPost(
        id: 'p1',
        title: 'How to prepare for Kharidar?',
        body: 'Start with the syllabus and past questions.',
        category: 'tips',
        authorName: 'Ram Sharma',
        isAdmin: true,
        likeCount: 12,
        commentCount: 3,
        createdAt: DateTime(2026, 10, 2, 8, 30),
      );
      bool? likeArg;
      var menuTapped = false;
      var cardTapped = false;
      Offset? menuAnchor;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        ),
        home: Scaffold(
          body: DiscussionPostCard(
            post: post,
            liked: false,
            onToggleLike: (v) async {
              likeArg = v;
            },
            onTap: () => cardTapped = true,
            onMenu: (anchor) {
              menuTapped = true;
              menuAnchor = anchor;
            },
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('How to prepare for Kharidar?'), findsOneWidget);
      // Body renders via DiscussionLinkText (RichText spans).
      expect(find.textContaining('Start with the syllabus', findRichText: true),
          findsOneWidget);
      // React parity: no category chip on the card; admin badge instead.
      expect(find.text('Tips'), findsNothing);
      expect(find.text('Admin'), findsOneWidget);

      // Title accent bar: 4px primary bar beside the title.
      final primary = Theme.of(tester.element(find.byType(DiscussionPostCard)))
          .colorScheme
          .primary;
      expect(
          find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == primary &&
              w.constraints?.minWidth == 4),
          findsOneWidget);

      // Footer: like count, comment count; date lives in the meta line.
      expect(find.text('12'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Card tap zone works; the like button bridges to onToggleLike.
      await tester.tap(find.text('How to prepare for Kharidar?'));
      await tester.pump();
      expect(cardTapped, isTrue);
      await tester.tap(find.byType(DiscussionHeartLike));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(likeArg, isTrue);
      expect(menuTapped, isFalse);

      // The overflow menu reports the button's global anchor for the menu.
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pump();
      expect(menuTapped, isTrue);
      expect(menuAnchor, isNotNull);
      expect(menuAnchor!.dx, greaterThan(0));
      expect(menuAnchor!.dy, greaterThan(0));
    });

    testWidgets('non-admin titled card keeps the title accent bar',
        (tester) async {
      final post = DiscussionPost(
        id: 'p2',
        title: 'Study group?',
        body: 'Anyone in Kathmandu?',
        category: 'general',
        authorName: 'Hari',
        createdAt: DateTime(2026, 10, 3),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiscussionPostCard(
            post: post,
            liked: true,
            onToggleLike: (_) async {},
            onTap: () {},
            onMenu: (_) {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      // React parity: the 4px title accent bar renders for ANY post with a
      // title (not just admins); there is no admin edge bar anymore.
      final primary = Theme.of(tester.element(find.byType(DiscussionPostCard)))
          .colorScheme
          .primary;
      expect(
          find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == primary &&
              w.constraints?.minWidth == 4),
          findsOneWidget);
      // No admin badge on a non-admin card.
      expect(find.text('Admin'), findsNothing);
    });
  });

  group('DiscussionCommentCard', () {
    testWidgets('reply indents 40px with a connector line; editedAt hidden',
        (tester) async {
      final comment = DiscussionComment(
        id: 'c1',
        body: 'Great explanation, thanks!',
        authorName: 'Sita',
        likeCount: 2,
        createdAt: DateTime(2026, 10, 1),
        editedAt: DateTime(2026, 10, 2),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiscussionCommentCard(
            comment: comment,
            isReply: true,
            liked: false,
            onToggleLike: (_) async {},
            onMenu: (_) {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Great explanation, thanks!'), findsOneWidget);
      expect(find.text('Sita'), findsOneWidget);
      // Reply indentation: 40px left padding + 2px connector line.
      expect(
          find.byWidgetPredicate((w) =>
              w is Padding && w.padding == const EdgeInsets.only(left: 40)),
          findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxWidth == 2),
          findsOneWidget);
      // editedAt is never displayed anywhere.
      expect(find.textContaining('dited', findRichText: true), findsNothing);
      // No reply chrome lives inside the card.
      expect(find.text('Reply'), findsNothing);
      expect(find.textContaining('replies', findRichText: true), findsNothing);
    });

    testWidgets('top-level comment has no indentation', (tester) async {
      final comment = DiscussionComment(
        id: 'c2',
        body: 'Nice post',
        authorName: 'Hari',
        createdAt: DateTime(2026, 10, 1),
      );
      var menuTapped = false;
      Offset? menuAnchor;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiscussionCommentCard(
            comment: comment,
            isReply: false,
            liked: true,
            onToggleLike: (_) async {},
            onMenu: (anchor) {
              menuTapped = true;
              menuAnchor = anchor;
            },
          ),
        ),
      ));
      await tester.pump();

      expect(
          find.byWidgetPredicate((w) =>
              w is Padding && w.padding == const EdgeInsets.only(left: 40)),
          findsNothing);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      expect(menuTapped, isTrue);
      expect(menuAnchor, isNotNull);
    });
  });

  group('DiscussionActionMenu', () {
    Future<void> openMenu(WidgetTester tester,
        {required void Function(String) onSelect,
        required void Function() onDone}) async {
      await tester.pumpWidget(wrap(
        launcher: (ctx) => ElevatedButton(
          onPressed: () {
            DiscussionActionMenu.show(
              context: ctx,
              anchorTopRight: const Offset(780, 120),
              items: [
                DiscussionMenuItem(
                    label: 'Edit', onSelect: () => onSelect('edit')),
                DiscussionMenuItem(
                    label: 'Delete',
                    danger: true,
                    onSelect: () => onSelect('delete')),
              ],
            ).then((_) => onDone());
          },
          child: const Text('open menu'),
        ),
      ));
      await tester.tap(find.text('open menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('shows items; danger item is red', (tester) async {
      await openMenu(tester, onSelect: (_) {}, onDone: () {});
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      final deleteText = tester.widget<Text>(find.text('Delete'));
      expect(deleteText.style?.color, const Color(0xFFEF4444));
      final editText = tester.widget<Text>(find.text('Edit'));
      expect(editText.style?.color, isNot(const Color(0xFFEF4444)));
    });

    testWidgets('tapping an item closes the menu then calls onSelect',
        (tester) async {
      String? selected;
      var dismissed = false;
      await openMenu(tester,
          onSelect: (s) => selected = s, onDone: () => dismissed = true);

      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Delete'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(selected, 'delete');
      expect(dismissed, isTrue);
    });

    testWidgets('barrier tap dismisses without selecting', (tester) async {
      String? selected;
      var dismissed = false;
      await openMenu(tester,
          onSelect: (s) => selected = s, onDone: () => dismissed = true);

      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Edit'), findsNothing);
      expect(selected, isNull);
      expect(dismissed, isTrue);
    });
  });

  group('DiscussionReportDialog', () {
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
    }
    Future<void> openReport(
      WidgetTester tester, {
      required Future<void> Function(String type, String id, String reason)
          submit,
      required void Function(bool) onDone,
    }) async {
      await tester.pumpWidget(wrap(
        launcher: (ctx) => ElevatedButton(
          onPressed: () {
            DiscussionReportDialog.show(
              context: ctx,
              targetType: 'post',
              targetId: 'p1',
              targetTitle: 'Spammy post title',
              submitForTest: submit,
            ).then(onDone);
          },
          child: const Text('report'),
        ),
      ));
      await tester.tap(find.text('report'));
      await tester.pump();
      // Debug-only: TextField inside showGeneralDialog carries no Material
      // ancestor (see app_modal_shell_test.dart); consume and continue.
      tester.takeException();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('chip selection + submit success returns true', (tester) async {
      useTallViewport(tester);
      String? capturedType;
      String? capturedId;
      String? capturedReason;
      bool? result;
      await openReport(tester,
          submit: (t, id, reason) async {
            capturedType = t;
            capturedId = id;
            capturedReason = reason;
          },
          onDone: (v) => result = v);

      expect(find.text('Spam'), findsOneWidget);
      await tester.tap(find.text('Spam'));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), 'Link spam in comments');
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(capturedType, 'post');
      expect(capturedId, 'p1');
      expect(capturedReason, 'Spam: Link spam in comments');
      expect(find.text('Spam'), findsNothing); // dialog closed
      expect(result, isTrue);
    });

    testWidgets('submit failure keeps the dialog open with an inline error',
        (tester) async {
      useTallViewport(tester);
      bool? result;
      await openReport(tester,
          submit: (_, __, ___) async {
            throw Exception('nope');
          },
          onDone: (v) => result = v);

      await tester.tap(find.text('Other'));
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget); // still open
      expect(find.text('Submit report'), findsOneWidget); // spinner off
      expect(result, isNull);
    });

    testWidgets('submit without a type shows an inline prompt', (tester) async {
      useTallViewport(tester);
      await openReport(tester, submit: (_, __, ___) async {}, onDone: (_) {});
      await tester.tap(find.text('Submit report'));
      await tester.pump();
      expect(find.textContaining('Please select a report type'),
          findsOneWidget);
      expect(find.text('Report content'), findsOneWidget); // still open
    });
  });

  group('DiscussionGuidelinesDialog', () {
    const guidelines = DiscussionGuidelines(
      title: 'Community Guidelines',
      body: 'Be kind.',
      bullets: ['No spam.', 'No abuse.'],
    );

    Future<void> openGuidelines(
      WidgetTester tester, {
      bool showSeedButton = false,
      required Future<void> Function() onSeed,
      required void Function(bool) onDone,
    }) async {
      await tester.pumpWidget(wrap(
        launcher: (ctx) => ElevatedButton(
          onPressed: () {
            DiscussionGuidelinesDialog.show(
              context: ctx,
              guidelines: guidelines,
              showSeedButton: showSeedButton,
              onSeed: onSeed,
            ).then(onDone);
          },
          child: const Text('guidelines'),
        ),
      ));
      await tester.tap(find.text('guidelines'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shows title, body and bullets', (tester) async {
      await openGuidelines(tester, onSeed: () async {}, onDone: (_) {});
      expect(find.text('Community Guidelines'), findsOneWidget);
      expect(find.text('Be kind.'), findsOneWidget);
      expect(find.text('No spam.'), findsOneWidget);
      expect(find.text('No abuse.'), findsOneWidget);
      expect(find.text('Save Guidelines'), findsNothing);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('seed success closes the dialog and returns true',
        (tester) async {
      var seeded = false;
      bool? result;
      await openGuidelines(tester,
          showSeedButton: true,
          onSeed: () async {
            seeded = true;
          },
          onDone: (v) => result = v);

      await tester.tap(find.text('Save Guidelines'));
      await tester.pump();
      // Loading state lives on the action button while seeding.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));

      expect(seeded, isTrue);
      expect(find.text('Community Guidelines'), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('seed failure keeps the dialog open with an inline error',
        (tester) async {
      bool? result;
      await openGuidelines(tester,
          showSeedButton: true,
          onSeed: () async {
            throw Exception('denied');
          },
          onDone: (v) => result = v);

      await tester.tap(find.text('Save Guidelines'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Community Guidelines'), findsOneWidget);
      expect(result, isNull);
    });
  });
}
