// Exam answer detail.
// Mirrors app/exam-answer/[id].tsx. When reviewed: a gradient result card
// (score / full marks, Passed / Not Passed), the teacher's note card,
// "Download Checked PDF" and "View Submitted PDF" buttons. When pending: a
// muted preview with a Pending Review badge and — inside the 1-hour edit
// window — an Edit / Re-upload button routing to
// /exam-answer/upload?editId=<id>.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

const int _answerEditWindowMs = 60 * 60 * 1000;

class ExamAnswerScreen extends StatefulWidget {
  final String id;
  const ExamAnswerScreen({super.key, required this.id});

  @override
  State<ExamAnswerScreen> createState() => _ExamAnswerScreenState();
}

class _ExamAnswerScreenState extends State<ExamAnswerScreen> {
  late final Future<Map<String, dynamic>?> _future = _load();

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('app_exam_answers/${widget.id}',
        idToken: token);
  }

  bool _canEdit(Map<String, dynamic> a) {
    if (a['status']?.toString() != 'pending') return false;
    final created = DateTime.tryParse(a['createdAt']?.toString() ?? '');
    if (created == null) return false;
    return DateTime.now().difference(created).inMilliseconds <
        _answerEditWindowMs;
  }

  void _showPdfDialog(String title, String url) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(url.isEmpty ? 'No file attached.' : url),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Answer Sheet'),
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
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load answer.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final a = snap.data;
          if (a == null) {
            return const Center(child: Text('Answer not found.'));
          }
          final reviewed = a['status']?.toString() == 'reviewed';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Text(a['examSetTitle']?.toString() ?? 'Exam',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                if ((a['sectionName']?.toString() ?? '').isNotEmpty)
                  Text(a['sectionName'].toString(),
                      style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 16),
                if (reviewed) ...[
                  _resultCard(a),
                  const SizedBox(height: 16),
                  if ((a['reviewNote']?.toString() ?? '').isNotEmpty)
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.note_alt,
                                    color: AppColors.navy),
                                SizedBox(width: 8),
                                Text("Teacher's Note",
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(a['reviewNote'].toString()),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.download),
                    label: const Text('Download Checked PDF'),
                    onPressed: () => _showPdfDialog('Checked PDF',
                        a['checkedPdfUrl']?.toString() ?? ''),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('View Submitted PDF'),
                    onPressed: () => _showPdfDialog('Submitted PDF',
                        a['pdfUrl']?.toString() ?? ''),
                  ),
                ] else ...[
                  // Pending: muted preview
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.hourglass_top,
                            size: 48, color: Colors.black45),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(20)),
                          child: const Text('PENDING REVIEW',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your answer sheet is with the teacher. '
                          'Marks and feedback will appear here once reviewed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('View Submitted PDF'),
                    onPressed: () => _showPdfDialog('Submitted PDF',
                        a['pdfUrl']?.toString() ?? ''),
                  ),
                  if (_canEdit(a)) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit / Re-upload Answer'),
                      onPressed: () => context.push(
                          '/exam-answer/upload?editId=${widget.id}'),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'You can edit your submission within 1 hour of uploading.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                _metaCard(a),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> a) {
    final passed = a['passed'] == true;
    final score = a['score'];
    final full = a['fullMarks'];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          passed ? Colors.green.shade700 : Colors.red.shade700,
          passed ? Colors.green.shade500 : Colors.red.shade400,
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(passed ? 'PASSED' : 'NOT PASSED',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            '${_num(score)} / ${_num(full)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold),
          ),
          const Text('Score',
              style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _metaCard(Map<String, dynamic> a) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Submission info',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _kv('Student', a['studentName']?.toString() ?? '—'),
              _kv('Status', a['status']?.toString() ?? '—'),
              _kv('Submitted', _fmtDate(a['createdAt'])),
              if ((a['message']?.toString() ?? '').isNotEmpty)
                _kv('Message', a['message'].toString()),
            ],
          ),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.black54)),
            Flexible(
                child: Text(v,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  String _num(dynamic v) {
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n % 1 == 0 ? n.toInt().toString() : n.toString();
  }

  String _fmtDate(dynamic v) {
    final dt = v is DateTime ? v : DateTime.tryParse(v.toString());
    if (dt == null) return '—';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }
}
