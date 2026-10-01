import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/user/bookmark_remove_dialog.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/trash_icon.dart';

/// FIX 5 — remove-bookmark dialog UX: the delete icon morphs into a spinner
/// while the Firestore delete runs; success closes with the shell's fade;
/// failure morphs back to the trash icon, keeps the dialog open, and toasts.
///
/// Footgun notes (AGENTS.md): never pumpAndSettle while the
/// CircularProgressIndicator spins (infinite animation); settle with many
/// small pumps instead. Tall test surface so the modal lays out like a phone.
void main() {
  Future<void> openDialog(
      WidgetTester tester, Future<void> Function() onRemove) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => AppModalShell.show<bool>(
                  context: context,
                  builder: (_) => BookmarkRemoveDialog(
                    item: const {'title': 'Sample bookmark'},
                    onRemove: onRemove,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.tap(find.text('open'));
    // The shell fades the card in over 200ms — small pumps, never settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Remove this bookmark?'), findsOneWidget);
  }

  group('BookmarkRemoveDialog', () {
    testWidgets('shows the delete icon, title, and bookmark copy',
        (tester) async {
      await openDialog(tester, () async {});
      expect(find.byType(TrashIcon), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sample bookmark'), findsOneWidget);
      expect(find.text('You can save it again any time.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Remove'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    });

    testWidgets(
        'tapping Remove morphs the delete icon into a spinner while '
        'the delete runs, then closes with the fade on success',
        (tester) async {
      final gate = Completer<void>();
      var removed = false;
      await openDialog(tester, () {
        removed = true;
        return gate.future;
      });

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Spinner replaces the trash icon in place; the dialog stays open.
      expect(removed, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TrashIcon), findsNothing);
      expect(find.text('Remove this bookmark?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Removing…'), findsOneWidget);

      // Delete completes → pop(true) through the shell's 200ms fade-out.
      gate.complete();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Remove this bookmark?'), findsNothing);
    });

    testWidgets('on error the spinner morphs back, the dialog stays open, '
        'and an error toast is shown', (tester) async {
      await openDialog(tester, () => Future<void>.error('nope'));

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Error path: the delete future threw, so the spinner morphs back to
      // the trash icon and the dialog STAYS OPEN with an error toast.
      expect(find.text('Remove this bookmark?'), findsOneWidget);
      expect(find.byType(TrashIcon), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Remove'), findsOneWidget);
    });
  });
}
