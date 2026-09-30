import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/keep_note.dart';
import '../../services/keep_notes_store.dart';
import '../../theme/app_theme.dart';
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

  void _showNoteOptions(KeepNote note) {
    final palette = ExpoPalette.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          note.title.isEmpty ? 'Note options' : note.title,
          style: TextStyle(
              fontWeight: FontWeight.bold, color: palette.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                  note.pinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin,
                  color: palette.primary),
              title: Text(note.pinned ? 'Unpin' : 'Pin to top',
                  style: TextStyle(color: palette.textPrimary)),
              onTap: () {
                Navigator.of(ctx).pop();
                _togglePin(note);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: palette.danger),
              title: Text('Delete',
                  style: TextStyle(color: palette.danger)),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDelete(note);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(KeepNote note) {
    final palette = ExpoPalette.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Delete note?',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: palette.textPrimary)),
        content: Text('This note will be permanently deleted.',
            style: TextStyle(color: palette.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                Text('Cancel', style: TextStyle(color: palette.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _delete(note);
            },
            child:
                Text('Delete', style: TextStyle(color: palette.danger)),
          ),
        ],
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
              'Keep Notes ko data database ma save hudaina — '
              'tapai ko phone ma matra surakshit save hunxa.',
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
