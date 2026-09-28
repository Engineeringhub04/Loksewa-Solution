import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Subject theory — mirrors app/subjects/theory.tsx.
/// Shows the theory note; if a PDF is attached, an "Open PDF" button
/// deep-links into the PDF viewer screen.
class SubjectTheoryScreen extends StatefulWidget {
  final String courseId;
  final String subcourseId;
  final String subjectId;
  final String chapterId;
  final String? unitId;
  final String? subjectName;
  final String? chapterName;
  final String? unitName;

  const SubjectTheoryScreen({
    super.key,
    required this.courseId,
    required this.subcourseId,
    required this.subjectId,
    required this.chapterId,
    this.unitId,
    this.subjectName,
    this.chapterName,
    this.unitName,
  });

  @override
  State<SubjectTheoryScreen> createState() => _SubjectTheoryScreenState();
}

class _SubjectTheoryScreenState extends State<SubjectTheoryScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  static String _canon(String v) {
    final parts = v.split('__').where((p) => p.isNotEmpty).toList();
    var id = parts.isNotEmpty ? parts.last : v;
    if (id == 'job-based-knowledge') id = 'technical-subject';
    return id;
  }

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    final subjectId = _canon(widget.subjectId);
    final chapterId = _canon(widget.chapterId);
    final unitId = widget.unitId == null || widget.unitId!.isEmpty
        ? null
        : _canon(widget.unitId!);
    final docId = '${widget.courseId}__${widget.subcourseId}__$subjectId'
        '__${unitId ?? 'no-unit'}__${chapterId}__theory';
    return FirestoreRest.getDocument('app_subject_theory_resources/$docId',
        idToken: token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterName ?? 'Theory'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Failed to load theory.'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final doc = snap.data;
          if (doc == null) {
            return const Center(
                child: Text('No theory material yet.',
                    style: TextStyle(color: Colors.grey)));
          }
          final title = (doc['titleNe'] as String?) ??
              (doc['title'] as String?) ??
              (widget.chapterName ?? 'Theory');
          final theory = (doc['theoryNe'] as String?) ??
              (doc['theory'] as String?) ??
              (doc['content'] as String?) ??
              '';
          final pdfUrl = (doc['pdfUrl'] as String?) ?? '';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (theory.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(theory,
                        style: const TextStyle(fontSize: 15, height: 1.6)),
                  ),
                )
              else
                const Text('No written theory — see the attached PDF.',
                    style: TextStyle(color: Colors.grey)),
              if (pdfUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Open PDF'),
                    onPressed: () {
                      final encoded = Uri.encodeComponent(pdfUrl);
                      context.push(
                          '/pdf/$encoded?title=${Uri.encodeComponent(title)}');
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
