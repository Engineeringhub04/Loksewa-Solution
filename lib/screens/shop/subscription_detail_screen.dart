// Subscription request detail.
// Mirrors app/subscription/[id].tsx: status crown (status-coloured gradient
// with amount hero), a 30-minute edit window with a draining progress bar and
// edit form (transactionRef, screenshot, customerMessage), admin message,
// rejection reason, status timeline (submitted -> under review ->
// approved/rejected/expired), payment summary, tappable receipt image
// (zoom dialog), and Renew / Contact Support buttons.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

const int _editWindowMs = 30 * 60 * 1000;

class SubscriptionDetailScreen extends StatefulWidget {
  final String id;
  const SubscriptionDetailScreen({super.key, required this.id});

  @override
  State<SubscriptionDetailScreen> createState() =>
      _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen> {
  late Future<Map<String, dynamic>?> _future = _load();
  final _refCtrl = TextEditingController();
  final _shotCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  Future<Map<String, dynamic>?> _load() async {
    final token = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('app_subscriptions/${widget.id}',
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
    final submitted =
        DateTime.tryParse(r['submittedAt']?.toString() ?? '');
    if (submitted == null) return false;
    return DateTime.now().difference(submitted).inMilliseconds < _editWindowMs;
  }

  double _editProgress(Map<String, dynamic> r) {
    final submitted =
        DateTime.tryParse(r['submittedAt']?.toString() ?? '');
    if (submitted == null) return 0;
    final elapsed =
        DateTime.now().difference(submitted).inMilliseconds / _editWindowMs;
    return (1 - elapsed).clamp(0.0, 1.0);
  }

  Future<void> _saveEdits() async {
    setState(() => _saving = true);
    try {
      final token = await AuthService.getValidIdToken();
      await FirestoreRest.setDocument(
        'app_subscriptions/${widget.id}',
        {
          'transactionRef': _refCtrl.text.trim(),
          'screenshotUrl': _shotCtrl.text.trim(),
          'customerMessage':
              _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
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
        return Colors.green;
      case 'pending':
        return Colors.amber.shade700;
      case 'rejected':
        return Colors.red;
      case 'expired':
        return Colors.grey;
      default:
        return AppColors.navy;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Details'),
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
                    child: Text('Could not load request.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final r = snap.data;
          if (r == null) {
            return const Center(child: Text('Request not found.'));
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
                // Status crown + amount hero
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.workspace_premium,
                          color: Colors.white, size: 40),
                      const SizedBox(height: 8),
                      Text(status.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Rs. ${_money(r['amount'])}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold)),
                      Text(r['planName']?.toString() ?? '',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Edit window
                if (editable && !_editing) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('You can still edit this request',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                              value: _editProgress(r),
                              backgroundColor: Colors.black12,
                              color: AppColors.accent),
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
                ],
                if (_editing) ...[
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
                ],
                // Admin message / rejection reason
                if ((r['adminMessage']?.toString() ?? '').isNotEmpty)
                  _infoCard('Message from admin',
                      r['adminMessage'].toString(), Colors.blue),
                if ((r['rejectionReason']?.toString() ?? '').isNotEmpty)
                  _infoCard('Rejection reason',
                      r['rejectionReason'].toString(), Colors.red),
                const SizedBox(height: 8),
                // Timeline
                _timeline(status, r),
                const SizedBox(height: 16),
                // Payment summary
                _summaryCard(r),
                const SizedBox(height: 16),
                // Receipt image
                if ((r['screenshotUrl']?.toString() ?? '').isNotEmpty) ...[
                  const Text('Receipt',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _zoomDialog(
                        context, r['screenshotUrl'].toString()),
                    child: ClipRRect(
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
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white),
                        onPressed: () => context.push(
                            '/subscription/checkout?planId=${r['planId'] ?? ''}'),
                        child: const Text('Renew'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.push('/help'),
                        child: const Text('Contact Support'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoCard(String title, String body, Color color) => Card(
        color: color.withOpacity(0.08),
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
      );

  Widget _timeline(String status, Map<String, dynamic> r) {
    final steps = [
      ('Submitted', r['submittedAt'], true),
      ('Under review', r['submittedAt'],
          status == 'active' || status == 'rejected' || status == 'expired'),
      (
        status == 'rejected'
            ? 'Rejected'
            : status == 'expired'
                ? 'Expired'
                : 'Approved',
        r['reviewedAt'],
        status == 'active' || status == 'rejected' || status == 'expired'
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Timeline',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...steps.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                          (s.$3 as bool)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: (s.$3 as bool)
                              ? Colors.green
                              : Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(s.$1 as String,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      Text(_fmtDate(s.$2),
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> r) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Payment Summary',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _kv('Method', r['method']?.toString() ?? '—'),
              _kv('Transaction ref', r['transactionRef']?.toString() ?? '—'),
              _kv('Amount', 'Rs. ${_money(r['amount'])}'),
              if ((r['couponCode']?.toString() ?? '').isNotEmpty)
                _kv('Coupon', r['couponCode'].toString()),
              _kv('Submitted', _fmtDate(r['submittedAt'])),
              if ((r['startDate']?.toString() ?? '').isNotEmpty)
                _kv('Start', _fmtDate(r['startDate'])),
              if ((r['expiryDate']?.toString() ?? '').isNotEmpty)
                _kv('Expiry', _fmtDate(r['expiryDate'])),
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

  void _zoomDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(url,
              errorBuilder: (_, __, ___) =>
                  const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Could not load image.'))),
        ),
      ),
    );
  }

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
