import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/models/keep_note.dart';
import 'package:loksewa_solution/services/keep_notes_store.dart';

void main() {
  late Directory tmp;
  late KeepNotesStore store;

  setUp(() {
    // Sync temp dir (AGENTS.md: no async dart:io under testWidgets).
    tmp = Directory.systemTemp.createTempSync('keep_notes_test');
    store = KeepNotesStore.forTest(tmp);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  KeepNote sample(String id, {bool pinned = false}) => KeepNote(
        id: id,
        title: 'Title $id',
        runs: [const KeepTextRun(text: 'body', bold: true)],
        pinned: pinned,
        createdAt: 100,
        updatedAt: 200,
      );

  group('KeepNotesStore (local JSON file)', () {
    test('loadAll on missing file returns []', () {
      expect(store.loadAll(), isEmpty);
    });

    test('save/load round-trip preserves notes and styles', () {
      store.saveAll([sample('a', pinned: true), sample('b')]);
      final loaded = store.loadAll();
      expect(loaded.length, 2);
      final a = loaded.firstWhere((n) => n.id == 'a');
      expect(a.title, 'Title a');
      expect(a.pinned, isTrue);
      expect(a.runs.single.bold, isTrue);
      expect(a.plainBody, 'body');
    });

    test('upsert inserts then replaces by id', () {
      store.upsert(sample('a'));
      expect(store.loadAll().length, 1);
      final updated = sample('a', pinned: true)..title = 'New title';
      store.upsert(updated);
      final all = store.loadAll();
      expect(all.length, 1);
      expect(all.single.title, 'New title');
      expect(all.single.pinned, isTrue);
    });

    test('delete removes by id, no-op when absent', () {
      store.saveAll([sample('a'), sample('b')]);
      store.delete('a');
      expect(store.loadAll().map((n) => n.id).toList(), ['b']);
      store.delete('missing'); // must not throw
      expect(store.loadAll().length, 1);
    });

    test('getById finds or returns null', () {
      store.saveAll([sample('a')]);
      expect(store.getById('a')!.title, 'Title a');
      expect(store.getById('zzz'), isNull);
    });

    test('corrupt file returns [] instead of throwing', () {
      File('${tmp.path}/notes.json')
          .writeAsStringSync('not json {{{');
      expect(store.loadAll(), isEmpty);
    });

    test('pin toggle persists across reloads', () {
      store.upsert(sample('a'));
      final note = store.getById('a')!;
      note.pinned = true;
      store.upsert(note);
      // Fresh store instance over the same dir (simulates app restart).
      final again = KeepNotesStore.forTest(tmp);
      expect(again.getById('a')!.pinned, isTrue);
    });

    test('data file lives under the store dir', () {
      store.saveAll([sample('a')]);
      expect(File('${tmp.path}/notes.json').existsSync(), isTrue);
    });
  });
}
