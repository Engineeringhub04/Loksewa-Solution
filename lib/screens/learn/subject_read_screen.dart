import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Subject read — mirrors app/subjects/read.tsx.
/// Expandable Q&A list; the correct option is highlighted with the
/// explanation when a question is opened.
class SubjectReadScreen extends StatefulWidget {
  final String courseId;
  final String subcourseId;
  final String subjectId;
  final String chapterId;
  final String? unitId;
  final String? subjectName;
  final String? chapterName;
  final String? unitName;

  const SubjectReadScreen({
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
  State<SubjectReadScreen> createState() => _SubjectReadScreenState();
}

class _SubjectReadScreenState extends State<SubjectReadScreen> {
  late Future<List<_ReadQuestion>> _future;

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

  Future<List<_ReadQuestion>> _load() async {
    final token = await AuthService.getValidIdToken();
    final subjectId = _canon(widget.subjectId);
    final chapterId = _canon(widget.chapterId);
    final unitId = widget.unitId == null || widget.unitId!.isEmpty
        ? null
        : _canon(widget.unitId!);
    final docId = '${widget.courseId}__${widget.subcourseId}__$subjectId'
        '__${unitId ?? 'no-unit'}__${chapterId}__read';
    final doc = await FirestoreRest.getDocument(
        'app_subject_cucqdata_Allmode/$docId',
        idToken: token);
    if (doc == null) return [];
    final raw = doc['questions'];
    if (raw is! List) return [];
    final out = <_ReadQuestion>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map<String, dynamic>) continue;
      if (item['isActive'] == false || doc['isPublished'] == false) continue;
      final options = <String>[];
      final rawOpts = item['options'];
      if (rawOpts is List) {
        for (var j = 0; j < rawOpts.length; j++) {
          final o = rawOpts[j];
          if (o is String) {
            options.add(o);
          } else if (o is Map<String, dynamic>) {
            options.add(
                (o['textEn'] as String?) ?? (o['text'] as String?) ?? '');
          }
        }
      }
      final correctId = (item['correctOptionId'] as String?) ?? '';
      var correctIndex = (item['correctIndex'] as num?)?.toInt() ?? 0;
      if (correctId.isNotEmpty && rawOpts is List) {
        for (var j = 0; j < rawOpts.length; j++) {
          final o = rawOpts[j];
          if (o is Map<String, dynamic> && o['id'] == correctId) {
            correctIndex = j;
            break;
          }
        }
      }
      out.add(_ReadQuestion(
        text: (item['questionNe'] as String?) ??
            (item['questionEn'] as String?) ??
            (item['text'] as String?) ??
            '',
        options: options,
        correctIndex: correctIndex,
        explanation: (item['explanationNe'] as String?) ??
            (item['explanationEn'] as String?) ??
            (item['explanation'] as String?) ??
            '',
        order: (item['order'] as num?)?.toInt() ?? (i + 1),
      ));
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterName ?? 'Read'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<_ReadQuestion>>(
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
                  const Text('Failed to load questions.'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final qs = snap.data ?? [];
          if (qs.isEmpty) {
            return const Center(
                child: Text('No read material yet.',
                    style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: qs.length,
            itemBuilder: (context, i) {
              final q = qs[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  title: Text(
                    'Q${i + 1}. ${q.text}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...List.generate(q.options.length, (oi) {
                            final isCorrect = oi == q.correctIndex;
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isCorrect
                                    ? Colors.green.shade50
                                    : Colors.grey.shade50,
                                border: Border.all(
                                  color: isCorrect
                                      ? Colors.green
                                      : Colors.grey.shade300,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Text(
                                          '${String.fromCharCode(65 + oi)}. ${q.options[oi]}')),
                                  if (isCorrect)
                                    const Icon(Icons.check_circle,
                                        color: Colors.green, size: 20),
                                ],
                              ),
                            );
                          }),
                          if (q.explanation.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.amber.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Explanation',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(q.explanation),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReadQuestion {
  final String text;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final int order;

  const _ReadQuestion({
    required this.text,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.order,
  });
}
