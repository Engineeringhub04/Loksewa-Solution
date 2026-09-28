// Content purchase request detail.
// Mirrors app/purchase-details/content/[id].tsx: same pattern as the exam
// purchase detail (status box, 30-minute edit window, admin message, details
// card, screenshot preview) with content-specific fields (contentType,
// courseId/subjectId, unitId).
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

const int _editWindowMs = 30 * 60 * 1000;

class ContentPurchaseDetailScreen extends StatefulWidget {
  final String id;
  const ContentPurchaseDetailScreen({super.key, required this.id});

  @override
  State<ContentPurchaseDetailScreen> createState() =>
      _ContentPurchaseDetailScreenState();
}

class _ContentPurchaseDetailScreenState
    extends State<ContentPurchaseDetailScreen> {
  late Future<Map<String, dynamic>?> _future = _load();
  final _refCtrl = TextEditingController();
  final _shotCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('app_content_purchases/${widget.id}',
        idToken: token);
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _shotCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  bool _canEdit(Map<String, dynamic> r) {
    if (r['status']?.toString() != 'pending') return false;
    final submitted = DateTime.tryParse(r['submittedAt']?.toString() ?? '');
    if (submitted == null) return false;
    return DateTime.now().difference(submitted).inMilliseconds < _editWindowMs;
  }

  Future<void> _saveEdits() async {
    setState(() => _saving = true);
    try {
      final token = await AuthService.getValidIdToken();
      await FirestoreRest.setDocument(
        'app_content_purchases/${widget.id}',
        {
          'transactionRef': _refCtrl.text.trim(),
          'screenshotUrl': _shotCtrl.text.trim(),
          'customerMessage':
              _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        merge: true,
        idToken: token,
      );
      setState(() {
        _editing = false;
        _future = _load();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Details updated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
          const SubpageHeader(title: 'Content Purchase'),
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
                    child: Text('Could not load purchase.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final r = snap.data;
          if (r == null) {
            return const Center(child: Text('Purchase not found.'));
          }
          final status = r['status']?.toString() ?? 'pending';
          final color = _statusColor(status);
          final editable = _canEdit(r);
          if (!_editing) {
            _refCtrl.text = r['transactionRef']?.toString() ?? '';
            _shotCtrl.text = r['screenshotUrl']?.toString() ?? '';
            _msgCtrl.text = r['customerMessage']?.toString() ?? '';
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.menu_book, color: color, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['contentTitle']?.toString() ?? 'Content',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text(status.toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if ((r['adminMessage']?.toString() ?? '').isNotEmpty)
                  _noteCard('Message from admin',
                      r['adminMessage'].toString(), Colors.blue),
                if ((r['rejectionReason']?.toString() ?? '').isNotEmpty)
                  _noteCard('Rejection reason',
                      r['rejectionReason'].toString(), Colors.red),
                const SizedBox(height: 12),
                if (editable && !_editing)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'You can edit this request for 30 minutes after submitting.',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () =>
                                setState(() => _editing = true),
                            child: const Text('Edit Details'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_editing)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Edit request',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _refCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Transaction reference',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _shotCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Receipt screenshot URL',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _msgCtrl,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                  labelText: 'Message for admin (optional)',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _saving ? null : _saveEdits,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.navy,
                                      foregroundColor: Colors.white),
                                  child: _saving
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Text('Save'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                  onPressed: () =>
                                      setState(() => _editing = false),
                                  child: const Text('Cancel')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Details',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _kv('Title', r['contentTitle']?.toString() ?? '—'),
                        if ((r['contentTitleNe']?.toString() ?? '').isNotEmpty)
                          _kv('Title (NE)',
                              r['contentTitleNe'].toString()),
                        _kv('Type', r['contentType']?.toString() ?? '—'),
                        _kv('Course ID', r['courseId']?.toString() ?? '—'),
                        _kv('Subject ID', r['subjectId']?.toString() ?? '—'),
                        _kv('Unit ID', r['unitId']?.toString() ?? '—'),
                        _kv('Amount', 'Rs. ${_money(r['amount'])}'),
                        _kv('Transaction ref',
                            r['transactionRef']?.toString() ?? '—'),
                        _kv('Submitted', _fmtDate(r['submittedAt'])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if ((r['screenshotUrl']?.toString() ?? '').isNotEmpty) ...[
                  const Text('Receipt screenshot',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(r['screenshotUrl'].toString(),
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            color: Colors.black12,
                            child: const Center(
                                child: Icon(Icons.broken_image)))),
                  ),
                ],
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

  Widget _noteCard(String title, String body, Color color) => Container(
        margin: const EdgeInsets.only(top: 12),
        child: Card(
          color: color.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 6),
                Text(body),
              ],
            ),
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

  String _money(dynamic v) {
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
