import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/models/keep_note.dart';
import 'package:loksewa_solution/services/keep_notes_store.dart';
import 'package:loksewa_solution/screens/learn/notes_screen.dart';
import 'package:loksewa_solution/widgets/keep_rich_text.dart';

const _bold = KeepTextStyle.bold;
const _italic = KeepTextStyle.italic;

TextEditingValue _v(String text, int offset) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );

void main() {
  group('KeepRichController.toggleStyle', () {
    test('bolds the selected range', () {
      final c = KeepRichController();
      c.value = const TextEditingValue(
        text: 'hello world',
        selection:
            TextSelection(baseOffset: 0, extentOffset: 5),
      );
      c.toggleStyle(_bold);
      expect(c.ranges.length, 1);
      expect(c.ranges.single.start, 0);
      expect(c.ranges.single.end, 5);
      expect(c.ranges.single.styles, {_bold});
    });

    test('toggling twice removes the style', () {
      final c = KeepRichController();
      c.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      c.toggleStyle(_bold);
      c.toggleStyle(_bold);
      expect(c.ranges, isEmpty);
    });

    test('partial coverage expands to the whole selection', () {
      final c = KeepRichController();
      c.setRichText('hello world', [KeepStyleRange(0, 5, {_bold})]);
      c.selection =
          const TextSelection(baseOffset: 3, extentOffset: 8);
      c.toggleStyle(_bold);
      // Not everything had bold ([5,8) was plain) → add everywhere.
      expect(c.ranges.length, 1);
      expect(c.ranges.single.start, 0);
      expect(c.ranges.single.end, 8);
    });

    test('full coverage removes from the whole selection', () {
      final c = KeepRichController();
      c.setRichText('hello', [KeepStyleRange(0, 5, {_bold})]);
      c.selection =
          const TextSelection(baseOffset: 1, extentOffset: 4);
      c.toggleStyle(_bold);
      expect(c.ranges.length, 2);
      expect(c.ranges[0].start, 0);
      expect(c.ranges[0].end, 1);
      expect(c.ranges[1].start, 4);
      expect(c.ranges[1].end, 5);
    });

    test('collapsed cursor toggles typing style', () {
      final c = KeepRichController();
      c.value = _v('', 0);
      c.toggleStyle(_italic);
      expect(c.typingStyles, {_italic});
      c.toggleStyle(_italic);
      expect(c.typingStyles, isEmpty);
    });
  });

  group('KeepRichController range bookkeeping', () {
    test('typing with typing style extends the styled range', () {
      final c = KeepRichController();
      c.value = _v('', 0);
      c.toggleStyle(_bold); // typing style = bold
      c.value = _v('hi', 2);
      expect(c.ranges.length, 1);
      expect(c.ranges.single.start, 0);
      expect(c.ranges.single.end, 2);
      // Keep typing — adjacent bold merges into one range.
      c.value = _v('hi you', 6);
      expect(c.ranges.length, 1);
      expect(c.ranges.single.start, 0);
      expect(c.ranges.single.end, 6);
    });

    test('plain typing does not create ranges', () {
      final c = KeepRichController();
      c.value = _v('hello', 5);
      expect(c.ranges, isEmpty);
      expect(c.typingStyles, isEmpty);
    });

    test('insertion in the middle shifts later ranges', () {
      final c = KeepRichController();
      c.setRichText('helloworld', [KeepStyleRange(5, 10, {_bold})]);
      // Insert a space at offset 5 → 'hello world'.
      c.value = _v('hello world', 6);
      expect(c.ranges.length, 1);
      expect(c.ranges.single.start, 6);
      expect(c.ranges.single.end, 11);
    });

    test('deletion clips overlapping ranges', () {
      final c = KeepRichController();
      c.setRichText('hello world', [KeepStyleRange(0, 5, {_bold})]);
      // Delete ' wor' ([5,9)) → 'hellold'. Bold range untouched.
      c.value = _v('hellold', 5);
      expect(c.ranges.length, 1);
      expect(c.ranges.single.start, 0);
      expect(c.ranges.single.end, 5);
    });

    test('deleting inside a range shrinks it', () {
      final c = KeepRichController();
      c.setRichText('hello', [KeepStyleRange(0, 5, {_bold})]);
      // Delete 'll' ([2,4)) → 'heo'.
      c.value = _v('heo', 2);
      expect(c.ranges.length, 1);
      expect(c.ranges.single.start, 0);
      expect(c.ranges.single.end, 3);
    });

    test('cursor move re-derives typing style from text under it', () {
      final c = KeepRichController();
      c.setRichText('ab', [KeepStyleRange(0, 2, {_bold})]);
      c.selection = const TextSelection.collapsed(offset: 1);
      expect(c.typingStyles, {_bold});
      c.selection = const TextSelection.collapsed(offset: 2);
      expect(c.typingStyles, {_bold});
    });
  });

  group('runs serialization', () {
    test('toRuns/fromRuns round-trip', () {
      final c = KeepRichController();
      c.setRichText('ab cd', [
        KeepStyleRange(0, 2, {_bold}),
        KeepStyleRange(3, 5, {_italic}),
      ]);
      final runs = c.toRuns();
      expect(runs.length, 3);
      expect(runs[0], {'t': 'ab', 'b': true});
      expect(runs[1], {'t': ' '});
      expect(runs[2], {'t': 'cd', 'i': true});

      final back = KeepRichController.fromRuns(runs);
      expect(back.text, 'ab cd');
      expect(back.ranges.length, 2);
      expect(back.ranges[0].start, 0);
      expect(back.ranges[0].end, 2);
      expect(back.ranges[0].styles, {_bold});

      // And through the JSON model layer.
      final note = KeepNote(
          id: 'x',
          runs:
              runs.map((m) => KeepTextRun.fromJson(m)).toList());
      final again = KeepNote.fromJson(note.toJson());
      expect(again.plainBody, 'ab cd');
      expect(again.runs[0].bold, isTrue);
    });

    test('empty body → no runs', () {
      final c = KeepRichController();
      expect(c.toRuns(), isEmpty);
      final back = KeepRichController.fromRuns([]);
      expect(back.text, '');
    });
  });

  group('KeepEditHistory', () {
    KeepEditSnapshot snap(String title, String body) => KeepEditSnapshot(
          title: title,
          bodyText: body,
          ranges: const [],
          titleBase: -1,
          titleExtent: -1,
          bodyBase: -1,
          bodyExtent: -1,
        );

    test('undo/redo walk the stack', () {
      final h = KeepEditHistory();
      expect(h.canUndo, isFalse);
      h.push(snap('a', '1'));
      expect(h.canUndo, isFalse); // only the current state
      h.push(snap('b', '2'));
      expect(h.canUndo, isTrue);
      expect(h.undo()!.title, 'a');
      expect(h.canRedo, isTrue);
      expect(h.canUndo, isFalse);
      expect(h.redo()!.title, 'b');
      expect(h.canRedo, isFalse);
    });

    test('push clears redo and skips duplicates', () {
      final h = KeepEditHistory();
      h.push(snap('a', '1'));
      h.push(snap('b', '2'));
      h.undo();
      expect(h.canRedo, isTrue);
      h.push(snap('c', '3'));
      expect(h.canRedo, isFalse);
      final depth = h.depth;
      h.push(snap('c', '3')); // duplicate
      expect(h.depth, depth);
    });

    test('undo on empty history returns null', () {
      final h = KeepEditHistory();
      expect(h.undo(), isNull);
      expect(h.redo(), isNull);
    });
  });

  group('widget: buildTextSpan', () {
    testWidgets('paints bold ranges, plain elsewhere', (tester) async {
      final c = KeepRichController();
      c.setRichText('hello', [KeepStyleRange(0, 2, {_bold})]);
      TextSpan? span;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          span = c.buildTextSpan(context: ctx, withComposing: false);
          return const SizedBox();
        }),
      ));
      final children = span!.children!;
      expect(children.length, 2);
      final first = children[0] as TextSpan;
      final second = children[1] as TextSpan;
      expect(first.text, 'he');
      expect(first.style!.fontWeight, FontWeight.bold);
      expect(second.text, 'llo');
      expect(second.style!.fontWeight, isNot(FontWeight.bold));
    });
  });

  group('widget: NotesScreen list', () {
    testWidgets('shows Pinned and Others sections', (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_list_test');
      final store = KeepNotesStore.forTest(tmp);
      final now = DateTime.now().millisecondsSinceEpoch;
      store.saveAll([
        KeepNote(
            id: 'p1',
            title: 'Pinned note',
            runs: const [KeepTextRun(text: 'body')],
            pinned: true,
            updatedAt: now),
        KeepNote(
            id: 'o1',
            title: 'Other note',
            runs: const [KeepTextRun(text: 'body')],
            pinned: false,
            updatedAt: now - 1000),
      ]);

      await tester.pumpWidget(
          MaterialApp(home: NotesScreen(store: store)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Keep Notes'), findsOneWidget);
      expect(find.text('PINNED'), findsOneWidget);
      expect(find.text('OTHERS'), findsOneWidget);
      expect(find.text('Pinned note'), findsOneWidget);
      expect(find.text('Other note'), findsOneWidget);
      // Security info card is visible (Devanagari — no Romanized Nepali).
      expect(find.textContaining('डाटा database मा save हुँदैन'),
          findsOneWidget);

      tmp.deleteSync(recursive: true);
    });

    testWidgets('empty state when no notes', (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_list_empty');
      final store = KeepNotesStore.forTest(tmp);
      await tester.pumpWidget(
          MaterialApp(home: NotesScreen(store: store)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No notes yet'), findsOneWidget);
      tmp.deleteSync(recursive: true);
    });
  });
}
