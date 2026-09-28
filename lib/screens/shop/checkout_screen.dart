// Checkout screen (multi-flow).
// Mirrors app/subscription/checkout.tsx. Query params decide the flow:
//   planId=...                      -> subscription plan purchase
//   examId=...                      -> exam set purchase
//   contentId,contentType,contentSubjectId,contentUnitId -> content purchase
// Payment methods: eSewa and Khalti are enabled via
// app_subscription_settings/config; QR/Manual is always available.
// eSewa/Khalti show a gateway placeholder with the same instructions UI as the
// Expo app (no gateway SDK exists in this Flutter build), then fall through
// to the receipt form. QR shows bank details + QR image + numbered
// instructions + the receipt form (transactionRef, screenshot URL, message).
// Submitting writes the order document (mirroring submitPayment /
// submitExamPurchase / submitContentPurchase) and routes to the detail screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late Future<_CheckoutData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }
  String _method = 'qr'; // esewa | khalti | qr
  final _refCtrl = TextEditingController();
  final _shotCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();
  String? _coupon;
  bool _submitting = false;
  bool _gatewayDone = false; // user confirms they paid in the gateway UI

  @override
  void dispose() {
    _refCtrl.dispose();
    _shotCtrl.dispose();
    _msgCtrl.dispose();
    _couponCtrl.dispose();
    super.dispose();
  }

  Future<_CheckoutData> _load() async {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final token = await AuthService.getValidIdToken();
    final settings = await FirestoreRest.getDocument(
        'app_subscription_settings/config',
        idToken: token);

    String title = '';
    String subtitle = '';
    num amount = 0;
    String flow = 'plan';
    Map<String, dynamic>? extra;

    if (qp['planId'] != null && qp['planId']!.isNotEmpty) {
      flow = 'plan';
      final plan = await FirestoreRest.getDocument(
          'app_subscription_plans/${qp['planId']}',
          idToken: token);
      title = plan?['name']?.toString() ?? 'Plan';
      subtitle = plan?['billingCycle']?.toString() ?? '';
      amount = _num(plan?['price']);
      extra = {'planId': qp['planId'], 'planName': title, 'billingCycle': subtitle};
    } else if (qp['examId'] != null && qp['examId']!.isNotEmpty) {
      flow = 'exam';
      final set = await FirestoreRest.getDocument(
          'app_exam_sets/${qp['examId']}',
          idToken: token);
      title = set?['title']?.toString() ?? 'Exam Set';
      subtitle = set?['contentType']?.toString() ?? '';
      amount = _num(set?['price']);
      extra = {
        'examSetId': qp['examId'],
        'examTitle': title,
        'examContentType': subtitle,
        'courseId': set?['courseId'],
        'courseName': set?['courseName'],
        'subcourseId': set?['subcourseId'],
        'subcourseName': set?['subcourseName'],
      };
    } else if (qp['contentId'] != null && qp['contentId']!.isNotEmpty) {
      flow = 'content';
      // Content price/title come from the query params the caller supplies.
      title = qp['contentTitle'] ?? 'Content';
      subtitle = qp['contentType'] ?? '';
      amount = _num(qp['contentPrice']);
      extra = {
        'contentType': qp['contentType'],
        'contentId': qp['contentId'],
        'contentTitle': title,
        'contentTitleNe': qp['contentTitleNe'],
        'subjectId': qp['contentSubjectId'],
        'unitId': qp['contentUnitId'],
      };
    }
    return _CheckoutData(flow, title, subtitle, amount, extra ?? {}, settings);
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v.toString()) ?? 0;

  bool _gatewayEnabled(_CheckoutData d, String m) {
    final s = d.settings;
    if (s == null) return false;
    final cfg = s[m];
    if (cfg is Map) return cfg['enabled'] == true;
    return false;
  }

  Future<void> _submit(_CheckoutData d) async {
    if (_refCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter your transaction reference.')));
      return;
    }
    if (_shotCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please add your receipt screenshot URL.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await AuthService.getValidIdToken();
      final user = AuthService.currentUser;
      final uid = user?.uid ?? '';
      final now = DateTime.now().millisecondsSinceEpoch;
      final base = {
        'uid': uid,
        'userName': user?.displayName,
        'userEmail': user?.email,
        'amount': d.amount,
        'currency': 'NPR',
        'status': 'pending',
        'transactionRef': _refCtrl.text.trim(),
        'screenshotUrl': _shotCtrl.text.trim(),
        'customerMessage':
            _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
        'couponCode': _coupon,
        'adminMessage': null,
        'submittedAt': DateTime.now().toIso8601String(),
        'reviewedAt': null,
        'reviewedBy': null,
        'rejectionReason': null,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      String route;
      if (d.flow == 'plan') {
        final id = '${uid}_$now';
        await FirestoreRest.setDocument('app_subscriptions/$id', {
          ...base,
          'planId': d.extra['planId'],
          'planName': d.extra['planName'],
          'billingCycle': d.extra['billingCycle'],
          'method': _method,
          'startDate': null,
          'expiryDate': null,
        }, idToken: token);
        route = '/subscription/$id';
      } else if (d.flow == 'exam') {
        final id = '${uid}_${d.extra['examSetId']}_$now';
        await FirestoreRest.setDocument('app_exam_purchases/$id', {
          ...base,
          'courseId': d.extra['courseId'],
          'courseName': d.extra['courseName'],
          'subcourseId': d.extra['subcourseId'],
          'subcourseName': d.extra['subcourseName'],
          'examSetId': d.extra['examSetId'],
          'examTitle': d.extra['examTitle'],
          'examContentType': d.extra['examContentType'],
          'method': 'qr',
        }, idToken: token);
        route = '/subscription/exam-purchase/$id';
      } else {
        final id =
            '${uid}_${d.extra['contentType']}_${d.extra['contentId']}_$now';
        await FirestoreRest.setDocument('app_content_purchases/$id', {
          ...base,
          'courseId': null,
          'subcourseId': d.extra['subjectId'],
          'contentType': d.extra['contentType'],
          'contentId': d.extra['contentId'],
          'contentTitle': d.extra['contentTitle'],
          'contentTitleNe': d.extra['contentTitleNe'],
          'subjectId': d.extra['subjectId'],
          'unitId': d.extra['unitId'],
          'method': 'qr',
        }, idToken: token);
        route = '/purchase-details/content/$id';
      }
      if (mounted) context.go(route);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Submission failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_CheckoutData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load checkout.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final d = snap.data!;
          final esewaOn = _gatewayEnabled(d, 'esewa');
          final khaltiOn = _gatewayEnabled(d, 'khalti');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _orderCard(d),
                const SizedBox(height: 16),
                const Text('Payment method',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (esewaOn)
                  _methodTile('esewa', 'eSewa',
                      'Pay instantly with eSewa', Icons.account_balance_wallet),
                if (khaltiOn)
                  _methodTile('khalti', 'Khalti',
                      'Pay instantly with Khalti', Icons.account_balance_wallet),
                _methodTile('qr', 'QR / Manual',
                    'Scan the QR or transfer manually, then upload receipt',
                    Icons.qr_code),
                const SizedBox(height: 16),
                if (_method == 'esewa' || _method == 'khalti')
                  _gatewayPlaceholder(d)
                else
                  _qrSection(d),
                const SizedBox(height: 16),
                _receiptForm(d),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _orderCard(_CheckoutData d) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              if (d.subtitle.isNotEmpty)
                Text(d.subtitle,
                    style: const TextStyle(color: Colors.black54)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Rs. ${_money(d.amount)}',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy)),
                ],
              ),
              const SizedBox(height: 8),
              // Coupon apply / remove
              if (_coupon == null)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _couponCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Coupon code (optional)',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_couponCtrl.text.trim().isEmpty) return;
                        setState(
                            () => _coupon = _couponCtrl.text.trim());
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Chip(
                        label: Text(_coupon!),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => setState(() {
                              _coupon = null;
                              _couponCtrl.clear();
                            })),
                    const SizedBox(width: 8),
                    const Text('Coupon applied',
                        style: TextStyle(color: Colors.green)),
                  ],
                ),
            ],
          ),
        ),
      );

  Widget _methodTile(
      String value, String title, String subtitle, IconData icon) {
    final selected = _method == value;
    return Card(
      color: selected ? AppColors.navy.withValues(alpha: 0.06) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: selected ? AppColors.navy : Colors.transparent, width: 2),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: _method,
        onChanged: (v) => setState(() {
          _method = v!;
          _gatewayDone = false;
        }),
        secondary: Icon(icon, color: AppColors.navy),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
      ),
    );
  }

  /// Gateway placeholder: the Expo app opens the eSewa/Khalti SDK here.
  /// No gateway SDK is available in this Flutter build, so we keep the
  /// order-creation Firestore write and show the same instructions UI.
  Widget _gatewayPlaceholder(_CheckoutData d) {
    final name = _method == 'esewa' ? 'eSewa' : 'Khalti';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pay with $name',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'The $name payment gateway opens inside the full app. '
              'Complete the payment of Rs. ${_money(d.amount)} there, '
              'then paste your transaction reference and receipt below '
              'so our team can verify it.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: Icon(_gatewayDone
                  ? Icons.check_circle
                  : Icons.open_in_new),
              label: Text(_gatewayDone
                  ? 'Payment marked as done'
                  : 'I have completed the $name payment'),
              onPressed: () =>
                  setState(() => _gatewayDone = true),
            ),
            if (!_gatewayDone)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Confirm your gateway payment above to unlock the receipt form.',
                    style: TextStyle(color: Colors.black54, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _qrSection(_CheckoutData d) {
    final manual = d.settings?['manual'];
    final bankDetails = manual is Map
        ? (manual['bankDetails']?.toString() ?? '')
        : '';
    final instructions = manual is Map
        ? (manual['instructions']?.toString() ?? '')
        : '';
    final qrUrl =
        manual is Map ? (manual['qrImageUrl']?.toString() ?? '') : '';
    final steps = instructions.isNotEmpty
        ? instructions.split('\n')
        : [
            'Scan the QR code below or transfer to the account shown.',
            'Send exactly Rs. ${_money(d.amount)}.',
            'Take a screenshot of the successful payment.',
            'Fill the receipt form below with your transaction reference.',
          ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Pay via QR / Manual transfer',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (qrUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(qrUrl,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: Colors.black12,
                        child: const Center(
                            child: Icon(Icons.qr_code, size: 48)))),
              ),
            if (bankDetails.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(bankDetails),
              ),
            ],
            const SizedBox(height: 12),
            ...steps.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.navy,
                          child: Text('${e.key + 1}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value.trim())),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _receiptForm(_CheckoutData d) {
    final gatewayLocked =
        (_method == 'esewa' || _method == 'khalti') && !_gatewayDone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Payment receipt',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _refCtrl,
              enabled: !gatewayLocked,
              decoration: const InputDecoration(
                  labelText: 'Transaction reference *',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _shotCtrl,
              enabled: !gatewayLocked,
              decoration: const InputDecoration(
                  labelText: 'Receipt screenshot URL *',
                  helperText:
                      'Upload your receipt image and paste its link here.',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _msgCtrl,
              enabled: !gatewayLocked,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Message for admin (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed:
                  (_submitting || gatewayLocked) ? null : () => _submit(d),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit for Review',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  String _money(num v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();
}

class _CheckoutData {
  final String flow; // plan | exam | content
  final String title;
  final String subtitle;
  final num amount;
  final Map<String, dynamic> extra;
  final Map<String, dynamic>? settings;
  _CheckoutData(this.flow, this.title, this.subtitle, this.amount,
      this.extra, this.settings);
}
