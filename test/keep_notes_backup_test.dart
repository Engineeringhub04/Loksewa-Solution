import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/models/keep_note.dart';
import 'package:loksewa_solution/services/keep_notes_backup.dart';

KeepNote _note(String id, String title) => KeepNote(
      id: id,
      title: title,
      runs: const [
        KeepTextRun(text: 'hello ', bold: true),
        KeepTextRun(text: 'world', italic: true),
      ],
      pinned: id == 'a',
      createdAt: 1000,
      updatedAt: 2000,
    );

void main() {
  group('KeepNotesBackup envelope', () {
    test('sign/verify round-trip preserves notes incl. styles', () {
      final notes = [_note('a', 'First'), _note('b', 'Second')];
      final raw = json.encode(KeepNotesBackup.buildEnvelope(notes));
      final parsed = KeepNotesBackup.parseAndVerify(raw);
      expect(parsed, isNotNull);
      expect(parsed!.length, 2);
      expect(parsed[0].title, 'First');
      expect(parsed[0].pinned, isTrue);
      expect(parsed[0].runs[0].bold, isTrue);
      expect(parsed[0].runs[1].italic, isTrue);
      expect(parsed[1].pinned, isFalse);
    });

    test('tampered signature is rejected', () {
      final env =
          KeepNotesBackup.buildEnvelope([_note('a', 'First')]);
      final sig = env['sig'] as String;
      env['sig'] =
          sig.substring(0, sig.length - 1) + (sig.endsWith('0') ? '1' : '0');
      expect(KeepNotesBackup.parseAndVerify(json.encode(env)), isNull);
    });

    test('tampered notes payload is rejected', () {
      final env =
          KeepNotesBackup.buildEnvelope([_note('a', 'First')]);
      (env['notes'] as List)[0]['title'] = 'HACKED';
      expect(KeepNotesBackup.parseAndVerify(json.encode(env)), isNull);
    });

    test('wrong format / version / shape rejected', () {
      final good =
          KeepNotesBackup.buildEnvelope([_note('a', 'First')]);

      final wrongFormat = Map<String, dynamic>.from(good)
        ..['format'] = 'something-else';
      expect(
          KeepNotesBackup.parseAndVerify(json.encode(wrongFormat)), isNull);

      final wrongVersion = Map<String, dynamic>.from(good)..['version'] = 99;
      expect(
          KeepNotesBackup.parseAndVerify(json.encode(wrongVersion)), isNull);

      final noSig = Map<String, dynamic>.from(good)..remove('sig');
      expect(KeepNotesBackup.parseAndVerify(json.encode(noSig)), isNull);

      final notesNotList = Map<String, dynamic>.from(good)
        ..['notes'] = 'nope';
      expect(
          KeepNotesBackup.parseAndVerify(json.encode(notesNotList)), isNull);

      expect(KeepNotesBackup.parseAndVerify('not json at all'), isNull);
      expect(KeepNotesBackup.parseAndVerify('[1,2,3]'), isNull);
    });

    test('envelope carries format + app name', () {
      final env = KeepNotesBackup.buildEnvelope([]);
      expect(env['format'], 'keep-notes-backup');
      expect(env['app'], 'Loksewa Solution App');
      expect(env['version'], 1);
      expect(env['sig'], isNotEmpty);
    });
  });

  group('KeepNotesBackup.merge (local wins)', () {
    test('new ids added, existing ids skipped, local untouched', () {
      final local = [_note('a', 'Local title')];
      final imported = [_note('a', 'Imported title'), _note('b', 'New')];
      final result = KeepNotesBackup.merge(local, imported);
      expect(result.added, 1);
      expect(result.skipped, 1);
      expect(local.length, 2);
      // Local note was NOT overwritten by the imported twin.
      expect(local.firstWhere((n) => n.id == 'a').title, 'Local title');
      expect(local.any((n) => n.id == 'b'), isTrue);
    });

    test('empty import adds nothing', () {
      final local = [_note('a', 'X')];
      final result = KeepNotesBackup.merge(local, []);
      expect(result.added, 0);
      expect(result.skipped, 0);
    });
  });

  group('exportFileName', () {
    test('contains "Loksewa Solution App" and the date', () {
      final name = KeepNotesBackup.exportFileName(DateTime(2026, 10, 1));
      expect(name.contains('Loksewa Solution App'), isTrue);
      expect(name, 'Loksewa Solution App Keep Notes 2026-10-01.json');
    });
  });
}
