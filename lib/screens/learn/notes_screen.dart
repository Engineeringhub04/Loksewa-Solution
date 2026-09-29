import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Keep Notes list — mirrors app/notes/index.tsx.
/// Personal notes, local-first (SharedPreferences under 'loksewa:notes'),
/// fully usable offline.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadNotes();
  }

  static Future<List<Map<String, dynamic>>> _loadNotes() async {
    final raw = await PrefsService.getString('loksewa:notes');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      final notes = list
          .whereType<Map<String, dynamic>>()
          .toList();
      notes.sort((a, b) =>
          _num(b['updatedAt']).compareTo(_num(a['updatedAt'])));
      return notes;
    } catch (_) {
      return [];
    }
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  static Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.white;
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

  String _dateLabel(dynamic v) {
    final ms = _num(v).toInt();
    if (ms <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(ms)
        .toLocal()
        .toString()
        .split(' ')
        .first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Keep Notes'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const PreloadingWidget(
              tinted: false,
              label: 'Loading Notes...',
            );
          }
          final notes = snap.data ?? [];
          if (notes.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async =>
                  setState(() => _future = _loadNotes()),
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.note_alt_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No notes yet. Tap + to create one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _future = _loadNotes()),
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
              ),
              itemCount: notes.length,
              itemBuilder: (context, i) {
                final n = notes[i];
                return InkWell(
                  onTap: () => context
                      .push('/notes/${n['id']}')
                      .then((_) =>
                          setState(() => _future = _loadNotes())),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _parseColor(n['color'] as String?),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ((n['title'] as String?)?.isNotEmpty == true)
                              ? n['title'] as String
                              : 'Title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text((n['body'] as String?) ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text(_dateLabel(n['updatedAt']),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.navy,
        onPressed: () => context
            .push('/notes/new')
            .then((_) => setState(() => _future = _loadNotes())),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
