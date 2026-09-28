import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Subject chapters — mirrors app/subjects/chapters/[subjectId].tsx.
/// Summary card + progress ring + chapter cards with P/R/T mode tags;
/// tapping a chapter opens a bottom sheet: Practice / Read / Theory.
class SubjectChaptersScreen extends StatefulWidget {
  final String subjectId;
  const SubjectChaptersScreen({super.key, required this.subjectId});

  @override
  State<SubjectChaptersScreen> createState() => _SubjectChaptersScreenState();
}

class _SubjectChaptersScreenState extends State<SubjectChaptersScreen> {
  late Future<_ChapterData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ChapterData> _load() async {
    final token = await AuthService.getValidIdToken();
    String? courseId;
    String? subcourseId;
    final user = AuthService.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: token);
        courseId = userDoc?['courseId'] as String?;
        subcourseId = userDoc?['subcourseId'] as String?;
      } catch (_) {}
    }

    String subjectName = 'Subject';
    try {
      final subjectDoc = await FirestoreRest.getDocument(
          'app_subjects_details/${widget.subjectId}',
          idToken: token);
      subjectName = (subjectDoc?['nameNe'] as String?) ??
          (subjectDoc?['name'] as String?) ??
          subjectName;
    } catch (_) {}

    final all = await FirestoreRest.listDocuments(
        'app_subjects_chapter_details',
        idToken: token,
        pageSize: 200);
    final chapters = all.where((c) {
      if (c['isPublished'] == false) return false;
      final subj = (c['subjectId'] as String?) ?? '';
      if (_canon(subj) != _canon(widget.subjectId)) return false;
      final unitId = c['unitId'] as String?;
      if (unitId != null && unitId.isNotEmpty) return false;
      final cc = c['courseId'] as String?;
      final sc = c['subcourseId'] as String?;
      if (courseId != null && cc != null && cc != courseId) return false;
      if (subcourseId != null && sc != null && sc != subcourseId) {
        return false;
      }
      return true;
    }).toList();
    chapters.sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));

    return _ChapterData(
      subjectName: subjectName,
      courseId: courseId ?? '',
      subcourseId: subcourseId ?? '',
      chapters: chapters,
    );
  }

  static String _canon(String v) {
    final parts = v.split('__').where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.last : v;
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  void _showModeSheet(Map<String, dynamic> chapter, _ChapterData d) {
    final chapterId = chapter['id'] as String;
    final chapterName =
        (chapter['nameNe'] as String?) ?? (chapter['name'] as String?) ?? '';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chapterName,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Choose a study mode',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              _modeTile(
                context,
                Icons.quiz_outlined,
                'Practice',
                'MCQ questions with explanations',
                Colors.blue,
                () => _goMode('/subjects/practice', chapterId, chapterName, d),
              ),
              _modeTile(
                context,
                Icons.menu_book_outlined,
                'Read',
                'Question & answer format',
                Colors.green,
                () => _goMode('/subjects/read', chapterId, chapterName, d),
              ),
              _modeTile(
                context,
                Icons.description_outlined,
                'Theory',
                'Study notes & reference PDF',
                AppColors.accent,
                () => _goMode('/subjects/theory', chapterId, chapterName, d),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeTile(BuildContext context, IconData icon, String title,
      String subtitle, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  void _goMode(String route, String chapterId, String chapterName,
      _ChapterData d) {
    final params = {
      'courseId': d.courseId,
      'subcourseId': d.subcourseId,
      'subjectId': widget.subjectId,
      'chapterId': chapterId,
      'subjectName': d.subjectName,
      'chapterName': chapterName,
    };
    final qs = params.entries
        .map((e) =>
            '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    context.push('$route?$qs');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chapters'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_ChapterData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Failed to load chapters.'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final d = snap.data!;
          final progress =
              d.chapters.isEmpty ? 0.0 : 0.0; // completed tracking lands later
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: AppColors.navy,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.subjectName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${d.chapters.length} chapters',
                                style: const TextStyle(
                                    color: Colors.white70)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.amber),
                          strokeWidth: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (d.chapters.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: Text('No chapters found.',
                          style: TextStyle(color: Colors.grey))),
                )
              else
                ...d.chapters.map((c) {
                  final name = (c['nameNe'] as String?) ??
                      (c['name'] as String?) ??
                      'Chapter';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.navy.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${_num(c['order']).toInt()}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy),
                        ),
                      ),
                      title: Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Row(
                        children: [
                          _ModeTag(label: 'P', color: Colors.blue),
                          _ModeTag(label: 'R', color: Colors.green),
                          _ModeTag(label: 'T', color: AppColors.accent),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.grey),
                      onTap: () => _showModeSheet(c, d),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _ModeTag extends StatelessWidget {
  final String label;
  final Color color;
  const _ModeTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

class _ChapterData {
  final String subjectName;
  final String courseId;
  final String subcourseId;
  final List<Map<String, dynamic>> chapters;

  const _ChapterData({
    required this.subjectName,
    required this.courseId,
    required this.subcourseId,
    this.chapters = const [],
  });
}
