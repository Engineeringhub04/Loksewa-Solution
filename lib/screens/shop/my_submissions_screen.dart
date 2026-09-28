// My answer-sheet submissions.
// Mirrors app/exam-answer/my-submissions.tsx: a hero tally
// (submitted / pending / passed) and cards with status + score pills that
// route to /exam-answer/:id.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

class MySubmissionsScreen extends StatefulWidget {
  const MySubmissionsScreen({super.key});

  @override
  State<MySubmissionsScreen> createState() => _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends State<MySubmissionsScreen> {
  late final Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final token = await AuthService.getValidIdToken();
    final uid = AuthService.currentUser?.uid;
    final raw = await FirestoreRest.listDocuments('app_exam_answers',
        idToken: token, pageSize: 200);
    final mine =
        raw.where((d) => d['uid']?.toString() == uid).toList()
          ..sort((a, b) => _date(b['createdAt'])
              .compareTo(_date(a['createdAt'])));
    return mine;
  }

  DateTime _date(dynamic v) =>
      DateTime.tryParse(v.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);

  String _docId(Map<String, dynamic> d) => d['id']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'My Submissions'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load submissions.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final list = snap.data!;
          final pending = list
              .where((d) => d['status']?.toString() == 'pending')
              .length;
          final passed =
              list.where((d) => d['passed'] == true).length;

          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No submissions yet.\nUpload your first answer sheet from the Theory Desk.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    AppColors.navy,
                    AppColors.deepNavy,
                  ]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _tally('${list.length}', 'Submitted'),
                    _tally('$pending', 'Pending'),
                    _tally('$passed', 'Passed'),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _card(list[i]),
                ),
              ),
            ],
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _tally(String n, String label) => Column(
        children: [
          Text(n,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      );

  Widget _card(Map<String, dynamic> d) {
    final reviewed = d['status']?.toString() == 'reviewed';
    final passed = d['passed'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
            reviewed ? Icons.fact_check : Icons.hourglass_top,
            color: reviewed
                ? (passed ? Colors.green : Colors.red)
                : Colors.amber.shade700),
        title: Text(d['examSetTitle']?.toString() ?? 'Exam',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(_fmtDate(d['createdAt'])),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (reviewed
                    ? (passed ? Colors.green : Colors.red)
                    : Colors.amber.shade700)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            reviewed
                ? '${_num(d['score'])}/${_num(d['fullMarks'])}'
                : 'PENDING',
            style: TextStyle(
                color: reviewed
                    ? (passed ? Colors.green : Colors.red)
                    : Colors.amber.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 12),
          ),
        ),
        onTap: () => context.push('/exam-answer/${_docId(d)}'),
      ),
    );
  }

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
