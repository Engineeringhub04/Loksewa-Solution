// Exam purchase landing screen.
// Mirrors app/exam-purchase/[id].tsx: fetches one exam set, shows a hero
// (Theory Desk for pdf sets, MCQ otherwise), a details card, a price card,
// and a buy button that routes to the checkout screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

class ExamPurchaseScreen extends StatefulWidget {
  final String id;
  const ExamPurchaseScreen({super.key, required this.id});

  @override
  State<ExamPurchaseScreen> createState() => _ExamPurchaseScreenState();
}

class _ExamPurchaseScreenState extends State<ExamPurchaseScreen> {
  late final Future<Map<String, dynamic>?> _future = _load();

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('app_exam_sets/${widget.id}',
        idToken: token);
  }

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n % 1 == 0 ? n.toInt().toString() : n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buy Exam Set'),
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
                child: Text('Could not load this exam set.\n${snap.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final set = snap.data;
          if (set == null) {
            return const Center(child: Text('Exam set not found.'));
          }
          final isPdf =
              (set['contentType']?.toString() ?? '').toLowerCase() == 'pdf';
          final title = set['title']?.toString() ?? 'Exam Set';
          final price = set['price'];
          final currency = set['currency']?.toString() ?? 'NPR';

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.navy, AppColors.deepNavy],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isPdf ? 'Theory Desk' : 'MCQ',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        isPdf
                            ? 'Written-answer paper checked by a teacher.'
                            : 'Objective practice set with instant results.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                // Details card
                _card([
                  _row('Content type',
                      isPdf ? 'Theory (PDF)' : 'MCQ (Objective)'),
                  _row('Total questions',
                      '${set['totalQuestions'] ?? '—'}'),
                  _row('Duration',
                      set['durationMinutes'] != null
                          ? '${set['durationMinutes']} min'
                          : '—'),
                  _row('Difficulty',
                      set['difficulty']?.toString() ?? '—'),
                  _row('Pass percent',
                      set['passPercent'] != null
                          ? '${set['passPercent']}%'
                          : '—'),
                ]),
                // Price card
                _card([
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Price',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Rs. ${_money(price)}',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Currency: $currency',
                      style: const TextStyle(color: Colors.black54)),
                ]),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => context.push(
                        '/subscription/checkout?examId=${widget.id}'),
                    child: const Text('Buy Now',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
