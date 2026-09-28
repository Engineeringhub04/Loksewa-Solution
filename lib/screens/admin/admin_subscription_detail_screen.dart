import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/subpage_header.dart';

/// Admin → review one subscription request. Approve activates the subscription
/// immediately (writes isPremium + premiumPlanName + premiumExpiryDate onto the
/// user doc); reject tags it rejected with a reason. Mirrors
/// app/admin/subscriptions/[id].tsx. Collections: app_subscriptions,
/// app_subscription_plans, users.
class AdminSubscriptionDetailScreen extends StatefulWidget {
  final String id;
  const AdminSubscriptionDetailScreen({super.key, required this.id});

  @override
  State<AdminSubscriptionDetailScreen> createState() =>
      _AdminSubscriptionDetailScreenState();
}

class _Denied implements Exception {}

class _AdminSubscriptionDetailScreenState
    extends State<AdminSubscriptionDetailScreen> {
  Future<Map<String, dynamic>?>? _future;
  final _adminMessage = TextEditingController();
  final _rejectReason = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _adminMessage.dispose();
    _rejectReason.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _load() async {
    final user = AuthService.currentUser;
    if (user == null) throw _Denied();
    final token = await AuthService.getValidIdToken();
    final profile =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
    if (profile?['isAdmin'] != true) throw _Denied();
    final record = await FirestoreRest.getDocument(
        'app_subscriptions/${widget.id}',
        idToken: token);
    if (record == null) return null;
    try {
      final plans = await FirestoreRest.listDocuments(
          'app_subscription_plans',
          idToken: token);
      record['_plans'] = plans;
    } catch (_) {
      record['_plans'] = <Map<String, dynamic>>[];
    }
    try {
      final uid = record['uid'];
      if (uid is String && uid.isNotEmpty) {
        record['_profile'] =
            await FirestoreRest.getDocument('users/$uid', idToken: token);
      }
    } catch (_) {}
    return record;
  }

  void _refresh() => setState(() => _future = _load());

  int _durationDays(Map<String, dynamic> record) {
    final plans = (record['_plans'] as List?) ?? [];
    for (final p in plans) {
      final plan = p as Map<String, dynamic>;
      if ('${plan['id'] ?? ''}' == '${record['planId'] ?? ''}') {
        final days = plan['durationDays'];
        if (days is int) return days;
        if (days is String) return int.tryParse(days) ?? 30;
      }
    }
    return 30;
  }

  Future<void> _approve(Map<String, dynamic> record) async {
    final reviewer = AuthService.currentUser;
    if (reviewer == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Approve subscription'),
        content: const Text(
            'This will activate the subscription immediately. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Approve')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      final token = await AuthService.getValidIdToken();
      final days = _durationDays(record);
      final now = DateTime.now();
      final expiry = now.add(Duration(days: days));
      final adminMessage = _adminMessage.text.trim().isEmpty
          ? null
          : _adminMessage.text.trim();
      await FirestoreRest.setDocument(
        'app_subscriptions/${widget.id}',
        {
          'status': 'active',
          'reviewedAt': now.toIso8601String(),
          'reviewedBy': reviewer.uid,
          'adminMessage': adminMessage,
          'rejectionReason': null,
          'startDate': now.toIso8601String(),
          'expiryDate': expiry.toIso8601String(),
          'updatedAt': FirestoreRest.serverTimestamp(),
        },
        idToken: token,
        merge: true,
      );
      final uid = record['uid'];
      if (uid is String && uid.isNotEmpty) {
        await FirestoreRest.setDocument(
          'users/$uid',
          {
            'isPremium': true,
            'premiumPlanName': record['planName'],
            'premiumBillingCycle': record['billingCycle'],
            'premiumExpiryDate': expiry.toIso8601String(),
            'updatedAt': FirestoreRest.serverTimestamp(),
          },
          idToken: token,
          merge: true,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Subscription approved.')));
        _refresh();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Something went wrong.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reviewer = AuthService.currentUser;
    if (reviewer == null) return;
    _rejectReason.text = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reject subscription'),
        content: TextField(
          controller: _rejectReason,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Reason for rejection',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, _rejectReason.text.trim()),
              child:
                  const Text('Reject', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      final token = await AuthService.getValidIdToken();
      await FirestoreRest.setDocument(
        'app_subscriptions/${widget.id}',
        {
          'status': 'rejected',
          'reviewedAt': DateTime.now().toIso8601String(),
          'reviewedBy': reviewer.uid,
          'rejectionReason':
              reason.isEmpty ? 'Payment could not be verified.' : reason,
          'adminMessage': _adminMessage.text.trim().isEmpty
              ? null
              : _adminMessage.text.trim(),
          'updatedAt': FirestoreRest.serverTimestamp(),
        },
        idToken: token,
        merge: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Subscription rejected.')));
        _refresh();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Something went wrong.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Subscription Details'),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            if (snap.error is _Denied) {
              return const Center(child: Text('Access denied'));
            }
            return Center(
              child: ElevatedButton(
                  onPressed: _refresh, child: const Text('Retry')),
            );
          }
          final record = snap.data;
          if (record == null) {
            return const Center(
                child: Text('This subscription request was not found.'));
          }
          return _body(record);
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _body(Map<String, dynamic> record) {
    final status = '${record['status'] ?? 'pending'}';
    final Color color = status == 'active'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : status == 'expired'
                ? Colors.grey
                : Colors.orange;
    final label = status == 'active'
        ? 'Approved'
        : status == 'rejected'
            ? 'Rejected'
            : status == 'expired'
                ? 'Expired'
                : 'New';
    final profile = record['_profile'] as Map<String, dynamic>?;
    final alreadyReviewed = status == 'active' || status == 'rejected';

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                border: Border.all(color: color),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  if (record['adminMessage'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${record['adminMessage']}',
                          style: TextStyle(color: color)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: (profile?['photoURL'] as String?)?.isNotEmpty == true
                    ? CircleAvatar(
                        backgroundImage:
                            NetworkImage(profile!['photoURL'] as String))
                    : const CircleAvatar(child: Icon(Icons.person)),
                title: Text(
                    '${profile?['name'] ?? record['userName'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${profile?['email'] ?? record['userEmail'] ?? '—'}'),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _adminMessage,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Message to user (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _busy ? null : () => _approve(record),
                      child: const Text('Approve'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _busy ? null : _reject,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Reject'),
                    ),
                    if (alreadyReviewed)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'This request was already reviewed — approving or rejecting again will overwrite the previous decision.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  _row('User',
                      '${record['userName'] ?? record['userEmail'] ?? record['uid'] ?? '—'}'),
                  _row('Plan', '${record['planName'] ?? '—'}'),
                  _row('Amount', 'Rs. ${record['amount'] ?? '—'}'),
                  _row('Method',
                      '${'${record['method'] ?? ''}'.toUpperCase()}'),
                  _row('Reference', '${record['transactionRef'] ?? '—'}'),
                  if (record['couponCode'] != null)
                    _row('Coupon', '${record['couponCode']}'),
                  _row('Submitted on',
                      _fmtDateTime(record['submittedAt'])),
                  if (record['customerMessage'] != null)
                    _row('Customer note', '${record['customerMessage']}'),
                  if (record['rejectionReason'] != null)
                    _row('Reject reason', '${record['rejectionReason']}'),
                ],
              ),
            ),
            if ((record['screenshotUrl'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              const Text('Payment screenshot',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _fullscreen(record['screenshotUrl'] as String),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(record['screenshotUrl'] as String,
                      height: 220, width: double.infinity, fit: BoxFit.cover),
                ),
              ),
              const Center(
                  child: Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Tap to zoom',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              )),
            ],
            const SizedBox(height: 24),
          ],
        ),
        if (_busy)
          Container(
            color: Colors.black45,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  static String _fmtDateTime(dynamic v) {
    DateTime? d;
    if (v is DateTime) d = v;
    if (v is String) d = DateTime.tryParse(v);
    if (d == null) return '—';
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 105,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.grey))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _fullscreen(String url) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: GestureDetector(
          onTap: () => Navigator.pop(c),
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
    );
  }
}
