import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Downloads — mirrors app/downloads.tsx.
///
/// The Expo app keeps downloads as a local list (`loksewa:downloads` AsyncStorage
/// key); this screen keeps the same local list in SharedPreferences.
/// Item shape: {id, title, type: pdf|note|other, sizeBytes, downloadedAt (ms)}.
/// - storage strip: "Storage used: {bytes}" row + "Clear All" text button
/// - remove is direct (trash icon, no confirm) + "Download removed" toast
/// - clear-all behind a confirm dialog: "Remove all downloaded files?"
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _key = 'loksewa:downloads';
  bool _loading = true;
  bool _error = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final raw = await PrefsService.getString(_key);
      final List list = raw == null || raw.isEmpty ? [] : json.decode(raw);
      _items = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      _error = true;
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() async {
    await PrefsService.setString(_key, json.encode(_items));
  }

  Future<void> _remove(String id) async {
    setState(() => _items.removeWhere((e) => (e['id'] ?? '').toString() == id));
    await _persist();
    if (mounted) {
      showToast(context, 'Download removed', ToastVariant.success);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove all downloaded files?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Clear All',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _items.clear());
    await _persist();
  }

  int get _totalBytes => _items.fold<int>(
      0,
      (sum, e) =>
          sum + ((e['sizeBytes'] is num) ? (e['sizeBytes'] as num).toInt() : 0));

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _dateStr(dynamic raw) {
    final ms = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    if (ms == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'pdf':
        return Icons.description_outlined;
      case 'note':
        return Icons.edit_outlined;
      default:
        return Icons.inbox_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Downloads'),
          Expanded(
            child: _loading
                ? const PreloadingWidget(
                    tinted: false,
                    label: 'Loading Downloads...',
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Storage used: ${_formatBytes(_totalBytes)}',
                              style: TextStyle(
                                  color: onSurface.withValues(alpha: 0.65),
                                  fontSize: 14),
                            ),
                            if (_items.isNotEmpty)
                              TextButton(
                                onPressed: _clearAll,
                                child: const Text('Clear All'),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _error
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                        'Could not load downloads.'),
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                        onPressed: _load,
                                        child: const Text('Retry')),
                                  ],
                                ),
                              )
                            : _items.isEmpty
                                ? Center(
                                    child: Text(
                                      'No downloads yet',
                                      style: TextStyle(
                                          color: onSurface.withValues(
                                              alpha: 0.55),
                                          fontSize: 15),
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: _load,
                                    child: ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                      itemCount: _items.length,
                                      itemBuilder: (context, i) {
                                        final item = _items[i];
                                        final id = (item['id'] ?? '')
                                            .toString();
                                        final type = (item['type'] ?? 'other')
                                            .toString();
                                        final size = (item['sizeBytes']
                                                    is num)
                                            ? (item['sizeBytes'] as num)
                                                .toInt()
                                            : 0;
                                        return Card(
                                          margin: const EdgeInsets.only(
                                              bottom: 8),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                Icon(_iconFor(type),
                                                    size: 24,
                                                    color: AppColors.navy),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        (item['title'] ?? '')
                                                            .toString(),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w500),
                                                      ),
                                                      Text(
                                                        '${_formatBytes(size)} · ${_dateStr(item['downloadedAt'])}',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: onSurface
                                                                .withValues(
                                                                    alpha:
                                                                        0.55)),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons
                                                      .delete_outline,
                                                      size: 20),
                                                  onPressed: () =>
                                                      _remove(id),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
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
