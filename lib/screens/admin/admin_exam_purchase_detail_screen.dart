import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import 'admin_review_dialogs.dart';

/// Admin → review one exam purchase request. Mirrors
/// app/admin/exam-purchases/[id].tsx. Approve tags it active; reject tags it
/// rejected with a reason. Collection: app_exam_purchases. The record is
/// never deleted — it stays in the admin list as an audit trail.
class AdminExamPurchaseDetailScreen extends StatefulWidget {
  final String id;
  const AdminExamPurchaseDetailScreen({super.key, required this.id});

  @override
  State<AdminExamPurchaseDetailScreen> createState() =>
      _AdminExamPurchaseDetailScreenState();
}

class _Denied implements Exception {}

class _AdminExamPurchaseDetailScreenState
    extends State<AdminExamPurchaseDetailScreen> {
  Future<Map<String, dynamic>?>? _future;
  final _adminMessage = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _adminMessage.dispose();
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
        'app_exam_purchases/${widget.id}',
        idToken: token);
    if (record == null) return null;
    // Best-effort user profile for the photo/name.
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

  Future<void> _approve() async {
    final reviewer = AuthService.currentUser;
    if (reviewer == null || _busy) return;
    if (!await showAdminReviewApproveDialog(context,
        approveMessage: AppLanguage.tr(
            'Approve this subscription? The user will be upgraded to Premium immediately.',
            'यो सदस्यता स्वीकृत गर्ने हो? प्रयोगकर्ता तुरुन्तै प्रिमियममा अपग्रेड हुनेछ।'))) {
      return;
    }
    setState(() => _busy = true);
    try {
      final token = await AuthService.getValidIdToken();
      await FirestoreRest.updateDocument(
        'app_exam_purchases/${widget.id}',
        {
          'status': 'active',
          'reviewedAt': DateTime.now().toIso8601String(),
          'reviewedBy': reviewer.uid,
          'adminMessage': _adminMessage.text.trim().isEmpty
              ? null
              : _adminMessage.text.trim(),
          'rejectionReason': null,
          'updatedAt': FirestoreRest.serverTimestamp(),
        },
        idToken: token,
      );
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Subscription approved.', 'सदस्यता स्वीकृत भयो।'),
            ToastVariant.success);
        _refresh();
      }
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
            ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reviewer = AuthService.currentUser;
    if (reviewer == null || _busy) return;
    final reason = await showAdminReviewRejectDialog(context);
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      final token = await AuthService.getValidIdToken();
      await FirestoreRest.updateDocument(
        'app_exam_purchases/${widget.id}',
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
      );
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Subscription rejected.', 'सदस्यता अस्वीकृत भयो।'),
            ToastVariant.success);
        _refresh();
      }
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
            ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Stack (not Column): the busy dim barrier sits ABOVE everything
      // including the header, so it never leaves white slivers at the
      // header's curved corners — same pattern as the chapter/units pages.
      body: Stack(
        children: [
          Column(
            children: [
              SubpageHeader(
                  title: AppLanguage.tr('Exam Details', 'परीक्षा विवरण')),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>?>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return PreloadingWidget(
                        tinted: false,
                        label: AppLanguage.tr(
                            'Loading Subscription...', 'सदस्यता लोड हुँदैछ...'),
                        hint: AppLanguage.tr('Fetching your purchase history',
                            'खरिद इतिहास ल्याउँदै'),
                      );
                    }
                    if (snap.hasError) {
                      if (snap.error is _Denied) {
                        return Center(
                            child: Text(AppLanguage.tr(
                                'Access denied', 'पहुँच अस्वीकृत')));
                      }
                      return Center(
                        child: ElevatedButton(
                            onPressed: _refresh,
                            child:
                                Text(AppLanguage.tr('Retry', 'पुनः प्रयास'))),
                      );
                    }
                    final record = snap.data;
                    if (record == null) {
                      return Center(
                          child: Text(AppLanguage.tr(
                              'This purchase request was not found.',
                              'यो खरिद अनुरोध भेटिएन।')));
                    }
                    return _body(record);
                  },
                ),
              ),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black45,
              child: PreloadingWidget(
                label: AppLanguage.tr(
                    'Loading Subscription...', 'सदस्यता लोड हुँदैछ...'),
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
            : Colors.orange;
    final label = status == 'active'
        ? AppLanguage.tr('Approved', 'स्वीकृत')
        : status == 'rejected'
            ? AppLanguage.tr('Rejected', 'अस्वीकृत')
            : AppLanguage.tr('New', 'नयाँ');
    final icon = status == 'active'
        ? Icons.check_circle
        : status == 'rejected'
            ? Icons.cancel
            : Icons.schedule;
    final profile = record['_profile'] as Map<String, dynamic>?;
    final screenshotUrl = (record['screenshotUrl'] as String?) ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0x14 / 0xFF),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              if (record['adminMessage'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${record['adminMessage']}',
                      style: TextStyle(color: color, fontSize: 13)),
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
            title: Text('${profile?['name'] ?? record['userName'] ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${profile?['email'] ?? record['userEmail'] ?? '—'}'),
                Text(
                  '${record['courseName'] ?? '—'} · ${record['subcourseName'] ?? '—'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            isThreeLine: true,
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
                  decoration: InputDecoration(
                    labelText: AppLanguage.tr('Message to user (optional)',
                        'प्रयोगकर्तालाई सन्देश (वैकल्पिक)'),
                    helperText: AppLanguage.tr(
                        'Shown back to the user alongside the approval/rejection.',
                        'स्वीकृति/अस्वीकृतिसँगै प्रयोगकर्तालाई देखाइनेछ।'),
                    hintText: AppLanguage.tr(
                        'e.g. Thanks! Your payment matched perfectly.',
                        'जस्तै धन्यवाद! तपाईंको भुक्तानी सही मिल्यो।'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _busy ? null : _approve,
                  child: Text(AppLanguage.tr('Approve', 'स्वीकृत गर्नुहोस्')),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _reject,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(AppLanguage.tr('Reject', 'अस्वीकार गर्नुहोस्')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _row(AppLanguage.tr('Exam Details', 'परीक्षा विवरण'),
                  '${record['examTitle'] ?? '—'}'),
              _row(AppLanguage.tr('User', 'प्रयोगकर्ता'),
                  '${record['userName'] ?? '—'}'),
              _row(AppLanguage.tr('Email', 'इमेल'),
                  '${record['userEmail'] ?? '—'}'),
              _row(AppLanguage.tr('Course', 'कोर्स'),
                  '${record['courseName'] ?? '—'}'),
              _row(AppLanguage.tr('Subcourse', 'सबकोर्स'),
                  '${record['subcourseName'] ?? '—'}'),
              _row(AppLanguage.tr('Amount', 'रकम'),
                  'Rs. ${record['amount'] ?? '—'}'),
              _row(AppLanguage.tr('Reference', 'सन्दर्भ'),
                  '${record['transactionRef'] ?? '—'}'),
              if (record['customerMessage'] != null)
                _row(AppLanguage.tr('Message (optional)', 'सन्देश (वैकल्पिक)'),
                    '${record['customerMessage']}'),
              if (record['rejectionReason'] != null)
                _row(AppLanguage.tr('Reject reason', 'अस्वीकारको कारण'),
                    '${record['rejectionReason']}'),
            ],
          ),
        ),
        if (screenshotUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _fullscreen(screenshotUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(screenshotUrl,
                  height: 230, width: double.infinity, fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text(
                AppLanguage.tr('Tap to view full screen and zoom',
                    'Full screen मा हेर्न र zoom गर्न थिच्नुहोस्'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
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
