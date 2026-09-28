// My report history.
// Mirrors app/report-history/index.tsx: a hero tally (total / open /
// closed), filter tracks derived from each report's source, and cards
// (targetTitle, origin, reason, date, status pill) routing to
// /report-history/:id.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  late final Future<List<Map<String, dynamic>>> _future = _load();
  String _filter = 'all';

  Future<List<Map<String, dynamic>>> _load() async {
    final token = await AuthService.getValidIdToken();
    final uid = AuthService.currentUser?.uid;
    final raw = await FirestoreRest.listDocuments('app_report_history',
        idToken: token, pageSize: 200);
    final mine = raw.where((d) => d['reporterId']?.toString() == uid).toList()
      ..sort((a, b) =>
          _date(b['createdAt']).compareTo(_date(a['createdAt'])));
    return mine;
  }

  DateTime _date(dynamic v) =>
      DateTime.tryParse(v.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);

  String _docId(Map<String, dynamic> d) => d['id']?.toString() ?? '';

  bool _isOpen(Map<String, dynamic> d) =>
      (d['status']?.toString() ?? 'pending') == 'pending';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Report History'),
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
                    child: Text('Could not load reports.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final list = snap.data!;
          final open = list.where(_isOpen).length;
          final closed = list.length - open;
          final sources = [
            'all',
            ...{for (final d in list) d['source']?.toString() ?? 'other'}
          ];
          final visible = _filter == 'all'
              ? list
              : list
                  .where((d) =>
                      (d['source']?.toString() ?? 'other') == _filter)
                  .toList();

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
                    _tally('${list.length}', 'Total'),
                    _tally('$open', 'Open'),
                    _tally('$closed', 'Closed'),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sources.length,
                  itemBuilder: (_, i) {
                    final s = sources[i];
                    final sel = _filter == s;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s),
                        selected: sel,
                        onSelected: (_) =>
                            setState(() => _filter = s),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No reports yet.\nFound a mistake in a question? Report it and help everyone learn.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: visible.length,
                        itemBuilder: (_, i) => _card(visible[i]),
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
    final open = _isOpen(d);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.flag,
            color: open ? Colors.amber.shade700 : Colors.green),
        title: Text(d['targetTitle']?.toString() ?? 'Report',
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
            '${d['source'] ?? ''} · ${d['reason'] ?? ''}\n${_fmtDate(d['createdAt'])}'),
        isThreeLine: true,
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (open ? Colors.amber.shade700 : Colors.green)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(open ? 'OPEN' : 'CLOSED',
              style: TextStyle(
                  color: open ? Colors.amber.shade700 : Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
        onTap: () => context.push('/report-history/${_docId(d)}'),
      ),
    );
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
