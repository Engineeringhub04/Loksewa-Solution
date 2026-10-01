import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/keep_note.dart';

/// Signed JSON backup (export / import) for Keep Notes.
///
/// 100% local: the envelope is a plain `.json` file the user carries between
/// phones (share sheet / Downloads). NOTHING here touches Firestore.
///
/// Envelope:
/// ```json
/// {
///   "format": "keep-notes-backup",
///   "app": "Loksewa Solution App",
///   "version": 1,
///   "exportedAt": "<iso8601>",
///   "notes": [ ...KeepNote.toJson()... ],
///   "sig": "<hmac-sha256 hex>"
/// }
/// ```
///
/// `sig` is HMAC-SHA256 over the canonical JSON of the notes array, keyed by
/// a secret compiled into the app. Import recomputes it and rejects the file
/// when it does not match — this stops forged / wrong / corrupt files from
/// being imported. Honest caveat: a compiled-in secret stops casual forgery,
/// not a determined reverse-engineer; proportionate for a notes app.
/// Structural validation (format/version/notes shape) runs too — defense in
/// depth. Parsing JSON never executes code; the signature is about
/// authenticity, not "viruses".
///
/// Pure Dart — no Flutter, no platform channels — so it is fully unit-tested.
class KeepNotesBackup {
  static const formatId = 'keep-notes-backup';
  static const appName = 'Loksewa Solution App';
  static const envelopeVersion = 1;

  /// Compiled-in HMAC secret. Unobtrusive by design (see class docs).
  static const _secret = 'ls-keepnotes-backup-sig-v1-x7q2m9k4';

  KeepNotesBackup._();

  /// Builds the signed export envelope for [notes].
  static Map<String, dynamic> buildEnvelope(List<KeepNote> notes) {
    final notesJson = notes.map((n) => n.toJson()).toList();
    final canonical = json.encode(notesJson);
    return {
      'format': formatId,
      'app': appName,
      'version': envelopeVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'notes': notesJson,
      'sig': _sign(canonical),
    };
  }

  /// HMAC-SHA256 (hex) of [canonicalJson] under the compiled-in secret.
  static String _sign(String canonicalJson) {
    final hmac = Hmac(sha256, utf8.encode(_secret));
    return hmac.convert(utf8.encode(canonicalJson)).toString();
  }

  /// Verifies [raw] (file bytes as string) and returns the notes, or `null`
  /// when the file is not a valid Keep Notes backup (bad JSON, wrong
  /// format/version, malformed notes array, or signature mismatch).
  static List<KeepNote>? parseAndVerify(String raw) {
    late final dynamic decoded;
    try {
      decoded = json.decode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['format'] != formatId) return null;
    if (decoded['version'] != envelopeVersion) return null;
    final rawNotes = decoded['notes'];
    if (rawNotes is! List) return null;
    final sig = decoded['sig'];
    if (sig is! String || sig.isEmpty) return null;

    final notes = rawNotes
        .whereType<Map<String, dynamic>>()
        .map(KeepNote.fromJson)
        .where((n) => n.id.isNotEmpty)
        .toList();

    // Recompute over the canonical re-encoding of the PARSED notes, so the
    // check is self-consistent with [buildEnvelope] (fromJson normalizes).
    final canonical = json.encode(notes.map((n) => n.toJson()).toList());
    if (!_constantTimeEquals(_sign(canonical), sig)) return null;
    return notes;
  }

  /// Compares two hex digests without early exit on first difference.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Merges [imported] into [local] by id. Existing ids are NEVER
  /// overwritten — the local note wins and the imported twin is skipped.
  /// Returns (added, skipped) counts for the summary message.
  static ({int added, int skipped}) merge(
      List<KeepNote> local, List<KeepNote> imported) {
    final ids = local.map((n) => n.id).toSet();
    var added = 0;
    var skipped = 0;
    for (final n in imported) {
      if (n.id.isEmpty || ids.contains(n.id)) {
        skipped++;
      } else {
        local.add(n);
        ids.add(n.id);
        added++;
      }
    }
    return (added: added, skipped: skipped);
  }

  /// Dated export filename — always contains "Loksewa Solution App".
  /// e.g. `Loksewa Solution App Keep Notes 2026-10-01.json`.
  static String exportFileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    final date =
        '${d.year}-${_two(d.month)}-${_two(d.day)}';
    return 'Loksewa Solution App Keep Notes $date.json';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
