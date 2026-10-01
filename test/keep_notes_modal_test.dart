import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:loksewa_solution/models/keep_note.dart';
import 'package:loksewa_solution/screens/learn/notes_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/keep_notes_backup.dart';
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
  // Premium preloading shimmer: the list appears only after the minimum
  // ~1.5s shimmer. Small pumps only (the shimmer's animation is infinite,
  // so never pumpAndSettle).
  for (int i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Stubs the path_provider channels used by export so the backup lands in
/// [dir]. Must be called inside the testWidgets body.
void _stubPathProvider(WidgetTester tester, String dir) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => dir,
  );
}

/// Stubs share_plus so the share sheet "succeeds" instantly.
void _stubShare(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/share'),
    (call) async => 'dev.fluttercommunity.plus/share/success',
  );
}

/// Stubs file_picker's `custom` pick to return the file at [path].
/// FilePicker.platform is `late` and only set by the real plugin registrant,
/// so widget tests must install a fake (extending via the public constructor
/// carries the platform-interface token — no channel mock can work).
class _FakeFilePicker extends FilePicker {
  final FilePickerResult? result;

  _FakeFilePicker(this.result);

  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileLoading,
    bool? allowCompression = true,
    bool allowMultiple = false,
    bool? withData = false,
    int compressionQuality = 30,
    bool? withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

void _stubPicker(String path) {
  FilePicker.platform = _FakeFilePicker(
    FilePickerResult([
      PlatformFile(
          name: 'backup.json',
          path: path,
          size: File(path).lengthSync()),
    ]),
  );
}

void main() {
  setUp(() => AppLanguage.current.value = AppLanguage.english);
  tearDown(() => AppLanguage.current.value = AppLanguage.english);

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

  group('security card uses the approved copy verbatim (EN/NE)', () {
    const enCopy =
        'Keep Notes are saved only on your phone — never in the database. '
        'If you delete the app or move to a new phone, export your notes '
        'first and keep the backup file safe.';
    const neCopy =
        'किप नोट्स तपाईंको फोनमा मात्र सेभ हुन्छ — डाटाबेसमा कहिल्यै हुँदैन। '
        'यदि तपाईंले एप डिलिट गर्नुहुन्छ वा नयाँ फोनमा जानुहुन्छ भने, '
        'पहिले नोटहरू एक्सपोर्ट गरेर ब्याकअप फाइल सुरक्षित राख्नुहोस्।';

    testWidgets('English mode shows the approved English copy',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_sec_en');
      final store = KeepNotesStore.forTest(tmp);
      addTearDown(() => tmp.deleteSync(recursive: true));

      AppLanguage.current.value = AppLanguage.english;
      await _pumpList(tester, store);
      expect(find.text(enCopy), findsOneWidget);
      // No Romanized Nepali anywhere on the screen.
      expect(find.textContaining('hudaina'), findsNothing);
      expect(find.textContaining('haina'), findsNothing);
    });

    testWidgets('Nepali mode shows the approved Nepali copy',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_sec_ne');
      final store = KeepNotesStore.forTest(tmp);
      addTearDown(() => tmp.deleteSync(recursive: true));

      AppLanguage.current.value = AppLanguage.nepali;
      await _pumpList(tester, store);
      expect(find.text(neCopy), findsOneWidget);
    });
  });

  group('EN/NE string selection via AppLanguage.current', () {
    testWidgets('list chrome switches between English and Nepali',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_i18n');
      final store = KeepNotesStore.forTest(tmp);
      store.saveAll([_note('n1', 'My note', pinned: true)]);
      addTearDown(() => tmp.deleteSync(recursive: true));

      AppLanguage.current.value = AppLanguage.english;
      await _pumpList(tester, store);
      expect(find.text('Keep Notes'), findsOneWidget); // header
      expect(find.text('PINNED'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);

      AppLanguage.current.value = AppLanguage.nepali;
      await _pumpList(tester, store);
      expect(find.text('किप नोट्स'), findsOneWidget); // header
      expect(find.text('पिन गरिएका'), findsOneWidget);
      expect(find.text('एक्सपोर्ट'), findsOneWidget);
      expect(find.text('इम्पोर्ट'), findsOneWidget);
      // English chrome is gone.
      expect(find.text('Export'), findsNothing);
      expect(find.text('PINNED'), findsNothing);
    });

    testWidgets('empty state switches between English and Nepali',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_i18n_empty');
      final store = KeepNotesStore.forTest(tmp);
      addTearDown(() => tmp.deleteSync(recursive: true));

      AppLanguage.current.value = AppLanguage.english;
      await _pumpList(tester, store);
      expect(find.text('No notes yet'), findsOneWidget);
      expect(
          find.text('Tap + to create your first note.'), findsOneWidget);

      AppLanguage.current.value = AppLanguage.nepali;
      await _pumpList(tester, store);
      expect(find.text('अहिलेसम्म कुनै नोट छैन'), findsOneWidget);
      expect(find.text('पहिलो नोट बनाउन + थिच्नुहोस्।'), findsOneWidget);
    });

    testWidgets('note-options + delete-confirm modals are localized',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_modal_i18n_mod');
      final store = KeepNotesStore.forTest(tmp);
      // Empty title → the options modal shows the localized 'Note options'.
      store.saveAll([_note('n1', '')]);
      addTearDown(() => tmp.deleteSync(recursive: true));

      AppLanguage.current.value = AppLanguage.nepali;
      await _pumpList(tester, store);
      // The card headline falls back to the body text.
      await tester.longPress(find.text('body'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('नोट विकल्पहरू'), findsOneWidget);
      expect(find.text('माथि पिन गर्नुहोस्'), findsOneWidget);
      expect(find.text('डिलिट गर्नुहोस्'), findsOneWidget);
      expect(find.text('रद्द गर्नुहोस्'), findsOneWidget);
      // The modal's tag pill is localized (the header title matches too).
      expect(
          find.descendant(
              of: find.byType(AppModalShell),
              matching: find.text('किप नोट्स')),
          findsOneWidget);

      await tester.tap(find.text('डिलिट गर्नुहोस्'));
      await tester.pumpAndSettle();

      expect(find.text('नोट डिलिट गर्ने?'), findsOneWidget);
      expect(
          find.text('यो नोट स्थायी रूपमा डिलिट हुनेछ।'), findsOneWidget);
      await tester
          .tap(find.widgetWithText(FilledButton, 'डिलिट गर्नुहोस्'));
      await tester.pumpAndSettle();

      expect(store.getById('n1'), isNull);
      expect(find.text('अहिलेसम्म कुनै नोट छैन'), findsOneWidget);
    });
  });

  group('export feedback is a modal, not a SnackBar', () {
    testWidgets('success shows the Backup-saved modal (English)',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_export_ok');
      final store = KeepNotesStore.forTest(tmp);
      store.saveAll([_note('n1', 'My note')]);
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stubPathProvider(tester, tmp.path);
      _stubShare(tester);

      AppLanguage.current.value = AppLanguage.english;
      await _pumpList(tester, store);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('Backup saved'), findsOneWidget);
      expect(
          find.text(
              'Your backup file was saved to the Downloads folder.'),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // The file really landed on disk (behavior unchanged).
      // (The store's own notes.json lives in the same temp dir — the export
      // file is the dated "Loksewa Solution App Keep Notes ..." one.)
      expect(
          tmp
              .listSync()
              .whereType<File>()
              .where((f) =>
                  f.path.contains('Loksewa Solution App Keep Notes') &&
                  f.path.endsWith('.json'))
              .length,
          1);
    });

    testWidgets('success shows the Backup-saved modal (Nepali)',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_export_ok_ne');
      final store = KeepNotesStore.forTest(tmp);
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stubPathProvider(tester, tmp.path);
      _stubShare(tester);

      AppLanguage.current.value = AppLanguage.nepali;
      await _pumpList(tester, store);
      await tester.tap(find.text('एक्सपोर्ट'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('ब्याकअप सेभ भयो'), findsOneWidget);
      expect(find.text('तपाईंको ब्याकअप फाइल डाउनलोड्स फोल्डरमा सेभ भयो।'),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('failure shows the Export-failed modal (no SnackBar)',
        (tester) async {
      // No path_provider / share stubs → MissingPluginException → failure.
      final tmp =
          Directory.systemTemp.createTempSync('keep_export_fail');
      final store = KeepNotesStore.forTest(tmp);
      addTearDown(() => tmp.deleteSync(recursive: true));

      AppLanguage.current.value = AppLanguage.english;
      await _pumpList(tester, store);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('Export failed'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('import feedback is a modal, not a SnackBar', () {
    testWidgets('invalid file shows the Invalid-backup modal (English)',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_import_bad');
      final store = KeepNotesStore.forTest(tmp);
      final bad = File('${tmp.path}/bad.json')
        ..writeAsStringSync('this is not json {{{');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stubPicker(bad.path);

      AppLanguage.current.value = AppLanguage.english;
      await _pumpList(tester, store);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('Invalid backup file'), findsOneWidget);
      expect(find.text('This file is not a valid Keep Notes backup.'),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // Nothing was imported.
      expect(store.loadAll(), isEmpty);
    });

    testWidgets('invalid file shows the Invalid-backup modal (Nepali)',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_import_bad_ne');
      final store = KeepNotesStore.forTest(tmp);
      final bad = File('${tmp.path}/bad.json')
        ..writeAsStringSync('garbage');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stubPicker(bad.path);

      AppLanguage.current.value = AppLanguage.nepali;
      await _pumpList(tester, store);
      await tester.tap(find.text('इम्पोर्ट'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('अमान्य ब्याकअप फाइल'), findsOneWidget);
      expect(
          find.text('यो मान्य किप नोट्स ब्याकअप होइन।'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('valid import shows the summary modal (English)',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_import_good');
      final store = KeepNotesStore.forTest(tmp);
      store.saveAll([_note('local1', 'Local')]);
      final raw = json.encode(KeepNotesBackup.buildEnvelope([
        _note('local1', 'Local'), // id collides → skipped (local wins)
        _note('imp1', 'Imported'), // new → added
      ]));
      final good = File('${tmp.path}/good.json')..writeAsStringSync(raw);
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stubPicker(good.path);

      AppLanguage.current.value = AppLanguage.english;
      await _pumpList(tester, store);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('Import complete'), findsOneWidget);
      expect(find.text('1 new, 1 skipped.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(store.getById('imp1'), isNotNull);
      expect(store.getById('local1')!.title, 'Local');
    });

    testWidgets('valid import shows the summary modal (Nepali, Devanagari)',
        (tester) async {
      final tmp =
          Directory.systemTemp.createTempSync('keep_import_good_ne');
      final store = KeepNotesStore.forTest(tmp);
      final raw = json.encode(KeepNotesBackup.buildEnvelope([
        _note('imp1', 'Imported'),
      ]));
      final good = File('${tmp.path}/good.json')..writeAsStringSync(raw);
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stubPicker(good.path);

      AppLanguage.current.value = AppLanguage.nepali;
      await _pumpList(tester, store);
      await tester.tap(find.text('इम्पोर्ट'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('इम्पोर्ट पूरा भयो'), findsOneWidget);
      expect(find.text('१ नयाँ, ० स्किप भए।'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(store.getById('imp1'), isNotNull);
    });
  });
}
