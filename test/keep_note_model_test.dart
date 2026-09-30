import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/models/keep_note.dart';

void main() {
  group('KeepTextRun JSON', () {
    test('round-trips flags', () {
      const run =
          KeepTextRun(text: 'hi', bold: true, underline: true);
      final back = KeepTextRun.fromJson(run.toJson());
      expect(back.text, 'hi');
      expect(back.bold, isTrue);
      expect(back.underline, isTrue);
      expect(back.italic, isFalse);
    });

    test('plain run omits flag keys', () {
      const run = KeepTextRun(text: 'plain');
      final j = run.toJson();
      expect(j, {'t': 'plain'});
      final back = KeepTextRun.fromJson(j);
      expect(back.bold, isFalse);
    });
  });

  group('KeepNote', () {
    test('JSON round-trip preserves everything', () {
      final note = KeepNote(
        id: 'n1',
        title: 'Title',
        runs: const [
          KeepTextRun(text: 'hello ', bold: true),
          KeepTextRun(text: 'world', italic: true),
        ],
        pinned: true,
        createdAt: 100,
        updatedAt: 200,
      );
      final back = KeepNote.fromJson(note.toJson());
      expect(back.id, 'n1');
      expect(back.title, 'Title');
      expect(back.runs.length, 2);
      expect(back.runs[0].bold, isTrue);
      expect(back.runs[1].italic, isTrue);
      expect(back.pinned, isTrue);
      expect(back.createdAt, 100);
      expect(back.updatedAt, 200);
    });

    test('plainBody strips styles', () {
      final note = KeepNote(id: 'pb', runs: const [
        KeepTextRun(text: 'a', bold: true),
        KeepTextRun(text: 'b'),
      ]);
      expect(note.plainBody, 'ab');
    });

    test('isEmpty', () {
      expect(KeepNote(id: 'e0').isEmpty, isTrue);
      expect(KeepNote(id: 'e1', title: '  ').isEmpty, isTrue);
      expect(KeepNote(id: 'e2', title: 'x').isEmpty, isFalse);
      expect(
          KeepNote(id: 'e3', runs: const [KeepTextRun(text: 'y')])
              .isEmpty,
          isFalse);
    });

    test('fromJson tolerates missing/garbage fields', () {
      final note = KeepNote.fromJson({'id': 'x'});
      expect(note.title, '');
      expect(note.runs, isEmpty);
      expect(note.pinned, isFalse);
    });
  });

  group('sortedForList', () {
    KeepNote n(String id, bool pinned, int updated) => KeepNote(
        id: id, pinned: pinned, updatedAt: updated, title: id);

    test('pinned first, newest first within each group', () {
      final sorted = KeepNote.sortedForList([
        n('o1', false, 300),
        n('p1', true, 100),
        n('o2', false, 400),
        n('p2', true, 200),
      ]);
      expect(sorted.map((e) => e.id).toList(),
          ['p2', 'p1', 'o2', 'o1']);
    });

    test('empty list', () {
      expect(KeepNote.sortedForList([]), isEmpty);
    });
  });
}
