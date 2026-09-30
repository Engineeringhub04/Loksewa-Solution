import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/keep_note.dart';
import 'prefs_service.dart';

/// Local-only storage for Keep Notes.
///
/// Notes live in `<app-docs>/keep_notes/notes.json` — a single JSON file on
/// the phone. NOTHING here ever touches Firestore or any server.
///
/// Sync filesystem ops throughout (see AGENTS.md: async dart:io hangs under
/// testWidgets' FakeAsync). The only async step is the one-time directory
/// resolution via [ensureInit]. Tests use [KeepNotesStore.forTest] with a
/// temp dir and skip path_provider entirely.
class KeepNotesStore {
  static const _dirName = 'keep_notes';
  static const _fileName = 'notes.json';
  static const _legacyPrefsKey = 'loksewa:notes';

  Directory? _dir;
  bool _migrated = false;

  KeepNotesStore._();

  /// Production singleton.
  static final KeepNotesStore instance = KeepNotesStore._();

  /// Test-only store rooted at [dir] — no path_provider involved, and the
  /// legacy SharedPreferences migration is disabled (hermetic tests).
  factory KeepNotesStore.forTest(Directory dir) {
    final s = KeepNotesStore._();
    s._dir = dir;
    s._migrated = true;
    return s;
  }

  bool get isReady => _dir != null;

  /// Resolves `<app-docs>/keep_notes` once. Safe to call repeatedly.
  Future<void> ensureInit() async {
    if (_dir != null) return;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$_dirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    _dir = d;
  }

  void _assertReady() {
    if (_dir == null) {
      throw StateError('KeepNotesStore.ensureInit() must complete first');
    }
  }

  File get _file => File('${_dir!.path}/$_fileName');

  /// Loads all notes. Missing/corrupt file → empty list (never throws).
  List<KeepNote> loadAll() {
    _assertReady();
    final f = _file;
    if (!f.existsSync()) return [];
    try {
      final decoded = json.decode(f.readAsStringSync());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(KeepNote.fromJson)
          .where((n) => n.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persists the full note list atomically (single file write).
  void saveAll(List<KeepNote> notes) {
    _assertReady();
    _file.writeAsStringSync(
        json.encode(notes.map((n) => n.toJson()).toList()));
  }

  KeepNote? getById(String id) {
    for (final n in loadAll()) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Inserts or replaces [note] by id, then saves.
  void upsert(KeepNote note) {
    final all = loadAll();
    final i = all.indexWhere((n) => n.id == note.id);
    if (i >= 0) {
      all[i] = note;
    } else {
      all.add(note);
    }
    saveAll(all);
  }

  /// Deletes the note with [id] (no-op when absent).
  void delete(String id) {
    final all = loadAll();
    all.removeWhere((n) => n.id == id);
    saveAll(all);
  }

  /// One-time import of notes saved by the legacy SharedPreferences-based
  /// notes screen (`loksewa:notes`). Runs only in production, only when no
  /// JSON file exists yet. The legacy key is cleared after a successful
  /// import so it never runs twice.
  Future<void> migrateLegacyOnce() async {
    if (_migrated) return;
    _migrated = true;
    await ensureInit();
    if (_file.existsSync()) return;
    try {
      final raw = await PrefsService.getString(_legacyPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! List) return;
      final notes = <KeepNote>[];
      for (final m in decoded.whereType<Map<String, dynamic>>()) {
        final id = '${m['id'] ?? ''}';
        if (id.isEmpty) continue;
        final ts = _asInt(m['updatedAt']);
        notes.add(KeepNote(
          id: id,
          title: '${m['title'] ?? ''}',
          runs: [KeepTextRun(text: '${m['body'] ?? ''}')],
          createdAt: ts,
          updatedAt: ts,
        ));
      }
      if (notes.isNotEmpty) {
        saveAll(notes);
        await PrefsService.remove(_legacyPrefsKey);
      }
    } catch (_) {
      // Legacy data is best-effort; never break the new screen over it.
    }
  }

  static int _asInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}
