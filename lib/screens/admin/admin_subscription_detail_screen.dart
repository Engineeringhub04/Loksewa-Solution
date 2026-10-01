import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'admin_review_dialogs.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Admin → review one subscription request. Approve activates the subscription
/// immediately (writes isPremium + premiumPlanName + premiumExpiryDate onto
/// the user doc); Reject tags it 'rejected' with a reason the user sees on
/// their Subscription page. Either action keeps the request permanently
/// visible in the admin list — this screen just updates its status/tag, never
/// deletes it. Mirrors app/admin/subscriptions/[id].tsx. Collections:
/// app_subscriptions, app_subscription_plans, users, app_courses.
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
        'app_subscriptions/${widget.id}',
        idToken: token);
    if (record == null) return null;
    // Plans (active only, ordered) — the approve expiry window comes from
    // the plan's durationDays, exactly like fetchSubscriptionPlans().
    try {
      final plans = await FirestoreRest.listDocuments('app_subscription_plans',
          idToken: token);
      plans.retainWhere((p) => p['isActive'] != false);
      plans.sort(((a, b) =>
          ((a['order'] ?? 0) as num).compareTo((b['order'] ?? 0) as num)));
      record['_plans'] = plans;
    } catch (_) {
      record['_plans'] = <Map<String, dynamic>>[];
    }
    // Requesting user's profile + their course info (course · subcourse
    // names), like fetchUserProfile + fetchUserCourseInfo.
    try {
      final uid = record['uid'];
      if (uid is String && uid.isNotEmpty) {
        final userProfile =
            await FirestoreRest.getDocument('users/$uid', idToken: token);
        record['_profile'] = userProfile;
        record['_courseInfo'] = await _fetchUserCourseInfo(userProfile, token);
      }
    } catch (_) {}
    return record;
  }

  /// Mirrors fetchUserCourseInfo(): course name from app_courses/{courseId},
  /// subcourse name from the sub-collection with the legacy flat
  /// app_subcourses fallback.
  Future<Map<String, String?>> _fetchUserCourseInfo(
      Map<String, dynamic>? userDoc, String token) async {
    final courseId = userDoc?['courseId'] as String?;
    final subcourseId = userDoc?['subcourseId'] as String?;
    if (courseId == null || courseId.isEmpty) {
      return {'courseName': null, 'subcourseName': null};
    }
    String? courseName;
    String? subcourseName;
    try {
      final courseDoc = await FirestoreRest.getDocument('app_courses/$courseId',
          idToken: token);
      courseName = courseDoc?['name'] as String?;
    } catch (_) {
      // ignore — course may have been removed
    }
    if (subcourseId != null && subcourseId.isNotEmpty) {
      try {
        final subDoc = await FirestoreRest.getDocument(
            'app_courses/$courseId/subcourses/$subcourseId',
            idToken: token);
        subcourseName = subDoc?['name'] as String?;
      } catch (_) {
        // ignore
      }
      if (subcourseName == null) {
        try {
          final legacyDoc = await FirestoreRest.getDocument(
              'app_subcourses/$subcourseId',
              idToken: token);
          subcourseName = legacyDoc?['name'] as String?;
        } catch (_) {
          // ignore — subcourse may have been removed
        }
      }
    }
    return {'courseName': courseName, 'subcourseName': subcourseName};
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
      final days = _durationDays(record);
      final now = DateTime.now();
      final expiry = now.add(Duration(days: days));
      final adminMessage =
          _adminMessage.text.trim().isEmpty ? null : _adminMessage.text.trim();
      // Atomic two-write batch, like approveSubscription()'s commitWrites:
      // activate the request AND mirror premium flags onto the user doc.
      await FirestoreRest.commitWrites(
        [
          FirestoreWrite(
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
            merge: true,
          ),
          if (record['uid'] is String && (record['uid'] as String).isNotEmpty)
            FirestoreWrite(
              'users/${record['uid']}',
              {
                'isPremium': true,
                'premiumPlanName': record['planName'],
                'premiumBillingCycle': record['billingCycle'],
                'premiumExpiryDate': expiry.toIso8601String(),
                'updatedAt': FirestoreRest.serverTimestamp(),
              },
              merge: true,
            ),
        ],
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

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      showToast(
          context, AppLanguage.tr('Copied', 'कपि भयो'), ToastVariant.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Stack (not Column): the busy dim barrier below sits ABOVE everything
      // including the header, so it never leaves white slivers at the
      // header's curved corners — same pattern as the chapter/units pages.
      body: Stack(
        children: [
          Column(
            children: [
              SubpageHeader(
                  title: AppLanguage.tr(
                      'Subscription Requests', 'सदस्यता अनुरोधहरू')),
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
                              'This subscription request was not found.',
                              'यो सदस्यता अनुरोध भेटिएन।')));
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
            : status == 'expired'
                ? Colors.grey
                : Colors.orange;
    final label = status == 'active'
        ? AppLanguage.tr('Approved', 'स्वीकृत')
        : status == 'rejected'
            ? AppLanguage.tr('Rejected', 'अस्वीकृत')
            : status == 'expired'
                ? AppLanguage.tr('Expired', 'म्याद सकिएको')
                : AppLanguage.tr('New', 'नयाँ');
    final profile = record['_profile'] as Map<String, dynamic>?;
    final courseInfo = record['_courseInfo'] as Map<String, String?>?;
    final alreadyReviewed = status == 'active' || status == 'rejected';
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
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 18, fontWeight: FontWeight.bold)),
              if (record['adminMessage'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
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
                  '${courseInfo?['courseName'] ?? '—'} · ${courseInfo?['subcourseName'] ?? '—'}',
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
                  onPressed: _busy ? null : () => _approve(record),
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
                if (alreadyReviewed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      AppLanguage.tr(
                          'You can change this decision any time — approving/rejecting again updates the status.',
                          'तपाईं यो निर्णय जुनसुकै बेला परिवर्तन गर्न सक्नुहुन्छ — फेरि स्वीकृत/अस्वीकार गर्दा स्थिति अपडेट हुन्छ।'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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
              _row(AppLanguage.tr('User', 'प्रयोगकर्ता'),
                  '${record['userName'] ?? record['userEmail'] ?? record['uid'] ?? '—'}'),
              _row(AppLanguage.tr('Plan', 'योजना'),
                  '${record['planName'] ?? '—'}'),
              _row(AppLanguage.tr('Amount', 'रकम'),
                  'Rs. ${record['amount'] ?? '—'}'),
              _row(AppLanguage.tr('Payment Method', 'भुक्तानी विधि'),
                  (record['method'] ?? '').toString().toUpperCase()),
              _row(AppLanguage.tr('Reference', 'सन्दर्भ'),
                  '${record['transactionRef'] ?? '—'}'),
              if (record['couponCode'] != null)
                _row(
                    AppLanguage.tr(
                        'Coupon Code (optional)', 'कुपन कोड (वैकल्पिक)'),
                    '${record['couponCode']}'),
              _row(AppLanguage.tr('Submitted', 'पेश गरिएको मिति'),
                  _fmtDateTime(record['submittedAt'])),
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
          Text(AppLanguage.tr('Screenshot', 'स्क्रिनसट'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _fullscreen(screenshotUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(screenshotUrl,
                  height: 220, width: double.infinity, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 8),
          // URL row: display-only link + copy button (no url_launcher;
          // external links stay display-only).
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(screenshotUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ),
                IconButton(
                  tooltip: AppLanguage.tr('Copy link', 'लिङ्क कपि'),
                  onPressed: () => _copyUrl(screenshotUrl),
                  icon: const Icon(Icons.copy_outlined,
                      size: 18, color: Colors.blue),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  static String _fmtDateTime(dynamic v) {
    DateTime? d;
    if (v is DateTime) d = v;
    if (v is String) d = DateTime.tryParse(v);
    if (d == null) return '—';
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 100,
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
