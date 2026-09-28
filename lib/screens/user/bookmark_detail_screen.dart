import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';

/// Bookmark detail — mirrors app/bookmarks/[id].tsx.
///
/// Renders the saved snapshot payload: origin card (context icon + source
/// label + saved date), meta rows, the question with its options (correct
/// option revealed via toggle using payload.answerIndex), explanation, and
/// body text. Remove deletes the bookmark document.
class BookmarkDetailScreen extends StatefulWidget {
  final String id;
  const BookmarkDetailScreen({super.key, required this.id});

  @override
  State<BookmarkDetailScreen> createState() => _BookmarkDetailScreenState();
}

class _BookmarkDetailScreenState extends State<BookmarkDetailScreen> {
  late Future<Map<String, dynamic>?> _future;
  bool _revealAnswer = false;
  bool _removing = false;
  Map<String, dynamic>? _loaded;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in.');
    final idToken = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('users/$uid/bookmarks/${widget.id}',
        idToken: idToken);
  }

  Future<void> _remove(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.bookmark_outline),
        title: const Text('Remove this bookmark?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((b['title'] ?? '').toString(),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('You can save it again any time.'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child:
                  const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    setState(() => _removing = true);
    try {
      final idToken = await AuthService.getValidIdToken();
      await FirestoreRest.deleteDocument(
          'users/$uid/bookmarks/${widget.id}',
          idToken: idToken);
      if (mounted) {
        showToast(context, 'Removed from bookmarks', ToastVariant.info);
        context.pop();
      }
    } catch (e) {
      setState(() => _removing = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Remove failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: 'Bookmark', actions: [
          _removing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                )
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _loaded == null ? null : () => _remove(_loaded!),
                ),
        ]),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snap.hasError
                      ? 'Failed to load bookmark:\n${snap.error}'
                      : 'Bookmark not found.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final b = snap.data!;
          _loaded = b;
          final payload = b['payload'];
          final Map<String, dynamic> p =
              payload is Map ? Map<String, dynamic>.from(payload) : {};
          final meta = p['meta'];
          final List metaRows = meta is List ? meta : [];
          final options = p['options'];
          final List optionList = options is List ? options : [];
          final answerIndex = p['answerIndex'] is int ? p['answerIndex'] as int : -1;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _originCard(b),
              const SizedBox(height: 12),
              Text((b['title'] ?? '').toString(),
                  style: Theme.of(context).textTheme.headlineSmall),
              if (metaRows.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (final m in metaRows)
                          if (m is Map)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                        (m['label'] ?? '').toString(),
                                        style: const TextStyle(
                                            color: Colors.grey)),
                                  ),
                                  Expanded(
                                      child: Text(
                                          (m['value'] ?? '').toString())),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
              if ((p['question'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text((p['question'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (var i = 0; i < optionList.length; i++)
                  _optionTile(i, optionList[i].toString(), answerIndex),
                if (answerIndex >= 0) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _revealAnswer = !_revealAnswer),
                      icon: Icon(_revealAnswer
                          ? Icons.visibility_off
                          : Icons.visibility),
                      label: Text(_revealAnswer
                          ? 'Hide answer'
                          : 'Reveal answer'),
                    ),
                  ),
                ],
                if ((p['explanation'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text((p['explanation'] ?? '').toString()),
                  ),
                ],
              ],
              if ((p['body'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text((p['body'] ?? '').toString(),
                    style: const TextStyle(height: 1.5)),
              ],
              if ((b['preview'] ?? '').toString().isNotEmpty &&
                  (p['question'] ?? '').toString().isEmpty) ...[
                const SizedBox(height: 16),
                Text((b['preview'] ?? '').toString(),
                    style: const TextStyle(height: 1.5)),
              ],
            ],
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  static const _ctxColors = <String, Color>{
    'exam': Color(0xFF2563EB),
    'read': Color(0xFF0D9488),
    'practice': Color(0xFFEA580C),
    'daily-test': Color(0xFF7C3AED),
    'qotd': Color(0xFFD97706),
    'quiz': Color(0xFFDB2777),
    'discussion': Color(0xFF4F46E5),
    'article': Color(0xFF059669),
    'note': Color(0xFF475569),
    'chapter': Color(0xFF0891B2),
    'other': Color(0xFF64748B),
  };

  static const _ctxIcons = <String, IconData>{
    'exam': Icons.school_outlined,
    'read': Icons.menu_book_outlined,
    'practice': Icons.fitness_center_outlined,
    'daily-test': Icons.calendar_today_outlined,
    'qotd': Icons.wb_sunny_outlined,
    'quiz': Icons.help_outline,
    'discussion': Icons.forum_outlined,
    'article': Icons.newspaper_outlined,
    'note': Icons.description_outlined,
    'chapter': Icons.layers_outlined,
    'other': Icons.bookmark_outline,
  };

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _savedDate(dynamic raw) {
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is num) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return '';
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  Widget _originCard(Map<String, dynamic> b) {
    final ctx = (b['context'] ?? 'other').toString();
    final color = _ctxColors[ctx] ?? _ctxColors['other']!;
    final icon = _ctxIcons[ctx] ?? _ctxIcons['other']!;
    final label = (b['sourceLabel'] ?? '').toString().isNotEmpty
        ? (b['sourceLabel'] ?? '').toString()
        : (ctx == 'quiz'
            ? 'Quiz'
            : ctx == 'exam'
                ? 'Exam'
                : ctx.replaceAll('-', ' '));
    final date = _savedDate(b['createdAt']);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: color),
                  ),
                  if (date.isNotEmpty)
                    Text(
                      'Saved on $date',
                      style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withValues(alpha: 0.5)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(int index, String text, int answerIndex) {    final isCorrect = _revealAnswer && index == answerIndex;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
            color: isCorrect ? Colors.green : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: isCorrect ? Colors.green.withValues(alpha: 0.08) : null,
      ),
      child: Row(
        children: [
          Text('${String.fromCharCode(65 + index)}. ',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
          if (isCorrect)
            const Icon(Icons.check_circle, color: Colors.green),
        ],
      ),
    );
  }
}
