import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/keep_note.dart';
import '../../services/keep_notes_backup.dart';
import '../../services/keep_notes_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Keep Notes list — the Additional Features "Keep Notes" page.
///
/// Pinned notes on top ("Pinned"), everything else under "Others".
/// 100% local: notes live in a JSON file on the phone, never in Firestore —
/// the info card says so. Tap opens the editor, long-press offers pin/delete.
class NotesScreen extends StatefulWidget {
  final KeepNotesStore? store;

  const NotesScreen({super.key, this.store});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  KeepNotesStore get _store => widget.store ?? KeepNotesStore.instance;

  List<KeepNote> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _store.ensureInit();
    await _store.migrateLegacyOnce();
    if (!mounted) return;
    setState(() {
      _notes = KeepNote.sortedForList(_store.loadAll());
      _loading = false;
    });
  }

  void _reload() {
    setState(() {
      _notes = KeepNote.sortedForList(_store.loadAll());
    });
  }

  Future<void> _openEditor(String id) async {
    await context.push('/keep-notes/$id');
    if (mounted) _reload();
  }

  void _togglePin(KeepNote note) {
    note.pinned = !note.pinned;
    note.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _store.upsert(note);
    _reload();
  }

  void _delete(KeepNote note) {
    _store.delete(note.id);
    _reload();
  }

  // ------------------------------------------------------------------
  // Backup: one-tap export (Downloads + share sheet) and signed import.
  // 100% local — no Firestore, no server, ever.
  // ------------------------------------------------------------------

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _exportBackup() async {
    try {
      final notes = _store.loadAll();
      final envelope = KeepNotesBackup.buildEnvelope(notes);
      final bytes = utf8.encode(json.encode(envelope));
      final name = KeepNotesBackup.exportFileName();

      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        dir = null;
      }
      final docs = await getApplicationDocumentsDirectory();
      dir ??= Directory(docs.path);
      final file = File('${dir.path}/$name');
      file.writeAsBytesSync(bytes);

      // Share sheet so the file can travel phone-to-phone
      // (WhatsApp / Telegram / Drive to self, then import on the new phone).
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Keep Notes backup',
      );
      _toast('ब्याकअप तयार भयो');
    } catch (_) {
      _toast('Export failed');
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;

      String? raw;
      if (picked.path != null) {
        raw = File(picked.path!).readAsStringSync();
      } else if (picked.bytes != null) {
        raw = utf8.decode(picked.bytes!);
      }
      if (raw == null) {
        _toast('यो मान्य Keep Notes backup होइन');
        return;
      }

      // Signature + structural validation: forged / wrong / corrupt files
      // are rejected here, before anything touches the note store.
      final imported = KeepNotesBackup.parseAndVerify(raw);
      if (imported == null) {
        _toast('यो मान्य Keep Notes backup होइन');
        return;
      }

      // ID-merge: new ids are added, existing ids keep the LOCAL note.
      final local = _store.loadAll();
      final counts = KeepNotesBackup.merge(local, imported);
      _store.saveAll(local);
      _reload();
      _toast(
          'आयात सम्पन्न: ${counts.added} नयाँ, ${counts.skipped} स्किप');
    } catch (_) {
      _toast('यो मान्य Keep Notes backup होइन');
    }
  }

  /// Long-press options — global AppModalShell (same modal as the daily-limit
  /// popup everywhere in the app; only the content differs).
  void _showNoteOptions(KeepNote note) {
    AppModalShell.show(
      context: context,
      builder: (ctx) => AppModalShell(
        maxWidth: 340,
        tagLabel: 'Keep Notes',
        onClose: () => Navigator.of(ctx).pop(),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: ExpoPalette.of(context).primary,
          ),
          child: const Icon(Icons.push_pin, size: 28, color: Colors.white),
        ),
        title: Text(
          note.title.isEmpty ? 'Note options' : note.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _modalOption(
              ctx,
              icon: note.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin,
              label: note.pinned ? 'Unpin' : 'Pin to top',
              onTap: () {
                Navigator.of(ctx).pop();
                _togglePin(note);
              },
            ),
            _modalOption(
              ctx,
              icon: Icons.delete_outline,
              label: 'Delete',
              danger: true,
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDelete(note);
              },
            ),
          ],
        ),
        footer: TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Cancel',
              style: TextStyle(
                  color: ExpoPalette.of(context).primary,
                  decoration: TextDecoration.none)),
        ),
      ),
    );
  }

  Widget _modalOption(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final palette = ExpoPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: danger ? palette.danger : palette.primary),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: danger ? palette.danger : const Color(0xFF0F172A),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(KeepNote note) {
    AppModalShell.show(
      context: context,
      builder: (ctx) => AppModalShell(
        maxWidth: 340,
        tagLabel: 'Keep Notes',
        onClose: () => Navigator.of(ctx).pop(),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: ExpoPalette.of(context).danger,
          ),
          child:
              const Icon(Icons.delete_outline, size: 28, color: Colors.white),
        ),
        title: const Text(
          'Delete note?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: const Text(
          'This note will be permanently deleted.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF64748B),
            decoration: TextDecoration.none,
          ),
        ),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor:
                        ExpoPalette.of(context).danger),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _delete(note);
                },
                child: const Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          const SubpageHeader(title: 'Keep Notes'),
          Expanded(
            child: _loading
                ? const Center(
                    child: PreloadingWidget(label: 'Loading notes...'))
                : RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      children: [
                        _securityCard(palette),
                        const SizedBox(height: 12),
                        _backupButtons(palette),
                        const SizedBox(height: 16),
                        ..._sections(palette),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor('new'),
        tooltip: 'New note',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Security notice: Keep Notes data never leaves the phone.
  /// App UI rule: English + Devanagari Nepali only — no Romanized Nepali.
  Widget _securityCard(ExpoPalette palette) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: palette.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline,
              size: 20, color: palette.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Keep Notes को डाटा database मा save हुँदैन — '
              'तपाईंको फोनमा मात्र सुरक्षित save हुन्छ।',
              style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// One-tap backup: Export writes a signed, dated JSON file to Downloads
  /// and opens the share sheet; Import reads one back (signature-verified).
  Widget _backupButtons(ExpoPalette palette) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _exportBackup,
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: const Text('Export'),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.primary,
              side: BorderSide(
                  color: palette.primary.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _importBackup,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Import'),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.primary,
              side: BorderSide(
                  color: palette.primary.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _sections(ExpoPalette palette) {
    if (_notes.isEmpty) {
      return [
        const SizedBox(height: 48),
        Icon(Icons.note_alt_outlined,
            size: 56, color: palette.textDisabled),
        const SizedBox(height: 12),
        Center(
          child: Text('No notes yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text('Tap + to create your first note.',
              style: TextStyle(
                  fontSize: 13, color: palette.textSecondary)),
        ),
      ];
    }
    final pinned = _notes.where((n) => n.pinned).toList();
    final others = _notes.where((n) => !n.pinned).toList();
    final widgets = <Widget>[];
    if (pinned.isNotEmpty) {
      widgets.add(_sectionLabel('Pinned', palette));
      widgets.addAll(pinned.map((n) => _noteCard(n, palette)));
      widgets.add(const SizedBox(height: 8));
    }
    if (others.isNotEmpty) {
      widgets.add(_sectionLabel(
          pinned.isNotEmpty ? 'Others' : 'Notes', palette));
      widgets.addAll(others.map((n) => _noteCard(n, palette)));
    }
    return widgets;
  }

  Widget _sectionLabel(String label, ExpoPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: palette.textSecondary),
      ),
    );
  }

  Widget _noteCard(KeepNote note, ExpoPalette palette) {
    final title = note.title.trim();
    final body = note.plainBody.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openEditor(note.id),
          onLongPress: () => _showNoteOptions(note),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.isEmpty ? _previewHeadline(body) : title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: palette.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (note.pinned)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.push_pin,
                            size: 16, color: palette.textSecondary),
                      ),
                  ],
                ),
                if (title.isNotEmpty && body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: palette.textSecondary),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _dateLabel(note.updatedAt),
                  style: TextStyle(
                      fontSize: 11, color: palette.textDisabled),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _previewHeadline(String body) {
    if (body.isEmpty) return 'Empty note';
    final firstLine = body.split('\n').first.trim();
    return firstLine.isEmpty ? 'Empty note' : firstLine;
  }

  static String _dateLabel(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      return 'Today ${_two(d.hour)}:${_two(d.minute)}';
    }
    if (diff == 1) return 'Yesterday';
    return '${_two(d.day)}/${_two(d.month)}/${d.year}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
