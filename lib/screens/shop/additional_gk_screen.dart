// General Knowledge feature home.
// Mirrors app/additional-features/gk.tsx (via AdditionalFeatureScreen with
// featureId 'gk'): the feature title, an offline-access button, an overall
// progress bar, and topic cards (icon by keyword, title, question count,
// progress) routing to /additional-features/gk/:topicId.
// Page doc: app_additional_feature_pages/gk__all__all.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

class AdditionalGkScreen extends StatelessWidget {
  const AdditionalGkScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureHome(
        featureId: 'gk',
        title: 'General Knowledge',
        subtitle: 'Nepal & world GK question bank',
      );
}

class _FeatureHome extends StatefulWidget {
  final String featureId;
  final String title;
  final String subtitle;
  const _FeatureHome(
      {required this.featureId, required this.title, required this.subtitle});

  @override
  State<_FeatureHome> createState() => _FeatureHomeState();
}

class _FeatureHomeState extends State<_FeatureHome> {
  late Future<_PageData> _future = _load();

  Future<_PageData> _load() async {
    final token = await AuthService.getValidIdToken();
    final page = await FirestoreRest.getDocument(
        'app_additional_feature_pages/${widget.featureId}__all__all',
        idToken: token);
    final topics =
        ((page?['topics'] as List?)?.cast<Map<String, dynamic>>() ?? [])
            .where((t) => t['isPublished'] != false)
            .toList()
          ..sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    final offline =
        await PrefsService.getBool('af_offline_${widget.featureId}') ?? false;
    double done = 0, total = 0;
    final progress = <String, double>{};
    for (final t in topics) {
      final tid = t['topicId']?.toString() ?? '';
      final p =
          await PrefsService.getString('af_progress_${widget.featureId}_$tid');
      final frac = double.tryParse(p ?? '') ?? 0.0;
      progress[tid] = frac.clamp(0.0, 1.0);
      total += 1;
      done += progress[tid]!;
    }
    return _PageData(topics, offline, progress,
        total == 0 ? 0 : (done / total).clamp(0.0, 1.0));
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v.toString()) ?? 0;

  Future<void> _downloadAll(List<Map<String, dynamic>> topics) async {
    // Offline access: cache every topic's question bank locally via the
    // REST client, then mark the feature complete (mirrors
    // downloadAllAdditionalFeatureQuestionBanks).
    try {
      final token = await AuthService.getValidIdToken();
      for (final t in topics) {
        final tid = t['topicId']?.toString() ?? '';
        await FirestoreRest.getDocument(
            'app_additional_feature_question_banks/${widget.featureId}__all__all__$tid',
            idToken: token);
      }
      await PrefsService.setBool('af_offline_${widget.featureId}', true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('All topics saved for offline use.')));
        setState(() => _future = _load());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  IconData _iconFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('histor')) return Icons.history_edu;
    if (t.contains('geograph') || t.contains('geo')) return Icons.public;
    if (t.contains('politi') || t.contains('constitution')) {
      return Icons.account_balance;
    }
    if (t.contains('econom')) return Icons.trending_up;
    if (t.contains('science')) return Icons.science;
    if (t.contains('sport')) return Icons.sports_soccer;
    if (t.contains('art') || t.contains('culture')) return Icons.palette;
    return Icons.menu_book;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_PageData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load topics.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final d = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.subtitle,
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 14)),
                const SizedBox(height: 12),
                // Offline access
                Card(
                  child: ListTile(
                    leading: Icon(
                        d.offline
                            ? Icons.cloud_done
                            : Icons.cloud_download,
                        color: AppColors.navy),
                    title: Text(d.offline
                        ? 'Available offline'
                        : 'Make available offline'),
                    subtitle: Text(d.offline
                        ? 'All topics are saved on this device.'
                        : 'Download every topic for offline study.'),
                    trailing: d.offline
                        ? null
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.navy,
                                foregroundColor: Colors.white),
                            onPressed: () =>
                                _downloadAll(d.topics),
                            child: const Text('Download'),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                // Overall progress
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Overall progress',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text('${(d.overall * 100).round()}%'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                            value: d.overall,
                            backgroundColor: Colors.black12,
                            color: AppColors.accent),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...d.topics.map((t) {
                  final tid = t['topicId']?.toString() ?? '';
                  final frac = d.progress[tid] ?? 0.0;
                  final titleEn = t['titleEn']?.toString() ?? tid;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.navy.withValues(alpha: 0.1),
                        child: Icon(_iconFor(titleEn),
                            color: AppColors.navy),
                      ),
                      title: Text(titleEn,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${t['questionCount'] ?? 0} questions'),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                              value: frac,
                              backgroundColor: Colors.black12,
                              color: AppColors.accent),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(
                          '/additional-features/${widget.featureId}/$tid'),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PageData {
  final List<Map<String, dynamic>> topics;
  final bool offline;
  final Map<String, double> progress;
  final double overall;
  _PageData(this.topics, this.offline, this.progress, this.overall);
}
