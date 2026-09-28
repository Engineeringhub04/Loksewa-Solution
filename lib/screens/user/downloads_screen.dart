import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Downloads — mirrors app/downloads.tsx.
///
/// The Expo app keeps downloads as a local list via `loadDownloads()`
/// (AsyncStorage key `loksewa:downloads`). This screen keeps the same local
/// list in SharedPreferences through PrefsService: storage-used strip,
/// per-item remove, and clear-all with confirmation. Item shape:
/// {id, title, type: pdf|note|other, sizeBytes, downloadedAt}.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _key = 'loksewa:downloads';
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await PrefsService.getString(_key);
      final List list = raw == null || raw.isEmpty ? [] : json.decode(raw);
      _items = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      _items = [];
    }
    setState(() => _loading = false);
  }

  Future<void> _persist() async {
    await PrefsService.setString(_key, json.encode(_items));
  }

  Future<void> _removeAt(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text('Remove "${(_items[index]['title'] ?? '').toString()}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _items.removeAt(index));
    await _persist();
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear all downloads?'),
        content: const Text(
            'This removes the download list from this device. Files already saved stay on the device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Clear all')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _items.clear());
    await _persist();
  }

  int get _totalBytes => _items.fold<int>(
      0, (sum, e) => sum + ((e['sizeBytes'] is int) ? e['sizeBytes'] as int : 0));

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'note':
        return Icons.note;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: 'Downloads', actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ]),
          Expanded(
            child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.storage, color: AppColors.navy),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_items.length} items',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Storage used: ${_formatBytes(_totalBytes)}',
                              style:
                                  const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No downloads yet.\nDownloaded PDFs and notes will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final item = _items[i];
                            final type =
                                (item['type'] ?? 'other').toString();
                            final downloadedAt =
                                (item['downloadedAt'] ?? '').toString();
                            return Card(
                              child: ListTile(
                                leading: Icon(_iconFor(type),
                                    color: AppColors.navy),
                                title: Text(
                                    (item['title'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${type.toUpperCase()} · ${_formatBytes(item['sizeBytes'] is int ? item['sizeBytes'] as int : 0)}'
                                    '${downloadedAt.isNotEmpty ? ' · $downloadedAt' : ''}'),
                                trailing: IconButton(
                                  icon:
                                      const Icon(Icons.delete_outline),
                                  onPressed: () => _removeAt(i),
                                ),
                              ),
                            );
                          },
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
