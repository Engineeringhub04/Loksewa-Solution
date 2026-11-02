import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/user/bookmark_remove_dialog.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/popup_action_button.dart';
import 'package:loksewa_solution/widgets/trash_icon.dart';

/// Remove-bookmark dialog UX: while the delete runs, the Remove button's
/// own label is replaced by a white spinner (Logout-popup pattern, the
/// header trash icon stays static, Cancel stays visually unchanged);
/// success closes with the shell's fade; failure restores the Remove
/// label, keeps the dialog open, and toasts.
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
      expect(
          find.widgetWithText(PopupActionButton, 'Remove'), findsOneWidget);
      expect(
          find.widgetWithText(PopupCancelButton, 'Cancel'), findsOneWidget);
    });

    testWidgets(
        'tapping Remove puts the spinner on the Remove button itself '
        'while the delete runs, then closes with the fade on success',
        (tester) async {
      final gate = Completer<void>();
      var removed = false;
      await openDialog(tester, () {
        removed = true;
        return gate.future;
      });

      await tester.tap(find.widgetWithText(PopupActionButton, 'Remove'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Spinner on the action button only; header icon static, Cancel
      // label untouched; the dialog stays open.
      expect(removed, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TrashIcon), findsOneWidget);
      expect(find.text('Remove this bookmark?'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);

      // Delete completes → pop(true) through the shell's 200ms fade-out.
      gate.complete();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Remove this bookmark?'), findsNothing);
    });

    testWidgets('on error the button spinner reverts, the dialog stays '
        'open, and an error toast is shown', (tester) async {
      await openDialog(tester, () => Future<void>.error('nope'));

      await tester.tap(find.widgetWithText(PopupActionButton, 'Remove'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Error path: the delete future threw, so the button spinner
      // reverts to the Remove label and the dialog STAYS OPEN with an
      // error toast.
      expect(find.text('Remove this bookmark?'), findsOneWidget);
      expect(find.byType(TrashIcon), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
          find.widgetWithText(PopupActionButton, 'Remove'), findsOneWidget);
    });
  });
}
