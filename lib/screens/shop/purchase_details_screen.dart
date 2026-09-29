// My purchases (exam + content).
// Mirrors app/purchase-details/index.tsx: a hero tally (total / pending /
// active), filter tracks (all / exam / content), and cards that route to
// /subscription/exam-purchase/:id and /purchase-details/content/:id.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

class _Purchases {
  final List<Map<String, dynamic>> exam;
  final List<Map<String, dynamic>> content;
  _Purchases(this.exam, this.content);
}

class PurchaseDetailsScreen extends StatefulWidget {
  const PurchaseDetailsScreen({super.key});

  @override
  State<PurchaseDetailsScreen> createState() => _PurchaseDetailsScreenState();
}

class _PurchaseDetailsScreenState extends State<PurchaseDetailsScreen> {
  late final Future<_Purchases> _future = _load();
  String _filter = 'all'; // all | exam | content

  Future<_Purchases> _load() async {
    final token = await AuthService.getValidIdToken();
    final uid = AuthService.currentUser?.uid;
    final examRaw = await FirestoreRest.listDocuments('app_exam_purchases',
        idToken: token, pageSize: 200);
    final contentRaw = await FirestoreRest.listDocuments(
        'app_content_purchases',
        idToken: token,
        pageSize: 200);
    List<Map<String, dynamic>> byUid(List<Map<String, dynamic>> l) =>
        (l.where((d) => d['uid']?.toString() == uid).toList()
          ..sort((a, b) => _date(b['submittedAt'])
              .compareTo(_date(a['submittedAt']))));
    return _Purchases(byUid(examRaw), byUid(contentRaw));
  }

  DateTime _date(dynamic v) =>
      DateTime.tryParse(v.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);

  String _docId(Map<String, dynamic> d) => d['id']?.toString() ?? '';

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.amber.shade700;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'My Purchases'),
          Expanded(
            child: FutureBuilder<_Purchases>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const PreloadingWidget(
              tinted: false,
              label: 'Loading Details...',
            );
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load purchases.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final p = snap.data!;
          final all = [...p.exam, ...p.content];
          final pending =
              all.where((d) => d['status']?.toString() == 'pending').length;
          final active = all
              .where((d) =>
                  d['status']?.toString() == 'active' ||
                  d['status']?.toString() == 'approved')
              .length;

          final visible = _filter == 'exam'
              ? p.exam
              : _filter == 'content'
                  ? p.content
                  : ([...all]..sort((a, b) => _date(b['submittedAt'])
                      .compareTo(_date(a['submittedAt']))));

          return Column(
            children: [
              // Hero tally
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AppColors.navy,
                    AppColors.deepNavy,
                  ]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _tally('${all.length}', 'Total'),
                    _tally('$pending', 'Pending'),
                    _tally('$active', 'Active'),
                  ],
                ),
              ),
              // Filter tracks
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'exam', label: Text('Exam')),
                    ButtonSegment(value: 'content', label: Text('Content')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) =>
                      setState(() => _filter = s.first),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                            'No purchases yet.\nBuy an exam set or content to see it here.',
                            textAlign: TextAlign.center))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final d = visible[i];
                          final isExam = _filter == 'content'
                              ? false
                              : _filter == 'exam'
                                  ? true
                                  : p.exam.contains(d);
                          return _card(d, isExam);
                        },
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

  Widget _card(Map<String, dynamic> d, bool isExam) {
    final status = d['status']?.toString() ?? 'pending';
    final title = isExam
        ? (d['examTitle']?.toString() ?? 'Exam')
        : (d['contentTitle']?.toString() ?? 'Content');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(isExam ? Icons.school : Icons.menu_book,
            color: AppColors.navy),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${isExam ? d['examContentType'] ?? '' : d['contentType'] ?? ''} · Rs. ${_money(d['amount'])}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(status).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(status.toUpperCase(),
              style: TextStyle(
                  color: _statusColor(status),
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
        onTap: () => context.push(isExam
            ? '/subscription/exam-purchase/${_docId(d)}'
            : '/purchase-details/content/${_docId(d)}'),
      ),
    );
  }

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n % 1 == 0 ? n.toInt().toString() : n.toString();
  }
}
