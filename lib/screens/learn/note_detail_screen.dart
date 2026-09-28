import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import '../../widgets/subpage_header.dart';

/// Note editor — mirrors app/notes/[id].tsx.
/// Title, body, color picker, save/delete. Local-first via SharedPreferences.
class NoteDetailScreen extends StatefulWidget {
  final String id;
  const NoteDetailScreen({super.key, required this.id});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  bool get _isNew => widget.id == 'new';

  static const _colorOptions = [
    '#FFFFFF',
    '#FEF3C7',
    '#DBEAFE',
    '#DCFCE7',
    '#FCE7F3',
    '#EDE9FE',
  ];

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _color = _colorOptions[0];
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _allNotes() async {
    final raw = await PrefsService.getString('loksewa:notes');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (json.decode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadExisting() async {
    if (_isNew) {
      setState(() => _loaded = true);
      return;
    }
    final notes = await _allNotes();
    final existing = notes.where((n) => n['id'] == widget.id).toList();
    if (existing.isNotEmpty && mounted) {
      _titleCtrl.text = (existing.first['title'] as String?) ?? '';
      _bodyCtrl.text = (existing.first['body'] as String?) ?? '';
      _color = (existing.first['color'] as String?) ?? _colorOptions[0];
    }
    if (mounted) setState(() => _loaded = true);
  }

  static String _uuid() =>
      '${DateTime.now().millisecondsSinceEpoch}-${(1000 + (DateTime.now().microsecond % 9000))}';

  Future<void> _save() async {
    setState(() => _saving = true);
    final notes = await _allNotes();
    final noteId = _isNew ? _uuid() : widget.id;
    final note = {
      'id': noteId,
      'title': _titleCtrl.text.trim(),
      'body': _bodyCtrl.text.trim(),
      'color': _color,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    final idx = notes.indexWhere((n) => n['id'] == noteId);
    if (idx >= 0) {
      notes[idx] = note;
    } else {
      notes.add(note);
    }
    await PrefsService.setString('loksewa:notes', json.encode(notes));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Note saved')));
    context.pop();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    final notes = await _allNotes();
    notes.removeWhere((n) => n['id'] == widget.id);
    await PrefsService.setString('loksewa:notes', json.encode(notes));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Note deleted')));
    context.pop();
  }

  static Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _parseColor(_color),
      body: Column(
        children: [
          SubpageHeader(title: _isNew ? 'New Note' : 'Edit Note', actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ]),
          Expanded(
            child: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Title',
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      TextField(
                        controller: _bodyCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Write your note...',
                          border: InputBorder.none,
                        ),
                        maxLines: null,
                        minLines: 8,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: _colorOptions.map((c) {
                          final selected = _color == c;
                          return GestureDetector(
                            onTap: () => setState(() => _color = c),
                            child: Container(
                              width: 36,
                              height: 36,
                              margin:
                                  const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: _parseColor(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? AppColors.navy
                                      : Colors.grey.shade400,
                                  width: selected ? 2.5 : 1,
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check,
                                      size: 18,
                                      color: AppColors.navy)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14)),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
