// Report detail.
// Mirrors app/report-history/[id].tsx: a status hero, the reported-content
// card (target title / preview / author), the report message (reason,
// description, submitted date), reporter details, and the admin responses
// list.
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/subpage_header.dart';

class ReportDetailScreen extends StatefulWidget {
  final String id;
  const ReportDetailScreen({super.key, required this.id});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late final Future<Map<String, dynamic>?> _future = _load();

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('app_report_history/${widget.id}',
        idToken: token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Report Details'),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load report.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final r = snap.data;
          if (r == null) {
            return const Center(child: Text('Report not found.'));
          }
          final open = (r['status']?.toString() ?? 'pending') == 'pending';
          final responses =
              (r['adminResponses'] as List?)?.cast<Map>() ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status hero
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      open ? Colors.amber.shade700 : Colors.green.shade700,
                      open ? Colors.amber.shade500 : Colors.green.shade500,
                    ]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag,
                          color: Colors.white, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(open ? 'OPEN' : 'CLOSED',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text(
                                open
                                    ? 'Our team is reviewing your report.'
                                    : 'This report has been resolved.',
                                style: const TextStyle(
                                    color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Reported content card
                _section('Reported content', [
                  _kv('Title', r['targetTitle']?.toString() ?? '—'),
                  if ((r['targetPreview']?.toString() ?? '').isNotEmpty)
                    _kv('Preview', r['targetPreview'].toString()),
                  if ((r['targetAuthorName']?.toString() ?? '')
                      .isNotEmpty)
                    _kv('Author', r['targetAuthorName'].toString()),
                  if ((r['contextLabel']?.toString() ?? '').isNotEmpty)
                    _kv('Where', r['contextLabel'].toString()),
                  _kv('Source', r['source']?.toString() ?? '—'),
                ]),
                const SizedBox(height: 12),
                // Report message
                _section('Your report', [
                  _kv('Reason', r['reason']?.toString() ?? '—'),
                  if ((r['description']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(r['description'].toString()),
                    ),
                  _kv('Submitted', _fmtDate(r['createdAt'])),
                ]),
                const SizedBox(height: 12),
                // Reporter details
                _section('Reporter', [
                  _kv('Name', r['reporterName']?.toString() ?? '—'),
                  if ((r['reporterEmail']?.toString() ?? '').isNotEmpty)
                    _kv('Email', r['reporterEmail'].toString()),
                ]),
                const SizedBox(height: 12),
                // Admin responses
                _section(
                    'Admin responses (${responses.length})',
                    responses.isEmpty
                        ? [
                            const Text('No responses yet.',
                                style: TextStyle(color: Colors.black54))
                          ]
                        : responses
                            .map((a) => Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          a['message']?.toString() ?? '',
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w500)),
                                      const SizedBox(height: 4),
                                      Text(
                                          _fmtDate(a['createdAt']),
                                          style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ))
                            .toList()),
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

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.black54)),
            const SizedBox(width: 12),
            Flexible(
                child: Text(v,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
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
