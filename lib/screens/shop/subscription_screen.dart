// Subscription plans + my request history.
// Mirrors app/subscription/index.tsx: status hero (active plan / free plan),
// my request rows (-> /subscription/:id), plan cards with a feature matrix
// (plan's own features[] against the client feature catalogue), a yearly
// savings percentage computed from the live plans, a "Your Free Services"
// free card, and a "We Accept" payment-methods section.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Client-side feature catalogue (mirrors PLAN_FEATURE_GROUPS in the Expo app).
const List<Map<String, dynamic>> _featureGroups = [
  {
    'title': 'Study',
    'features': [
      {'id': 'mock_tests', 'label': 'Mock Tests'},
      {'id': 'past_questions', 'label': 'Past Questions'},
      {'id': 'theory_desk', 'label': 'Theory Desk'},
      {'id': 'video_classes', 'label': 'Video Classes'},
    ],
  },
  {
    'title': 'Practice',
    'features': [
      {'id': 'daily_quiz', 'label': 'Daily Quiz'},
      {'id': 'gk_bank', 'label': 'GK Question Bank'},
      {'id': 'pm_bank', 'label': 'Public Management Bank'},
      {'id': 'flashcards', 'label': 'Flashcards'},
    ],
  },
  {
    'title': 'Extras',
    'features': [
      {'id': 'answer_checking', 'label': 'Answer Sheet Checking'},
      {'id': 'priority_support', 'label': 'Priority Support'},
      {'id': 'offline_access', 'label': 'Offline Access'},
    ],
  },
];

class _ScreenData {
  final List<Map<String, dynamic>> plans;
  final List<Map<String, dynamic>> myRequests;
  final Map<String, dynamic>? settings;
  _ScreenData(this.plans, this.myRequests, this.settings);
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<_ScreenData> _future = _load();

  Future<_ScreenData> _load() async {
    final token = await AuthService.getValidIdToken();
    final uid = AuthService.currentUser?.uid;
    final plansRaw = await FirestoreRest.listDocuments(
        'app_subscription_plans',
        idToken: token,
        pageSize: 100);
    final plans = plansRaw
        .where((p) => p['isActive'] != false)
        .toList()
      ..sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    final reqRaw = await FirestoreRest.listDocuments('app_subscriptions',
        idToken: token, pageSize: 200);
    final mine = reqRaw.where((r) => r['uid']?.toString() == uid).toList()
      ..sort((a, b) =>
          _date(b['submittedAt']).compareTo(_date(a['submittedAt'])));
    final settings = await FirestoreRest.getDocument(
        'app_subscription_settings/config',
        idToken: token);
    return _ScreenData(plans, mine, settings);
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v.toString()) ?? 0;

  DateTime _date(dynamic v) =>
      DateTime.tryParse(v.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);

  String _docId(Map<String, dynamic> d) => d['id']?.toString() ?? '';

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n % 1 == 0 ? n.toInt().toString() : n.toString();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
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
          const SubpageHeader(title: 'Subscription'),
          Expanded(
            child: FutureBuilder<_ScreenData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const PreloadingWidget(
              tinted: false,
              label: 'Loading Plans...',
            );
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load plans.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final data = snap.data!;
          final active = data.myRequests
              .where((r) => r['status']?.toString() == 'active')
              .toList();
          final current = active.isNotEmpty ? active.first : null;

          // Yearly savings % computed from the live plans.
          String? yearlySave;
          final monthly = data.plans.where(
              (p) => p['billingCycle']?.toString() == 'monthly');
          final yearly = data.plans.where(
              (p) => p['billingCycle']?.toString() == 'yearly');
          if (monthly.isNotEmpty && yearly.isNotEmpty) {
            final m = _num(monthly.first['price']);
            final y = _num(yearly.first['price']);
            if (m > 0 && y > 0 && y < m * 12) {
              yearlySave = 'Save ${(((m * 12 - y) / (m * 12)) * 100).round()}%';
            }
          }

          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _statusHero(current),
                const SizedBox(height: 16),
                if (data.myRequests.isNotEmpty) ...[
                  const Text('My Requests',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...data.myRequests.map(_requestRow),
                  const SizedBox(height: 16),
                ],
                const Text('Plans',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...data.plans.map((p) => _planCard(p, yearlySave)),
                _freeCard(),
                const SizedBox(height: 16),
                _weAccept(),
              ],
            ),
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _statusHero(Map<String, dynamic>? current) {
    final isActive = current != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [Colors.green.shade700, Colors.green.shade500]
              : [AppColors.navy, AppColors.deepNavy],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(isActive ? Icons.workspace_premium : Icons.person_outline,
                color: Colors.white, size: 28),
            const SizedBox(width: 8),
            Text(isActive ? 'Active Plan' : 'Free Plan',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text(
            isActive
                ? '${current['planName'] ?? 'Plan'} · expires ${_fmtDate(current['expiryDate'])}'
                : 'You are on the free plan. Upgrade for full access.',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _requestRow(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? 'pending';
    return Card(
      child: ListTile(
        leading: Icon(Icons.receipt_long, color: _statusColor(status)),
        title: Text(r['planName']?.toString() ?? 'Subscription'),
        subtitle: Text(
            '${_fmtDate(r['submittedAt'])} · Rs. ${_money(r['amount'])}'),
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
        onTap: () => context.push('/subscription/${_docId(r)}'),
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> p, String? yearlySave) {
    final planFeatures =
        (p['features'] as List?)?.map((e) => e.toString()).toSet() ?? {};
    final cycle = p['billingCycle']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(p['name']?.toString() ?? 'Plan',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (cycle == 'yearly' && yearlySave != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(yearlySave,
                        style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Rs. ${_money(p['price'])} · $cycle',
                style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.navy,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ..._featureGroups.map((g) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g['title'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    ...(g['features'] as List).map((f) {
                      final included =
                          planFeatures.contains((f as Map)['id']);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                                included
                                    ? Icons.check_circle
                                    : Icons.cancel_outlined,
                                size: 18,
                                color: included ? Colors.green : Colors.grey),
                            const SizedBox(width: 8),
                            Text(f['label'] as String,
                                style: TextStyle(
                                    color: included
                                        ? Colors.black87
                                        : Colors.black38)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                )),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white),
                onPressed: () => context.push(
                    '/subscription/checkout?planId=${_docId(p)}'),
                child: const Text('Choose Plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _freeCard() => Card(
        color: Colors.blue.shade50,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Free Services',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                  'Daily quiz, selected GK sets and community features stay free forever — no payment needed.'),
            ],
          ),
        ),
      );

  Widget _weAccept() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('We Accept',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: ['eSewa', 'Khalti', 'fonepay']
                .map((m) => Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Text(m,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ))
                .toList(),
          ),
        ],
      );

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
