import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loksewa_solution/services/admin_notify_service.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';

/// Admin → review one subscription request. Approve activates the subscription
/// immediately (writes isPremium + premiumPlanName + premiumExpiryDate onto
/// the user doc); Reject tags it 'rejected' with a reason the user sees on
/// their Subscription page. Either action keeps the request permanently
/// visible in the admin list — this screen just updates its status/tag, never
/// deletes it. Mirrors app/admin/subscriptions/[id].tsx. Collections:
/// app_subscriptions, app_subscription_plans, users, app_courses.
///
/// PREMIUM layout: a status-tinted gradient hero, a user card with a course
/// chip, an icon-led payment-details card, the screenshot card, the decision
/// section (Reject / Approve / Other toggle), a required message field, and a
/// sticky bottom zone with ONE Save button — disabled until every required
/// field is filled. Save opens an AppModalShell confirm whose own Save button
/// carries the loading state; on success the page reloads.
///
/// Logic is untouched: same load (record + plans + profile + course info),
/// same approve atomic batch, same reject write (same collections, status
/// values, fields), same copy-url, same loading / denied / error / not-found
/// states, and the Scaffold > Stack [Column[header, body]] structure is
/// preserved. The payment-proof image now opens with the global
/// showImageViewer.
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
  final _customReason = TextEditingController();

  /// null = nothing chosen yet; 'approve' | 'reject' | 'other'.
  String? _decision;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _adminMessage.addListener(_onReviewFieldsChanged);
    _customReason.addListener(_onReviewFieldsChanged);
  }

  @override
  void dispose() {
    _adminMessage.removeListener(_onReviewFieldsChanged);
    _customReason.removeListener(_onReviewFieldsChanged);
    _adminMessage.dispose();
    _customReason.dispose();
    super.dispose();
  }

  /// Rebuild so the Save button's enabled state tracks the inputs.
  void _onReviewFieldsChanged() {
    if (mounted) setState(() {});
  }

  /// The single Save button stays disabled until every required field is
  /// filled: a decision is chosen, Other brings its custom text, and the
  /// message is non-empty.
  bool get _canSave {
    if (_decision == null) return false;
    if (_decision == 'other' && _customReason.text.trim().isEmpty) {
      return false;
    }
    return _adminMessage.text.trim().isNotEmpty;
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

  /// Approve write — the exact two-write batch the old Approve button ran
  /// (status 'active', expiry window from the plan, premium flags mirrored
  /// onto the user doc). Throws on failure so the confirm dialog can stay
  /// open with an error toast.
  Future<void> _writeApprove(Map<String, dynamic> record) async {
    final reviewer = AuthService.currentUser;
    if (reviewer == null) {
      throw Exception(
          AppLanguage.tr('Not signed in.', 'साइन इन गरिएको छैन।'));
    }
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
  }

  /// Reject write — the exact updateDocument the old Reject button ran:
  /// status 'rejected' + rejectionReason. [reason] is the default
  /// verification text for a plain Reject, or the admin's custom text for
  /// Other. Throws on failure.
  Future<void> _writeReject(String reason) async {
    final reviewer = AuthService.currentUser;
    if (reviewer == null) {
      throw Exception(
          AppLanguage.tr('Not signed in.', 'साइन इन गरिएको छैन।'));
    }
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
  }

  /// Save → AppModalShell CONFIRM popup → the popup's Save button shows the
  /// loading state while the write runs → success pops, toasts, and the
  /// page reloads.
  Future<void> _onSave(Map<String, dynamic> record) async {
    if (!_canSave) return;
    final decision = _decision!;
    final saved = await AppModalShell.show<bool>(
      context: context,
      builder: (c) => _DecisionConfirmDialog(
        decision: decision,
        customReason: _customReason.text.trim(),
        message: _adminMessage.text.trim(),
        onConfirm: () async {
          if (decision == 'approve') {
            await _writeApprove(record);
          } else {
            await _writeReject(
                decision == 'other' ? _customReason.text.trim() : '');
          }
        },
      ),
    );
    if (saved != true || !mounted) return;
    // Best-effort push to the subscriber — never blocks.
    final subscriberUid = (record['uid'] ?? '').toString();
    if (subscriberUid.isNotEmpty) {
      final isApprove = decision == 'approve';
      unawaited(AdminNotifyService.notifyUser(
        uid: subscriberUid,
        title: isApprove ? 'Subscription approved 🎉' : 'Subscription rejected ❌',
        body: isApprove
            ? 'Your subscription is now active. Enjoy your premium access!'
            : 'Your subscription was rejected. Reason: ${decision == 'other' ? _customReason.text.trim() : 'Payment could not be verified.'}',
        deepLink: '/subscription/${widget.id}',
      ));
    }
    showToast(
        context,
        decision == 'approve'
            ? AppLanguage.tr(
                'Subscription approved.', 'सदस्यता स्वीकृत भयो।')
            : AppLanguage.tr(
                'Subscription rejected.', 'सदस्यता अस्वीकृत भयो।'),
        ToastVariant.success);
    _refresh();
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      showToast(
          context, AppLanguage.tr('Copied', 'कपि भयो'), ToastVariant.success);
    }
  }

  /// Status tone through the theme palette (lifted variants in dark mode).
  Color _statusTone(String status) {
    final palette = ExpoPalette.of(context);
    switch (status) {
      case 'active':
        return palette.success;
      case 'rejected':
        return palette.danger;
      case 'expired':
        return palette.textDisabled;
      default:
        return palette.warning;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return AppLanguage.tr('Approved', 'स्वीकृत');
      case 'rejected':
        return AppLanguage.tr('Rejected', 'अस्वीकृत');
      case 'expired':
        return AppLanguage.tr('Expired', 'म्याद सकिएको');
      default:
        return AppLanguage.tr('New', 'नयाँ');
    }
  }

  static String _statusSubtitle(String status) {
    switch (status) {
      case 'active':
        return AppLanguage.tr(
            'Premium activated', 'प्रिमियम सक्रिय भयो');
      case 'rejected':
        return AppLanguage.tr(
            'Payment not approved', 'भुक्तानी स्वीकृत भएन');
      case 'expired':
        return AppLanguage.tr(
            'Request expired', 'अनुरोधको म्याद सकियो');
      default:
        return AppLanguage.tr(
            'Awaiting your review', 'तपाईंको समीक्षाको प्रतीक्षामा');
    }
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'expired':
        return Icons.schedule;
      default:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Stack (not Column): kept as a single-child Stack so the structure
      // stays identical to the chapter/units pages' pattern.
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
        ],
      ),
    );
  }

  /// Scrolling review content above a sticky bottom Save zone — the
  /// decision (Reject / Approve / Other) sits just above the message field,
  /// and the single Save button stays enabled only when every required
  /// field is filled.
  Widget _body(Map<String, dynamic> record) {
    final status = '${record['status'] ?? 'pending'}';
    final tone = _statusTone(status);
    final label = _statusLabel(status);
    final profile = record['_profile'] as Map<String, dynamic>?;
    final courseInfo = record['_courseInfo'] as Map<String, String?>?;
    final alreadyReviewed = status == 'active' || status == 'rejected';
    final screenshotUrl = (record['screenshotUrl'] as String?) ?? '';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SyllabusEntrance(
                  delayMs: 0,
                  child: _statusHero(record, status, tone, label)),
              const SizedBox(height: 12),
              SyllabusEntrance(
                  delayMs: 60,
                  child: _userCard(profile, record, courseInfo)),
              const SizedBox(height: 12),
              SyllabusEntrance(
                  delayMs: 120, child: _detailsCard(record)),
              if (screenshotUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                SyllabusEntrance(
                    delayMs: 180,
                    child: _screenshotCard(screenshotUrl)),
              ],
              const SizedBox(height: 12),
              SyllabusEntrance(
                  delayMs: 220, child: _decisionCard()),
              const SizedBox(height: 12),
              SyllabusEntrance(
                  delayMs: 240, child: _messageCard()),
              const SizedBox(height: 16),
            ],
          ),
        ),
        _actionZone(record, alreadyReviewed),
      ],
    );
  }

  /// Status hero: the request's state as a full-bleed gradient banner with
  /// a glass icon tile and the admin's message on it when present.
  Widget _statusHero(Map<String, dynamic> record, String status, Color tone,
      String label) {
    final deep = Color.lerp(tone, Colors.black, 0.35) ?? tone;
    final adminMessage = record['adminMessage'];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        gradient: LinearGradient(
          colors: [tone, deep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        child: Stack(
          children: [
            Positioned(
              top: -48,
              right: -32,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              bottom: -56,
              left: 40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color:
                              Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: Icon(_statusIcon(status),
                        color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2)),
                        const SizedBox(height: 3),
                        Text(_statusSubtitle(status),
                            style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: 0.85),
                                fontSize: 13)),
                        if (adminMessage != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('$adminMessage',
                                style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.95),
                                    fontSize: 13,
                                    height: 1.4)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Who is asking: photo (or gradient initial), name, email, and a
  /// course · subcourse chip.
  Widget _userCard(Map<String, dynamic>? profile,
      Map<String, dynamic> record, Map<String, String?>? courseInfo) {
    final palette = ExpoPalette.of(context);
    final photoUrl = (profile?['photoURL'] as String?) ?? '';
    final name = '${profile?['name'] ?? record['userName'] ?? '—'}';
    final email = '${profile?['email'] ?? record['userEmail'] ?? '—'}';
    final courseLine =
        '${courseInfo?['courseName'] ?? '—'} · ${courseInfo?['subcourseName'] ?? '—'}';
    final initial =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final info = palette.info;
    final infoDeep = Color.lerp(info, Colors.black, 0.25) ?? info;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          if (photoUrl.isNotEmpty)
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: info.withValues(alpha: 0.4), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: info.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CircleAvatar(
                  radius: 28,
                  backgroundImage: NetworkImage(photoUrl)),
            )
          else
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [info, infoDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: info.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary)),
                const SizedBox(height: 3),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: palette.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: info.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(ExpoRadius.pill),
                    border: Border.all(
                        color: info.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_outlined,
                          size: 13, color: info),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(courseLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: info)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Payment facts as icon-led rows with indented hairline dividers.
  Widget _detailsCard(Map<String, dynamic> record) {
    final palette = ExpoPalette.of(context);
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.receipt_long_outlined,
                      size: 18, color: palette.info),
                ),
                const SizedBox(width: 10),
                Text(
                  AppLanguage.tr(
                      'Payment details', 'भुक्तानी विवरण'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary),
                ),
              ],
            ),
          ),
          _infoRow(Icons.card_membership_outlined,
              AppLanguage.tr('Plan', 'योजना'), '${record['planName'] ?? '—'}'),
          _infoRow(Icons.payments_outlined,
              AppLanguage.tr('Amount', 'रकम'), 'Rs. ${record['amount'] ?? '—'}',
              valueColor: palette.success),
          _infoRow(Icons.account_balance_wallet_outlined,
              AppLanguage.tr('Payment Method', 'भुक्तानी विधि'),
              (record['method'] ?? '').toString().toUpperCase()),
          _infoRow(Icons.tag_outlined, AppLanguage.tr('Reference', 'सन्दर्भ'),
              '${record['transactionRef'] ?? '—'}'),
          if (record['couponCode'] != null)
            _infoRow(
                Icons.percent_outlined,
                AppLanguage.tr(
                    'Coupon Code (optional)', 'कुपन कोड (वैकल्पिक)'),
                '${record['couponCode']}'),
          _infoRow(Icons.schedule_outlined,
              AppLanguage.tr('Submitted', 'पेश गरिएको मिति'),
              _fmtDateTime(record['submittedAt'])),
          if (record['customerMessage'] != null)
            _infoRow(
                Icons.message_outlined,
                AppLanguage.tr(
                    'Message (optional)', 'सन्देश (वैकल्पिक)'),
                '${record['customerMessage']}'),
          if (record['rejectionReason'] != null)
            _infoRow(Icons.report_outlined,
                AppLanguage.tr('Reject reason', 'अस्वीकारको कारण'),
                '${record['rejectionReason']}',
                iconColor: palette.danger),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color? iconColor, Color? valueColor}) {
    final palette = ExpoPalette.of(context);
    final ic = iconColor ?? palette.info;
    return Column(
      children: [
        Divider(
            height: 1,
            indent: 64,
            endIndent: 16,
            color: palette.divider),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ic.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: ic),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            color: palette.textSecondary,
                            letterSpacing: 0.4)),
                    const SizedBox(height: 2),
                    Text(value,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: valueColor ?? palette.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _screenshotCard(String url) {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(AppLanguage.tr('Screenshot', 'स्क्रिनसट'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary)),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: GestureDetector(
            onTap: () => _fullscreen(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(url,
                  height: 220, width: double.infinity, fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // URL row: display-only link + copy button (no url_launcher;
        // external links stay display-only).
        Container(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: palette.textSecondary)),
                ),
              ),
              IconButton(
                tooltip: AppLanguage.tr('Copy link', 'लिङ्क कपि'),
                onPressed: () => _copyUrl(url),
                icon: Icon(Icons.copy_outlined,
                    size: 18, color: palette.info),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The review decision section: a Reject / Approve / Other segmented
  /// toggle. Choosing Other reveals a free-text input whose content is saved
  /// as the rejection reason (the same field the old reject flow wrote).
  Widget _decisionCard() {
    final palette = ExpoPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.how_to_vote_outlined,
                    size: 18, color: palette.info),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLanguage.tr('Your decision', 'तपाईंको निर्णय'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: palette.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(ExpoRadius.pill),
                ),
                child: Text(
                  AppLanguage.tr('Required', 'आवश्यक'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _decisionToggle(),
          if (_decision == 'other') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customReason,
              style: TextStyle(
                  color: palette.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: palette.surfaceAlt,
                hintText: AppLanguage.tr(
                    'Type the reason — e.g. Duplicate, Fake…',
                    'कारण लेख्नुहोस्'),
                hintStyle: TextStyle(
                    color: palette.textDisabled, fontSize: 13),
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: palette.info, width: 1.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _decisionToggle() {
    final palette = ExpoPalette.of(context);
    final options = [
      _DecisionOption('reject', AppLanguage.tr('Reject', 'अस्वीकृत'),
          Icons.cancel_outlined, palette.danger),
      _DecisionOption('approve', AppLanguage.tr('Approve', 'स्वीकृत'),
          Icons.check_circle_outlined, palette.success),
      _DecisionOption('other', AppLanguage.tr('Other', 'अन्य'),
          Icons.edit_outlined, palette.info),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: _decisionSegment(o),
            ),
        ],
      ),
    );
  }

  Widget _decisionSegment(_DecisionOption option) {
    final selected = _decision == option.value;
    final palette = ExpoPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _decision = option.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? option.color : Colors.transparent,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: option.color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(option.icon,
                size: 17,
                color: selected ? Colors.white : palette.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Required note back to the user, sent along with the decision.
  Widget _messageCard() {
    final palette = ExpoPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.edit_note_outlined,
                    size: 18, color: palette.info),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLanguage.tr(
                      'Message to user', 'प्रयोगकर्तालाई सन्देश'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: palette.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(ExpoRadius.pill),
                ),
                child: Text(
                  AppLanguage.tr('Required', 'आवश्यक'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _adminMessage,
            maxLines: 3,
            minLines: 3,
            style:
                TextStyle(color: palette.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: palette.surfaceAlt,
              hintText: AppLanguage.tr(
                  'e.g. Thanks! Your payment matched perfectly.',
                  'जस्तै धन्यवाद! तपाईंको भुक्तानी सही मिल्यो।'),
              hintStyle: TextStyle(
                  color: palette.textDisabled, fontSize: 13),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: palette.info, width: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.tr(
                'Shown back to the user alongside the approval/rejection.',
                'स्वीकृति/अस्वीकृतिसँगै प्रयोगकर्तालाई देखाइनेछ।'),
            style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
                height: 1.4),
          ),
        ],
      ),
    );
  }

  /// Sticky bottom zone: ONE Save button, enabled only when the decision,
  /// the Other custom text (when chosen), and the message are all filled.
  /// Save opens the AppModalShell confirm; the write's loading state lives
  /// on the popup's Save button.
  Widget _actionZone(
      Map<String, dynamic> record, bool alreadyReviewed) {
    final palette = ExpoPalette.of(context);
    final enabled = _canSave;
    final info = palette.info;
    final deep = Color.lerp(info, Colors.black, 0.18) ?? info;
    final disabledText = palette.textDisabled;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: enabled ? 1 : 0.5,
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: enabled
                          ? LinearGradient(
                              colors: [info, deep],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: enabled ? null : palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: enabled
                          ? [
                              BoxShadow(
                                color: info.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: enabled ? () => _onSave(record) : null,
                      child: Container(
                        height: 56,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.save_outlined,
                                color:
                                    enabled ? Colors.white : disabledText,
                                size: 21),
                            const SizedBox(width: 8),
                            Text(
                              AppLanguage.tr(
                                  'Save decision', 'निर्णय सेभ गर्नुहोस्'),
                              style: TextStyle(
                                  color: enabled
                                      ? Colors.white
                                      : disabledText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (alreadyReviewed) ...[
                const SizedBox(height: 10),
                Text(
                  AppLanguage.tr(
                      'You can change this decision any time — approving/rejecting again updates the status.',
                      'तपाईं यो निर्णय जुनसुकै बेला परिवर्तन गर्न सक्नुहुन्छ — फेरि स्वीकृत/अस्वीकार गर्दा स्थिति अपडेट हुन्छ।'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                      height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(ExpoRadius.lg),
      border: Border.all(color: palette.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
          blurRadius: 18,
          offset: const Offset(0, 8),
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
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  /// Payment-proof image → the global dimmed viewer (pinch-zoom,
  /// black-circle X close), the same viewer the rest of the app uses.
  void _fullscreen(String url) =>
      showImageViewer(context, NetworkImage(url));
}

class _DecisionOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _DecisionOption(this.value, this.label, this.icon, this.color);
}

/// Confirm card for the subscription decision — the shared AppModalShell
/// global modal (same modal as the daily-limit popup; only the content
/// differs). Shown via `AppModalShell.show<bool>`; pops `true` on a
/// completed save, `false`/null on Cancel or X.
///
/// The write runs on the popup's own Save button with a loading state
/// (spinner swaps into the header tile in place + "Saving…" on the button,
/// Cancel/X blocked meanwhile). On success the dialog pops `true` and the
/// caller refreshes; on error the spinner morphs back, the dialog stays
/// open, and an error toast is shown.
class _DecisionConfirmDialog extends StatefulWidget {
  /// 'approve' | 'reject' | 'other'
  final String decision;
  final String customReason;
  final String message;

  /// Runs the actual Firestore write (the caller's approve/reject path —
  /// the dialog never touches storage itself). Throw on failure.
  final Future<void> Function() onConfirm;

  const _DecisionConfirmDialog({
    required this.decision,
    required this.customReason,
    required this.message,
    required this.onConfirm,
  });

  @override
  State<_DecisionConfirmDialog> createState() => _DecisionConfirmDialogState();
}

class _DecisionConfirmDialogState extends State<_DecisionConfirmDialog> {
  bool _saving = false;

  Future<void> _confirmSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onConfirm();
      if (!mounted) return;
      // Pop through the shell: AppModalShell.show's reverse transition
      // fades + scales the card out over 200ms.
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      // Spinner morphs back; the dialog STAYS OPEN with an error toast.
      setState(() => _saving = false);
      showToast(
        context,
        AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
        ToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final isApprove = widget.decision == 'approve';
    final accent = isApprove ? palette.success : palette.danger;
    final accentMid = Color.lerp(accent, Colors.white, 0.45) ?? accent;
    final accentLight = Color.lerp(accent, Colors.white, 0.8) ?? accent;
    final decisionLabel = isApprove
        ? AppLanguage.tr('Approve', 'स्वीकृत')
        : widget.decision == 'other'
            ? AppLanguage.tr('Other', 'अन्य')
            : AppLanguage.tr('Reject', 'अस्वीकृत');
    final summaryIcon =
        isApprove ? Icons.check_circle : Icons.cancel_outlined;
    return AppModalShell(
      maxWidth: 340,
      tagLabel: AppLanguage.tr('Review decision', 'निर्णय समीक्षा'),
      accent: accent,
      accentMid: accentMid,
      accentLight: accentLight,
      tagColor: accent,
      // Cancel and the X are blocked while the write runs; the spinner
      // below is the progress signal.
      onClose: _saving ? null : () => Navigator.of(context).pop(false),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: accent,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: _saving
              ? const SizedBox(
                  key: ValueKey('saving'),
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  key: const ValueKey('decision'),
                  summaryIcon,
                  size: 28,
                  color: Colors.white,
                ),
        ),
      ),
      title: Text(
        isApprove
            ? AppLanguage.tr(
                'Approve this subscription?', 'यो सदस्यता स्वीकृत गर्ने?')
            : AppLanguage.tr(
                'Reject this subscription?', 'यो सदस्यता अस्वीकृत गर्ने?'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryRow(AppLanguage.tr('Decision', 'निर्णय'), decisionLabel),
          if (widget.decision == 'other' && widget.customReason.isNotEmpty)
            _summaryRow(
                AppLanguage.tr('Reason', 'कारण'), widget.customReason),
          _summaryRow(AppLanguage.tr('Message to user', 'प्रयोगकर्तालाई सन्देश'),
              widget.message),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _confirmSave,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(_saving
                  ? AppLanguage.tr('Saving…', 'सेभ हुँदैछ…')
                  : AppLanguage.tr('Save', 'सेभ गर्नुहोस्')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Color(0xFF64748B),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
              height: 1.4,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
