import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/keep_note.dart';
import '../../services/app_language.dart';
import '../../services/keep_notes_backup.dart';
import '../../services/keep_notes_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/trash_icon.dart';

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
    // Premium preloading shimmer: the note store is local and inits nearly
    // instantly, so without this minimum delay the page would pop in cheaply.
    // The shimmer (PreloadingWidget) stays up for at least ~1.5s.
    await Future.wait([
      () async {
        await _store.ensureInit();
        await _store.migrateLegacyOnce();
      }(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);
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
  //
  // Feedback convention: important feedback goes through the shared global
  // AppModalShell (never a SnackBar) — same modal as the daily-limit popup
  // everywhere in the app; only the content differs.
  // ------------------------------------------------------------------

  /// Converts ASCII digits in [s] to Devanagari digits — Nepali strings
  /// never carry Roman-script numerals.
  static String _dev(String s) {
    const en = '0123456789';
    const ne = '०१२३४५६७८९';
    return s.split('').map((c) {
      final i = en.indexOf(c);
      return i >= 0 ? ne[i] : c;
    }).join();
  }

  /// Info/error feedback in the shared global modal. All text goes through
  /// [AppLanguage.tr] — pure English or pure Devanagari Nepali, never mixed.
  void _showInfoModal({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    if (!mounted) return;
    AppModalShell.show(
      context: context,
      builder: (ctx) => AppModalShell(
        maxWidth: 340,
        tagLabel: AppLanguage.tr('Keep Notes', 'किप नोट्स'),
        onClose: () => Navigator.of(ctx).pop(),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: iconColor,
          ),
          child: Icon(icon, size: 28, color: Colors.white),
        ),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF64748B),
            decoration: TextDecoration.none,
          ),
        ),
        footer: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLanguage.tr('OK', 'ठीक छ')),
          ),
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    final palette = ExpoPalette.of(context);
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
        text: AppLanguage.tr('Keep Notes backup', 'किप नोट्स ब्याकअप'),
      );
      _showInfoModal(
        icon: Icons.check_circle_outline,
        iconColor: palette.primary,
        title: AppLanguage.tr('Backup saved', 'ब्याकअप सेभ भयो'),
        body: AppLanguage.tr(
          'Your backup file was saved to the Downloads folder.',
          'तपाईंको ब्याकअप फाइल डाउनलोड्स फोल्डरमा सेभ भयो।',
        ),
      );
    } catch (_) {
      _showInfoModal(
        icon: Icons.error_outline,
        iconColor: palette.danger,
        title: AppLanguage.tr('Export failed', 'एक्सपोर्ट असफल भयो'),
        body: AppLanguage.tr(
          'The backup file could not be saved. Please try again.',
          'ब्याकअप फाइल सेभ गर्न सकिएन। कृपया पुनः प्रयास गर्नुहोस्।',
        ),
      );
    }
  }

  Future<void> _importBackup() async {
    final palette = ExpoPalette.of(context);

    void invalid() => _showInfoModal(
          icon: Icons.error_outline,
          iconColor: palette.danger,
          title:
              AppLanguage.tr('Invalid backup file', 'अमान्य ब्याकअप फाइल'),
          body: AppLanguage.tr(
            'This file is not a valid Keep Notes backup.',
            'यो मान्य किप नोट्स ब्याकअप होइन।',
          ),
        );

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
        invalid();
        return;
      }

      // Signature + structural validation: forged / wrong / corrupt files
      // are rejected here, before anything touches the note store.
      final imported = KeepNotesBackup.parseAndVerify(raw);
      if (imported == null) {
        invalid();
        return;
      }

      // ID-merge: new ids are added, existing ids keep the LOCAL note.
      final local = _store.loadAll();
      final counts = KeepNotesBackup.merge(local, imported);
      _store.saveAll(local);
      _reload();
      _showInfoModal(
        icon: Icons.check_circle_outline,
        iconColor: palette.primary,
        title: AppLanguage.tr('Import complete', 'इम्पोर्ट पूरा भयो'),
        body: AppLanguage.tr(
          '${counts.added} new, ${counts.skipped} skipped.',
          '${_dev('${counts.added}')} नयाँ, ${_dev('${counts.skipped}')} स्किप भए।',
        ),
      );
    } catch (_) {
      invalid();
    }
  }

  /// Long-press options — global AppModalShell (same modal as the daily-limit
  /// popup everywhere in the app; only the content differs).
  void _showNoteOptions(KeepNote note) {
    AppModalShell.show(
      context: context,
      builder: (ctx) => AppModalShell(
        maxWidth: 340,
        tagLabel: AppLanguage.tr('Keep Notes', 'किप नोट्स'),
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
          note.title.isEmpty
              ? AppLanguage.tr('Note options', 'नोट विकल्पहरू')
              : note.title,
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
              icon: Icon(
                  note.pinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin,
                  size: 22,
                  color: ExpoPalette.of(context).primary),
              label: note.pinned
                  ? AppLanguage.tr('Unpin', 'पिन हटाउनुहोस्')
                  : AppLanguage.tr('Pin to top', 'माथि पिन गर्नुहोस्'),
              onTap: () {
                Navigator.of(ctx).pop();
                _togglePin(note);
              },
            ),
            _modalOption(
              ctx,
              icon: TrashIcon(
                  size: 22, color: ExpoPalette.of(context).danger),
              label: AppLanguage.tr('Delete', 'डिलिट गर्नुहोस्'),
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
          child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
              style: TextStyle(
                  color: ExpoPalette.of(context).primary,
                  decoration: TextDecoration.none)),
        ),
      ),
    );
  }

  Widget _modalOption(
    BuildContext ctx, {
    required Widget icon,
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
              icon,
              const SizedBox(width: 14),
              // Expanded so longer localized labels (e.g. Nepali) wrap
              // instead of overflowing the modal row.
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: danger ? palette.danger : const Color(0xFF0F172A),
                    decoration: TextDecoration.none,
                  ),
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
        tagLabel: AppLanguage.tr('Keep Notes', 'किप नोट्स'),
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
              const TrashIcon(size: 28, color: Colors.white),
        ),
        title: Text(
          AppLanguage.tr('Delete note?', 'नोट डिलिट गर्ने?'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: Text(
          AppLanguage.tr(
            'This note will be permanently deleted.',
            'यो नोट स्थायी रूपमा डिलिट हुनेछ।',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
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
                child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
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
                child: Text(AppLanguage.tr('Delete', 'डिलिट गर्नुहोस्')),
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
          SubpageHeader(
              title: AppLanguage.tr('Keep Notes', 'किप नोट्स')),
          Expanded(
            child: _loading
                ? Center(
                    child: PreloadingWidget(
                        // Theme-coloured page: theme-grey spokes, not white.
                        tinted: false,
                        label: AppLanguage.tr(
                            'Loading notes...', 'नोटहरू लोड हुँदैछन्...')))
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
        tooltip: AppLanguage.tr('New note', 'नयाँ नोट'),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Security notice: Keep Notes data never leaves the phone.
  /// App UI rule: English + Devanagari Nepali only — no Romanized Nepali.
  /// Uses the approved copy verbatim (EN/NE pair).
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
              AppLanguage.tr(
                'Keep Notes are saved only on your phone — never in the database. '
                'If you delete the app or move to a new phone, export your notes '
                'first and keep the backup file safe.',
                'किप नोट्स तपाईंको फोनमा मात्र सेभ हुन्छ — डाटाबेसमा कहिल्यै हुँदैन। '
                'यदि तपाईंले एप डिलिट गर्नुहुन्छ वा नयाँ फोनमा जानुहुन्छ भने, '
                'पहिले नोटहरू एक्सपोर्ट गरेर ब्याकअप फाइल सुरक्षित राख्नुहोस्।',
              ),
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
            label: Text(AppLanguage.tr('Export', 'एक्सपोर्ट')),
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
            label: Text(AppLanguage.tr('Import', 'इम्पोर्ट')),
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
          child: Text(AppLanguage.tr('No notes yet', 'अहिलेसम्म कुनै नोट छैन'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
              AppLanguage.tr('Tap + to create your first note.',
                  'पहिलो नोट बनाउन + थिच्नुहोस्।'),
              style: TextStyle(
                  fontSize: 13, color: palette.textSecondary)),
        ),
      ];
    }
    final pinned = _notes.where((n) => n.pinned).toList();
    final others = _notes.where((n) => !n.pinned).toList();
    final widgets = <Widget>[];
    if (pinned.isNotEmpty) {
      widgets.add(_sectionLabel(
          AppLanguage.tr('Pinned', 'पिन गरिएका'), palette));
      widgets.addAll(pinned.map((n) => _noteCard(n, palette)));
      widgets.add(const SizedBox(height: 8));
    }
    if (others.isNotEmpty) {
      widgets.add(_sectionLabel(
          pinned.isNotEmpty
              ? AppLanguage.tr('Others', 'अन्य')
              : AppLanguage.tr('Notes', 'नोटहरू'),
          palette));
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
    if (body.isEmpty) return AppLanguage.tr('Empty note', 'खाली नोट');
    final firstLine = body.split('\n').first.trim();
    return firstLine.isEmpty
        ? AppLanguage.tr('Empty note', 'खाली नोट')
        : firstLine;
  }

  static String _dateLabel(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      final time = '${_two(d.hour)}:${_two(d.minute)}';
      return AppLanguage.tr('Today $time', 'आज ${_dev(time)}');
    }
    if (diff == 1) return AppLanguage.tr('Yesterday', 'हिजो');
    final date = '${_two(d.day)}/${_two(d.month)}/${d.year}';
    return AppLanguage.tr(date, _dev(date));
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
