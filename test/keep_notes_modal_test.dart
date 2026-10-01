import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/models/keep_note.dart';
import 'package:loksewa_solution/screens/learn/notes_screen.dart';
import 'package:loksewa_solution/services/keep_notes_store.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

KeepNote _note(String id, String title, {bool pinned = false}) => KeepNote(
      id: id,
      title: title,
      runs: const [KeepTextRun(text: 'body')],
      pinned: pinned,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

Future<void> _pumpList(WidgetTester tester, KeepNotesStore store) async {
  await tester.pumpWidget(MaterialApp(home: NotesScreen(store: store)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('Keep Notes long-press options use the global modal', () {
    testWidgets('long-press opens AppModalShell (not AlertDialog)',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('keep_modal_test');
      final store = KeepNotesStore.forTest(tmp);
      store.saveAll([_note('n1', 'My note')]);
      addTearDown(() => tmp.deleteSync(recursive: true));

      await _pumpList(tester, store);
      await tester.longPress(find.text('My note'));
      await tester.pumpAndSettle();

      // Global modal is used; the old AlertDialog is gone.
      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Pin to top'), findsOneWidget);
      expect(find.text('Delete'), findsWidgets);
    });

    testWidgets('Pin option pins the note and closes the modal',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_pin');
      final store = KeepNotesStore.forTest(tmp);
      store.saveAll([_note('n1', 'My note')]);
      addTearDown(() => tmp.deleteSync(recursive: true));

      await _pumpList(tester, store);
      await tester.longPress(find.text('My note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin to top'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsNothing);
      expect(find.text('PINNED'), findsOneWidget);
      expect(store.getById('n1')!.pinned, isTrue);
    });

    testWidgets('Delete asks for confirm in AppModalShell, then deletes',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_del');
      final store = KeepNotesStore.forTest(tmp);
      store.saveAll([_note('n1', 'My note')]);
      addTearDown(() => tmp.deleteSync(recursive: true));

      await _pumpList(tester, store);
      await tester.longPress(find.text('My note'));
      await tester.pumpAndSettle();
      // Tap the Delete option row (first of the two Delete texts is the row).
      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('Delete note?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsNothing);
      expect(store.getById('n1'), isNull);
      expect(find.text('No notes yet'), findsOneWidget);
    });

    testWidgets('security card is Devanagari (no Romanized Nepali)',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_lang');
      final store = KeepNotesStore.forTest(tmp);
      addTearDown(() => tmp.deleteSync(recursive: true));

      await _pumpList(tester, store);
      expect(find.textContaining('डाटा database मा save हुँदैन'),
          findsOneWidget);
      expect(find.textContaining('hudaina'), findsNothing);
    });

    testWidgets('Export and Import buttons are present', (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_btns');
      final store = KeepNotesStore.forTest(tmp);
      addTearDown(() => tmp.deleteSync(recursive: true));

      await _pumpList(tester, store);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });
  });
}
