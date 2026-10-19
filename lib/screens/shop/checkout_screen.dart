// Checkout screen (multi-flow).
// Mirrors app/subscription/checkout.tsx block-for-block. Query params decide
// the flow:
//   planId=...                      -> subscription plan purchase
//   examId=...                      -> exam set purchase
//   contentId,contentType,contentSubjectId,contentUnitId -> content purchase
//
// Three payment methods are always shown: eSewa, Khalti, QR (Manual).
//  - eSewa/Khalti availability is independently controlled by the existing
//    app_subscription_settings/config enabled flags; false shows Coming Soon.
//  - QR (Manual) never has an on/off switch — it is the zero-budget fallback.
// Selecting eSewa/Khalti runs the in-app gateway flow: the worker's
// /payments/init returns signed payloads (secrets never touch the app),
// payment happens inside the app (eSewa webview / Khalti SDK), then the
// worker's /payments/verify activates the subscription server-side.
// Manual receipt fields are rendered for QR only. Provider secrets are
// never fetched by this screen.
//
// Writes mirror submitPayment / submitExamPurchase / submitContentPurchase
// exactly (via the existing services), then route to the detail screen.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:khalti_checkout_flutter/khalti_checkout_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:loksewa_solution/services/admin_notify_service.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/coupon_service.dart';
import 'package:loksewa_solution/services/exam_purchases.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/gateway_payment_service.dart';
import 'package:loksewa_solution/services/purchase_refresh.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/gateway_popups.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/subpage_header.dart';
import 'esewa_webview_screen.dart';

const _esewaLogo = 'https://i.ibb.co/HLpHmnQz/esewa-icon-large.png';
const _khaltiLogo = 'https://i.ibb.co/tMHZRHKQ/Khalti-Logo-New-3.png';
const _qrDownloadName = 'Ls-qr.png';

class _AppliedCoupon {
  final String code;
  final num discountedAmount;
  final String label;
  const _AppliedCoupon({
    required this.code,
    required this.discountedAmount,
    required this.label,
  });
}

/// Outcome of the payment submit work. The confirm popup stays open with an
/// inline error on failure and only closes on success or user cancel.
class _SubmitOutcome {
  final bool ok;
  final String? error;
  final String? examPurchaseId;
  final String? contentPurchaseId;
  const _SubmitOutcome({
    required this.ok,
    this.error,
    this.examPurchaseId,
    this.contentPurchaseId,
  }) : assert(ok || error != null,
            'a failed outcome must carry an error message');
}

class _CheckoutData {
  final String flow; // 'plan' | 'exam' | 'content'
  final String? examId;
  final String? contentType;
  final String? contentId;
  final String? contentSubjectId;
  final String? contentUnitId;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? exam;
  final Map<String, dynamic>? content;
  final Map<String, dynamic>? userDoc;
  final String? courseName;
  final String? subcourseName;
  final Map<String, dynamic> settings;
  final bool settingsAvailable;
  const _CheckoutData({
    required this.flow,
    required this.examId,
    required this.contentType,
    required this.contentId,
    required this.contentSubjectId,
    required this.contentUnitId,
    required this.plan,
    required this.exam,
    required this.content,
    required this.userDoc,
    required this.courseName,
    required this.subcourseName,
    required this.settings,
    required this.settingsAvailable,
  });
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

/// Resilient content-document fetch for the checkout (Method B).
///
/// Tries a direct getDocument on the constructed ID first; when that misses
/// (404) or fails, falls back to a collection query for subjects so new
/// courses/subjects and any id-format drift keep resolving automatically.
/// [getDoc] and [queryDocs] are injectable for tests.
Future<Map<String, dynamic>?> fetchCheckoutContent(
  String type,
  String contentId, {
  String? unitId,
  required String token,
  required Future<Map<String, dynamic>?> Function(String path, String token)
      getDoc,
  required Future<List<Map<String, dynamic>>> Function(
          String collection, Map<String, dynamic>? where)
      queryDocs,
}) async {
  // Real collections (mirrors the list sources in exam_service.dart):
  // subjects -> app_subjects_details/<course>__<subcourse>__<slug>
  // units    -> app_subjects_units_details/<unitId>
  // chapters -> app_subjects_chapter_details/<chapterId> (no unit)
  //             app_subjects_unit-chapters_details/<chapterId> (has unit)
  // The unitId signal picks the correct chapter collection upfront —
  // no cross-collection double-checking.
  final path = type == 'subject'
      ? 'app_subjects_details/$contentId'
      : type == 'unit'
          ? 'app_subjects_units_details/$contentId'
          : (unitId != null && unitId.isNotEmpty)
              ? 'app_subjects_unit-chapters_details/$contentId'
              : 'app_subjects_chapter_details/$contentId';
  try {
    final direct = await getDoc(path, token);
    if (direct != null) return direct;
    debugPrint('checkout _fetchContent direct miss (404) path=$path');
  } catch (e) {
    // Don't rethrow: fall through to the query fallback so a transient
    // direct-read failure still gets a chance. The caller treats a null
    // result as "Checkout not available".
    debugPrint('checkout _fetchContent direct FAILED path=$path error=$e');
  }
  try {
    if (type == 'subject') {
      // Slug = last non-empty __-segment. Query the whole (small) collection
      // and match the ID suffix — depends on nothing but the slug, so any
      // course/subcourse/id-format drift still resolves.
      final slug = contentId
          .split('__')
          .lastWhere((p) => p.isNotEmpty, orElse: () => '');
      if (slug.isNotEmpty) {
        final docs = await queryDocs('app_subjects_details', null);
        for (final d in docs) {
          if ('${d['id']}'.endsWith('__$slug')) return d;
        }
        debugPrint('checkout _fetchContent fallback no slug match '
            'slug=$slug tried=${docs.length}');
      }
    }
    // Units/chapters use opaque doc IDs minted by live queries — no
    // reliable fallback; returning null shows "not available".
  } catch (e) {
    debugPrint('checkout _fetchContent fallback FAILED type=$type error=$e');
  }
  return null;
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late Future<_CheckoutData> _future;

  String? _method; // 'esewa' | 'khalti' | 'qr' — null until the user picks one
  final _refCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();
  Uint8List? _screenshotBytes;
  bool _uploadingScreenshot = false;
  double _uploadProgress = 0;
  _AppliedCoupon? _couponApplied;
  String? _couponError;
  bool _validatingCoupon = false;
  bool _downloadingQr = false;
  bool _paying = false; // gateway flow in progress (prevents double-taps)

  /// Transaction id of the in-flight gateway payment (for exit-cancel).
  String _activeTransactionUuid = '';

  /// purchaseType of the in-flight gateway payment ('subscription' | 'exam'
  /// | 'content') — the worker's cancel endpoint needs it.
  String _activePurchaseType = 'subscription';

  @override
  void initState() {
    super.initState();
    _future = _load();
    _couponCtrl.addListener(_onCouponTextChanged);
  }

  void _onCouponTextChanged() {
    // Rebuild so the Apply button enables/disables with the input.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _couponCtrl.removeListener(_onCouponTextChanged);
    _refCtrl.dispose();
    _msgCtrl.dispose();
    _couponCtrl.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _future = _load());

  // ------------------------------------------------------------------ load

  /// Mirrors normalizeSettings(): client-safe fields only, secret keys are
  /// deliberately discarded even if an old config document still has them.
  Map<String, dynamic> _normalizeSettings(Map<String, dynamic>? doc) {
    final d = doc ?? {};
    Map<String, dynamic> asMap(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : {};
    final esewa = asMap(d['esewa']);
    final khalti = asMap(d['khalti']);
    final manual = asMap(d['manual']);
    bool asBool(dynamic v) => v == true || v == 'true';
    String asStr(dynamic v) => v is String ? v.trim() : '';
    String pick(List<dynamic> vs) {
      for (final v in vs) {
        final s = asStr(v);
        if (s.isNotEmpty) return s;
      }
      return '';
    }
    // The admin saves receiver/bank fields separately; the display below
    // expects one multi-line string. Compose it when the legacy combined
    // field is absent so the details (with copy button) actually show.
    final composedBankDetails = [
      asStr(manual['receiverName']),
      asStr(manual['receiverPhone']),
      asStr(manual['bankName']),
      asStr(manual['bankAccountNo']),
    ].where((s) => s.isNotEmpty).join('\n');
    return {
      'esewa': {'enabled': asBool(esewa['enabled'])},
      'khalti': {'enabled': asBool(khalti['enabled'])},
      'manual': {
        'qrImageUrl':
            pick([manual['qrImageUrl'], d['qrImageUrl'], manual['qrUrl']]),
        'bankDetails': pick(
            [manual['bankDetails'], d['bankDetails'], composedBankDetails]),
        'instructions': pick([manual['instructions'], d['instructions']]),
      },
    };
  }

  Future<_CheckoutData> _load() async {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final token = await AuthService.getValidIdToken();
    final uid = AuthService.currentUser?.uid ?? '';

    final planId = qp['planId'];
    final examId = qp['examId'];
    final contentId = qp['contentId'];
    final contentType = qp['contentType'];
    final contentSubjectId = qp['contentSubjectId'];
    final contentUnitId = qp['contentUnitId'];
    final isExam = examId != null && examId.isNotEmpty;
    final isContent = contentId != null &&
        contentId.isNotEmpty &&
        contentType != null &&
        contentType.isNotEmpty &&
        contentSubjectId != null &&
        contentSubjectId.isNotEmpty;
    final flow = isContent ? 'content' : (isExam ? 'exam' : 'plan');

    final results = await Future.wait<dynamic>([
      FirestoreRest.listDocuments('app_subscription_plans', idToken: token),
      _fetchSettings(token),
      isExam
          ? FirestoreRest.getDocument('app_exam_sets/$examId', idToken: token)
          : Future.value(null),
      isContent
          ? _fetchContent(
              contentType, contentSubjectId, contentId, contentUnitId, token)
          : Future.value(null),
      uid.isNotEmpty
          ? FirestoreRest.getDocument('users/$uid', idToken: token)
              .catchError((_) => null)
          : Future.value(null),
    ]);

    final plans = (results[0] as List).cast<Map<String, dynamic>>();
    final settingsRes = results[1] as _SettingsResult;
    final examDoc = results[2] as Map<String, dynamic>?;
    final contentDoc = results[3] as Map<String, dynamic>?;
    final userDoc = results[4] as Map<String, dynamic>?;

    // fetchSubscriptionPlans(): active only, ordered.
    final activePlans = plans.where((p) => p['isActive'] != false).toList()
      ..sort((a, b) => _asInt(a['order']).compareTo(_asInt(b['order'])));
    Map<String, dynamic>? plan;
    if (planId != null && planId.isNotEmpty) {
      for (final p in activePlans) {
        if ('${p['id']}' == planId) {
          plan = p;
          break;
        }
      }
    }
    if (examDoc != null) examDoc['id'] = examId;
    if (contentDoc != null) contentDoc['id'] = contentId;

    // Course names from the user profile (mirrors profileStore.courseInfo).
    String? courseName;
    String? subcourseName;
    final courseId = '${userDoc?['courseId'] ?? ''}';
    final subcourseId = '${userDoc?['subcourseId'] ?? ''}';
    if (courseId.isNotEmpty) {
      try {
        final courseDoc = await FirestoreRest.getDocument(
            'app_courses/$courseId',
            idToken: token);
        courseName = courseDoc?['name']?.toString();
      } catch (_) {}
      if (subcourseId.isNotEmpty) {
        try {
          final subDoc = await FirestoreRest.getDocument(
              'app_courses/$courseId/subcourses/$subcourseId',
              idToken: token);
          subcourseName = subDoc?['name']?.toString();
        } catch (_) {}
        if (subcourseName == null) {
          try {
            final legacyDoc = await FirestoreRest.getDocument(
                'app_subcourses/$subcourseId',
                idToken: token);
            subcourseName = legacyDoc?['name']?.toString();
          } catch (_) {}
        }
      }
    }

    return _CheckoutData(
      flow: flow,
      examId: examId,
      contentType: contentType,
      contentId: contentId,
      contentSubjectId: contentSubjectId,
      contentUnitId: contentUnitId,
      plan: plan,
      exam: examDoc,
      content: contentDoc,
      userDoc: userDoc,
      courseName: courseName,
      subcourseName: subcourseName,
      settings: settingsRes.settings,
      settingsAvailable: settingsRes.available,
    );
  }

  Future<_SettingsResult> _fetchSettings(String token) async {
    try {
      final doc = await FirestoreRest.getDocument(
          'app_subscription_settings/config',
          idToken: token);
      // Read succeeded (even a missing doc) — mirrors sourceAvailable: true.
      return _SettingsResult(_normalizeSettings(doc), true);
    } catch (_) {
      // Resilient for normal users, like the React catch → DEFAULT_SETTINGS.
      return _SettingsResult(_normalizeSettings(null), false);
    }
  }

  Future<Map<String, dynamic>?> _fetchContent(
    String type,
    String subjectId,
    String contentId,
    String? unitId,
    String token,
  ) {
    debugPrint('checkout _fetchContent type=$type contentId=$contentId '
        'subjectId=$subjectId unitId=$unitId');
    return fetchCheckoutContent(
      type,
      contentId,
      unitId: unitId,
      token: token,
      getDoc: (path, t) => FirestoreRest.getDocument(path, idToken: t),
      queryDocs: (collection, where) =>
          ExamRest.runQuery(collection, where: where, limit: 100),
    );
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  num _num(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  Map<String, dynamic>? _purchasable(_CheckoutData d) =>
      d.flow == 'content' ? d.content : (d.flow == 'exam' ? d.exam : d.plan);

  num _originalAmount(_CheckoutData d) {
    final p = _purchasable(d);
    return p == null ? 0 : _num(p['price']);
  }

  String _checkoutTitle(_CheckoutData d) {
    if (d.content != null) {
      final title = '${d.content!['title'] ?? ''}';
      final titleNe = '${d.content!['titleNe'] ?? ''}';
      if (title.isNotEmpty) {
        return AppLanguage.isNepali && titleNe.isNotEmpty ? titleNe : title;
      }
    }
    final examTitle = '${d.exam?['title'] ?? ''}';
    if (examTitle.isNotEmpty) return examTitle;
    final planName = '${d.plan?['name'] ?? ''}';
    if (planName.isNotEmpty) return planName;
    return AppLanguage.tr('Subscription Details', 'सदस्यता विवरण');
  }

  String _money(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  // ---------------------------------------------------------------- coupon

  Future<void> _handleApplyCoupon(_CheckoutData d) async {
    if (_couponCtrl.text.trim().isEmpty) return;
    if (_purchasable(d) == null) return;
    setState(() {
      _validatingCoupon = true;
      _couponError = null;
    });
    try {
      // Exam + content purchases validate against the 'exam' category.
      final category = (d.flow == 'content' || d.flow == 'exam')
          ? 'exam'
          : '${d.plan?['billingCycle'] ?? 'free'}';
      // Purchase context for the new coupon scope fields.
      String? purchaseType;
      String? scopeContentId;
      if (d.flow == 'plan') {
        purchaseType = 'subscription';
      } else if (d.flow == 'exam') {
        purchaseType = 'exam';
        scopeContentId = d.examId;
      } else if (d.flow == 'content') {
        final ct = d.contentType ?? '';
        if (ct == 'subject') {
          purchaseType = 'subject';
          scopeContentId = d.contentId;
        } else if (ct == 'chapter') {
          purchaseType = 'chapter';
          scopeContentId = d.contentId;
        } else if (ct == 'unit') {
          // Units are purchased from the chapter-level pages — 'chapter'
          // coupons apply (checked against the unit's own ID).
          purchaseType = 'chapter';
          scopeContentId = d.contentId;
        }
      }
      final couponCourseId =
          '${d.content?['courseId'] ?? d.userDoc?['courseId'] ?? ''}';
      final couponSubcourseId =
          '${d.content?['subcourseId'] ?? d.userDoc?['subcourseId'] ?? ''}';
      // Exam tier for the new examTiers coupon check — fail-open when the
      // exam doc does not carry an isPro field.
      String? examTier;
      if (d.flow == 'exam' && d.exam != null && d.exam!.containsKey('isPro')) {
        examTier = d.exam!['isPro'] == true ? 'pro' : 'free';
      }
      final result = await CouponService.validateCoupon(
        _couponCtrl.text.trim(),
        category,
        _originalAmount(d),
        purchaseType: purchaseType,
        contentId: scopeContentId,
        courseId: couponCourseId.isEmpty ? null : couponCourseId,
        subcourseId: couponSubcourseId.isEmpty ? null : couponSubcourseId,
        uid: AuthService.currentUser?.uid,
        examTier: examTier,
      );
      if (!mounted) return;
      if (!result.valid) {
        setState(() => _couponError =
            result.reason ?? AppLanguage.tr('Invalid coupon', 'अमान्य कुपन'));
        return;
      }
      setState(() => _couponApplied = _AppliedCoupon(
            code: _couponCtrl.text.trim().toUpperCase(),
            discountedAmount: result.discountedAmount ?? _originalAmount(d),
            label: result.discountLabel ?? '',
          ));
      showToast(context, AppLanguage.tr('Coupon applied', 'कुपन लागू भयो'),
          ToastVariant.success);
    } catch (_) {
      if (mounted) {
        setState(() => _couponError =
            AppLanguage.tr('Invalid coupon', 'अमान्य कुपन'));
      }
    } finally {
      if (mounted) setState(() => _validatingCoupon = false);
    }
  }

  // --------------------------------------------------------------- gateway

  /// In-app gateway payment: worker-signed init → gateway UI inside the
  /// app → worker-side verification → purchase activation.
  ///
  /// Works for all three flows: subscription plans ('subscription'),
  /// exam sets ('exam') and subject/unit/chapter content ('content').
  /// The worker reads the real price server-side — the app never sends an
  /// amount. Coupons are subscription-only on the gateway path (the worker
  /// rejects couponCode for exam/content).
  Future<void> _startGatewayPayment(_CheckoutData d) async {
    final purchasable = _purchasable(d);
    if (purchasable == null || _method == null || _method == 'qr' || _paying) {
      return;
    }
    if (!d.settingsAvailable) {
      showToast(
          context,
          AppLanguage.tr(
              'Payment settings are temporarily unavailable. Please use QR Method or try again later.',
              'भुक्तानी सेटिङ अहिले अस्थायी रूपमा उपलब्ध छैन। कृपया QR विधि प्रयोग गर्नुहोस् वा केही समयपछि पुनः प्रयास गर्नुहोस्।'),
          ToastVariant.info);
      return;
    }
    // 'plan' flow → worker purchaseType 'subscription'; exam/content pass
    // through as-is.
    final purchaseType = d.flow == 'plan' ? 'subscription' : d.flow;
    final itemId = d.flow == 'plan'
        ? '${d.plan!['id']}'
        : (d.flow == 'exam' ? d.examId : d.contentId) ?? '';
    if (itemId.isEmpty) {
      showToast(
          context,
          AppLanguage.tr('Could not start payment. Please try again.',
              'भुक्तानी सुरु हुन सकेन। कृपया पुनः प्रयास गर्नुहोस्।'),
          ToastVariant.error);
      return;
    }
    if (purchaseType != 'subscription' && _couponApplied != null) {
      // Honest UX: the coupon stays valid for the QR/manual path, but the
      // gateway charges the worker's server-side price (full). Never
      // silently drop the discount.
      showToast(
          context,
          AppLanguage.tr(
              'Coupon codes apply to QR payments only — the gateway charges the full price.',
              'कुपन कोड QR भुक्तानीमा मात्र लागू हुन्छ — गेटवेले पूरा मूल्य लिन्छ।'),
          ToastVariant.info);
    }
    final itemTitle = _checkoutTitle(d);
    setState(() => _paying = true);
    try {
      final initRes = await GatewayPaymentService.initPayment(
        gateway: _method!,
        purchaseType: purchaseType,
        planId: d.flow == 'plan' ? '${d.plan!['id']}' : null,
        itemId: d.flow == 'plan' ? null : itemId,
        contentType: d.flow == 'content' ? d.contentType : null,
        contentUnitId: d.flow == 'content' ? d.contentUnitId : null,
        couponCode: _couponApplied?.code,
      );
      if (!mounted) return;
      final txnUuid = '${initRes['transactionUuid'] ?? ''}';
      setState(() {
        _activeTransactionUuid = txnUuid;
        _activePurchaseType = purchaseType;
      });
      // Persist the pending payment BEFORE the gateway UI opens — an app
      // kill during payment/verify must never lose the transaction.
      // Cleared on verify success, definitive failure, or user cancel.
      await GatewayPaymentService.savePendingPayment(
        gateway: _method!,
        transactionUuid: txnUuid,
        subId: '${initRes['subId'] ?? ''}',
        purchaseType: purchaseType,
        planId: d.flow == 'plan' ? '${d.plan!['id']}' : null,
        planName: d.flow == 'plan' ? '${d.plan!['name'] ?? ''}' : null,
        itemId: d.flow == 'plan' ? null : itemId,
        itemTitle: d.flow == 'plan' ? null : itemTitle,
      );
      if (_method == 'esewa') {
        await _runEsewaFlow(
          d,
          initRes,
          purchaseType: purchaseType,
          planId: d.flow == 'plan' ? '${d.plan!['id']}' : null,
          itemId: d.flow == 'plan' ? null : itemId,
          contentType: d.flow == 'content' ? d.contentType : null,
          contentUnitId: d.flow == 'content' ? d.contentUnitId : null,
        );
      } else {
        await _runKhaltiFlow(
          d,
          initRes,
          purchaseType: purchaseType,
          planId: d.flow == 'plan' ? '${d.plan!['id']}' : null,
          itemId: d.flow == 'plan' ? null : itemId,
          contentType: d.flow == 'content' ? d.contentType : null,
          contentUnitId: d.flow == 'content' ? d.contentUnitId : null,
        );
      }
    } on GatewayException catch (e) {
      if (mounted) {
        showToast(context, e.message, ToastVariant.error);
      }
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Could not start payment. Please try again.',
                'भुक्तानी सुरु हुन सकेन। कृपया पुनः प्रयास गर्नुहोस्।'),
            ToastVariant.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _paying = false;
          _activeTransactionUuid = '';
          _activePurchaseType = 'subscription';
        });
      }
    }
  }

  /// eSewa: in-app webview auto-POSTs the worker-signed form, intercepts the
  /// success/failure redirects, then the worker verifies server-side.
  Future<void> _runEsewaFlow(
    _CheckoutData d,
    Map<String, dynamic> initRes, {
    required String purchaseType,
    String? planId,
    String? itemId,
    String? contentType,
    String? contentUnitId,
  }) async {
    final esewa = initRes['esewa'] is Map
        ? Map<String, dynamic>.from(initRes['esewa'] as Map)
        : <String, dynamic>{};
    final endpoint = '${esewa['endpoint'] ?? ''}';
    final rawFields = esewa['fields'];
    final fields = <String, String>{};
    if (rawFields is Map) {
      rawFields.forEach((k, v) => fields['$k'] = '$v');
    }
    final transactionUuid = '${initRes['transactionUuid'] ?? ''}';
    final testMode = initRes['testMode'] == true;
    if (endpoint.isEmpty || fields.isEmpty || transactionUuid.isEmpty) {
      showToast(
          context,
          AppLanguage.tr('eSewa is not configured correctly. Please use QR Method.',
              'eSewa सही रूपमा कन्फिगर गरिएको छैन। कृपया QR विधि प्रयोग गर्नुहोस्।'),
          ToastVariant.error);
      return;
    }

    final result = await Navigator.of(context).push<EsewaWebResult>(
      MaterialPageRoute(
        builder: (_) => EsewaWebViewScreen(
          endpoint: endpoint,
          fields: fields,
          testMode: testMode,
          transactionUuid: transactionUuid,
          gateway: 'esewa',
          purchaseType: purchaseType,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null && result.status == 'expired') {
      // The 15-minute session lapsed: the webview already asked the worker
      // to cancel; just reset local state and tell the user.
      await GatewayPaymentService.clearPendingPayment();
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr(
              'Payment session expired.', 'भुक्तानी समय समाप्त भयो।'),
          ToastVariant.warning);
      return;
    }
    if (result == null || result.status == 'cancelled') {
      // User backed out: fire-and-forget server cancel (never block the UI
      // on it — the toast must show within a second even on bad network),
      // then reset local state immediately.
      unawaited(GatewayPaymentService.cancelPayment(
          gateway: 'esewa',
          transactionUuid: transactionUuid,
          purchaseType: purchaseType));
      await GatewayPaymentService.clearPendingPayment();
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr('Payment cancelled.', 'भुक्तानी रद्द गरियो।'),
          ToastVariant.info);
      return;
    }
    if (result.status == 'failure') {
      await GatewayPaymentService.clearPendingPayment();
      if (!mounted) return;
      await showGatewayFailurePopup(
        context,
        message: result.message ??
            AppLanguage.tr(
                'Payment was not completed.', 'भुक्तानी पूरा भएन।'),
        onRetry: () => _startGatewayPayment(d),
      );
      return;
    }
    // success → verifying overlay → worker verification.
    await _verifyWithOverlay(
      d,
      gateway: 'esewa',
      purchaseType: purchaseType,
      planId: planId,
      itemId: itemId,
      contentType: contentType,
      contentUnitId: contentUnitId,
      proof: {
        'transactionUuid': transactionUuid,
        'esewaData': result.data,
      },
    );
  }

  /// Khalti: official SDK (in-app webview), then worker-side verification.
  Future<void> _runKhaltiFlow(
    _CheckoutData d,
    Map<String, dynamic> initRes, {
    required String purchaseType,
    String? planId,
    String? itemId,
    String? contentType,
    String? contentUnitId,
  }) async {
    final kh = initRes['khalti'] is Map
        ? Map<String, dynamic>.from(initRes['khalti'] as Map)
        : <String, dynamic>{};
    final pidx = '${kh['pidx'] ?? ''}';
    final paymentUrl = '${kh['paymentUrl'] ?? ''}';
    final publicKey = '${kh['publicKey'] ?? ''}';
    final transactionUuid = '${initRes['transactionUuid'] ?? ''}';
    final testMode = initRes['testMode'] == true;
    if (pidx.isEmpty || paymentUrl.isEmpty || publicKey.isEmpty) {
      showToast(
          context,
          AppLanguage.tr('Khalti is not configured correctly. Please use QR Method.',
              'Khalti सही रूपमा कन्फिगर गरिएको छैन। कृपया QR विधि प्रयोग गर्नुहोस्।'),
          ToastVariant.error);
      return;
    }

    final completer = Completer<Map<String, String>?>();
    // The Khalti SDK only auto-detects the payment return (firing onReturn
    // and its own verify → onPaymentResult) when the payment URL carries
    // return_url as a query parameter. Khalti's payment_url lacks it, so
    // append it explicitly — otherwise the user gets stuck on the
    // "Payment received" page with no automatic return.
    const khaltiReturnUrl =
        'https://loksewa-push-worker.loksewasolutionapi.workers.dev/payments/khalti/return';
    final paymentUrlWithReturn =
        '$paymentUrl${paymentUrl.contains('?') ? '&' : '?'}return_url=${Uri.encodeComponent(khaltiReturnUrl)}';
    late final Khalti khalti;
    try {
      khalti = await Khalti.init(
        payConfig: KhaltiPayConfig(
          publicKey: publicKey,
          pidx: pidx,
          paymentUrl: paymentUrlWithReturn,
          environment: testMode ? Environment.test : Environment.prod,
        ),
        onPaymentResult: (paymentResult, kh) {
          // Complete BEFORE closing: close() pops the page, which fires
          // kpgDisposed — completing first keeps the payment result.
          final resultData = {
            'pidx': paymentResult.payload?.pidx ?? pidx,
            'transactionId': paymentResult.payload?.transactionId ?? '',
            'status': paymentResult.payload?.status ?? '',
          };
          if (!completer.isCompleted) {
            completer.complete(resultData);
          }
          kh.close(context);
        },
        onReturn: () {
          // Khalti redirected to our return_url in-app: the payment finished
          // on Khalti's side. The SDK now runs its own verify(pidx) and
          // routes to onPaymentResult/onMessage automatically — nothing to
          // do here except let it proceed. Fully automatic, no user action.
        },
        onMessage: (kh, {statusCode, description, event, needsPaymentConfirmation}) {
          if (completer.isCompleted) return;
          // User dismissed the Khalti page without paying.
          if (event == KhaltiEvent.kpgDisposed) {
            completer.complete(null);
            return;
          }
          // Any other SDK-side issue (e.g. its own verify failed): fall back
          // to the worker, which is the source of truth. Close the Khalti
          // page and let the worker verify the pidx server-side.
          completer.complete({
            'pidx': pidx,
            'transactionId': '',
            'status': 'sdk_fallback',
          });
          kh.close(context);
        },
      );
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Could not open Khalti. Please try again.',
                'Khalti खोल्न सकिएन। कृपया पुनः प्रयास गर्नुहोस्।'),
            ToastVariant.error);
      }
      return;
    }
    if (!mounted) return;
    khalti.open(context);
    // Watchdog: if the Khalti page is dismissed without the SDK firing
    // kpgDisposed (seen on some devices), the completer would hang forever
    // and the pay button would spin forever. When our route is current
    // again but nothing completed, treat it as a user cancel.
    final checkoutRoute = ModalRoute.of(context);
    Timer? watchdog;
    watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (completer.isCompleted) {
        watchdog?.cancel();
        return;
      }
      if (checkoutRoute != null && checkoutRoute.isCurrent) {
        completer.complete(null);
      }
    });
    final res = await completer.future;
    watchdog.cancel();
    if (!mounted) return;
    if (res == null) {
      // User backed out: fire-and-forget server cancel (never block the UI
      // on it), reset local state immediately, toast at once.
      unawaited(GatewayPaymentService.cancelPayment(
          gateway: 'khalti',
          transactionUuid: transactionUuid,
          purchaseType: purchaseType));
      await GatewayPaymentService.clearPendingPayment();
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr('Payment cancelled.', 'भुक्तानी रद्द गरियो।'),
          ToastVariant.info);
      return;
    }
    await _verifyWithOverlay(
      d,
      gateway: 'khalti',
      purchaseType: purchaseType,
      planId: planId,
      itemId: itemId,
      contentType: contentType,
      contentUnitId: contentUnitId,
      proof: {'transactionUuid': transactionUuid, 'pidx': res['pidx']},
    );
  }

  /// Friendly message for a failed verify/recheck response.
  String _verifyErrorMessage(Map<String, dynamic> res) {
    const known = {
      'amount_mismatch',
      'duplicate',
      'payment_not_completed',
      'not_found',
      'gateway_disabled',
      'already_used',
      'order_mismatch',
      'uuid_mismatch',
      'signature_mismatch',
      'product_code_mismatch',
    };
    final reason = res['reason']?.toString();
    if (reason != null && reason.isNotEmpty && reason != 'network_error') {
      return gatewayFailureMessage(reason);
    }
    final error = res['error']?.toString() ?? '';
    if (known.contains(error)) return gatewayFailureMessage(error);
    if (error.isNotEmpty) return error;
    return gatewayFailureMessage(null);
  }

  /// AppModalShell checking popup while the worker verifies with the
  /// gateway, then a premium success/failure state. The app never trusts
  /// its own "payment done" signal — only the worker's verification
  /// activates.
  Future<void> _verifyWithOverlay(
    _CheckoutData d, {
    required String gateway,
    String purchaseType = 'subscription',
    String? planId,
    String? itemId,
    String? contentType,
    String? contentUnitId,
    required Map<String, dynamic> proof,
  }) async {
    if (!mounted) return;
    final isSubscription = purchaseType == 'subscription';
    // Display name for the success popup: plan name, else the item title.
    final successTitle = isSubscription
        ? '${d.plan?['name'] ?? ''}'
        : _checkoutTitle(d);
    final closeVerifying = await showGatewayVerifyingPopup(context);
    Map<String, dynamic> res;
    try {
      res = await GatewayPaymentService.verifyPayment(
        gateway: gateway,
        purchaseType: purchaseType,
        planId: planId,
        itemId: itemId,
        contentType: contentType,
        contentUnitId: contentUnitId,
        couponCode: _couponApplied?.code,
        proof: proof,
      );
    } catch (e) {
      res = {
        'ok': false,
        'error': e is GatewayException
            ? e.message
            : AppLanguage.tr('Verification failed. Please try again.',
                'प्रमाणीकरण असफल भयो। कृपया पुनः प्रयास गर्नुहोस्।')
      };
    }
    if (!mounted) {
      closeVerifying();
      return;
    }
    if (res['ok'] == true) {
      await GatewayPaymentService.clearPendingPayment();
      // A purchase was just recorded/activated: tell the purchase list and
      // the exam/subject pages to re-read their data (no manual refresh).
      PurchaseRefreshBus.bump();
      if (isSubscription) {
        // Real-time profile update WHILE the verifying popup is still up, so
        // the profile pill flips Free -> plan name instantly and the user
        // never sees a blank gap between the popups.
        final uid = AuthService.currentUser?.uid;
        if (uid != null) {
          try {
            await ProfileStore.instance.load(uid, refresh: true);
          } catch (_) {}
        }
        if (!mounted) {
          closeVerifying();
          return;
        }
      }
      // The worker returns the purchase doc id in `subscriptionId` for every
      // purchase kind (naming is historical).
      final purchaseId = '${res['subscriptionId'] ?? ''}';
      // Direct swap: verifying out, success in — no intermediate frame.
      closeVerifying();
      if (!mounted) return;
      await showGatewaySuccessPopup(
        context,
        planName: successTitle,
        onNavigate: () {
          if (isSubscription) {
            // Pop back to the plans page, PRESERVING the original stack
            // (Profile stays underneath). Then push the detail on top.
            // Result: Profile -> Plans -> Detail. Back goes Detail -> Plans
            // -> Profile; the app never closes and never returns to checkout.
            // (context.go would wipe the stack and lose Profile.)
            final router = GoRouter.of(context);
            while (router.routerDelegate.currentConfiguration.last
                        .matchedLocation !=
                    '/subscription' &&
                context.canPop()) {
              context.pop();
            }
            if (purchaseId.isNotEmpty) {
              context.push('/subscription/$purchaseId');
            }
            return;
          }
          // Exam/content: close the checkout, then open the purchase's
          // request page (unified timeline + problem section UI).
          if (context.canPop()) context.pop();
          if (purchaseId.isEmpty) {
            context.push('/purchase-details');
          } else if (purchaseType == 'exam') {
            context.push('/subscription/exam-purchase/$purchaseId');
          } else {
            context.push('/purchase-details/content/$purchaseId');
          }
        },
      );
    } else {
      closeVerifying();
      if (!mounted) return;
      await GatewayPaymentService.clearPendingPayment();
      if (!mounted) return;
      await showGatewayFailurePopup(
        context,
        message: _verifyErrorMessage(res),
        onRetry: () => _startGatewayPayment(d),
      );
    }
  }

  // ------------------------------------------------------------------ QR

  Future<void> _handleDownloadQr(String qrUrl) async {
    if (qrUrl.isEmpty) {
      showToast(
          context,
          AppLanguage.tr('QR image is not configured yet.',
              'QR तस्बिर अझै कन्फिगर गरिएको छैन।'),
          ToastVariant.info);
      return;
    }
    setState(() => _downloadingQr = true);
    try {
      final res = await http
          .get(Uri.parse(qrUrl))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('QR download failed');
      // Same convention as the Keep Notes backup export: Downloads folder
      // (app documents fallback), then the share sheet so the file can be
      // saved to the gallery from there.
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_qrDownloadName');
      await file.writeAsBytes(res.bodyBytes);
      await Share.shareXFiles([XFile(file.path)], text: _qrDownloadName);
      if (mounted) {
        showToast(context,
            AppLanguage.tr('QR code saved', 'QR कोड सुरक्षित गरियो'),
            ToastVariant.success);
      }
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Could not download the QR code.',
                'QR कोड डाउनलोड गर्न सकिएन।'),
            ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _downloadingQr = false);
    }
  }

  Future<void> _handleCopyBankField(String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      showToast(
          context, AppLanguage.tr('Copied', 'कपी गरियो'), ToastVariant.success);
    }
  }

  // -------------------------------------------------------------- receipt

  Future<void> _pickScreenshot() async {
    try {
      final bytes = await ScreenshotPicker.pickImage();
      if (bytes != null && mounted) setState(() => _screenshotBytes = bytes);
    } on ScreenshotPickerUnavailable {
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr('Image picker is not available in this build yet',
              'तस्बिर छान्ने सुविधा यो बिल्डमा अझै उपलब्ध छैन'),
          ToastVariant.error);
    } catch (_) {
      if (!mounted) return;
      showToast(context,
          AppLanguage.tr('Could not pick the image', 'तस्बिर छान्न सकिएन'),
          ToastVariant.error);
    }
  }

  Future<String?> _uploadScreenshot() async {
    final bytes = _screenshotBytes;
    if (bytes == null) return null;
    setState(() {
      _uploadingScreenshot = true;
      _uploadProgress = 0;
    });
    try {
      return await CloudinaryUploader.uploadImage(bytes,
          onProgress: (f) {
        if (mounted) setState(() => _uploadProgress = f);
      });
    } finally {
      if (mounted) setState(() => _uploadingScreenshot = false);
    }
  }

  /// Result of the payment submit work: the popup stays open on failure
  /// (inline error + retry) and only closes on success or user cancel.

  Future<_SubmitOutcome?> _showSubmitPopup(_CheckoutData d) {
    bool busy = false;
    String? error;
    return AppModalShell.show<_SubmitOutcome>(
      context: context,
      builder: (ctx) {
        final pal = ExpoPalette.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setPopupState) {
            return AppModalShell(
              maxWidth: 340,
              tagLabel: AppLanguage.tr('Payment', 'भुक्तानी'),
              accent: pal.primary,
              accentMid: pal.info,
              accentLight: pal.info.withValues(alpha: 0x33 / 0xFF),
              tagColor: pal.primary,
              onClose: busy
                  ? () {}
                  : () => Navigator.of(ctx).pop(null),
              icon: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: pal.primary,
                ),
                child: const Icon(Icons.payments_outlined,
                    size: 28, color: Colors.white),
              ),
              title: Text(
                AppLanguage.tr('Submit Payment', 'भुक्तानी पेश गर्नुहोस्'),
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
                children: [
                  Text(
                    AppLanguage.tr(
                        'Submit your payment details for review? An admin will verify and activate your subscription shortly.',
                        'समीक्षाको लागि आफ्नो भुक्तानी विवरण पेश गर्ने हो? एड्मिनले प्रमाणित गरेपछि तपाईंको सदस्यता सक्रिय हुनेछ।'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF475569),
                      height: 1.5,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFDC2626),
                        height: 1.4,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
              footer: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(ctx).pop(null),
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
                      onPressed: busy
                          ? null
                          : () async {
                              setPopupState(() {
                                busy = true;
                                error = null;
                              });
                              final outcome = await _performSubmit(d);
                              if (!ctx.mounted) return;
                              if (outcome.ok) {
                                Navigator.of(ctx).pop(outcome);
                              } else {
                                setPopupState(() {
                                  busy = false;
                                  error = outcome.error;
                                });
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: pal.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(AppLanguage.tr(
                              'Submit Payment', 'भुक्तानी पेश गर्नुहोस्')),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Owns the whole submit UX: popup (with in-popup loading + inline error)
  /// then the success toast + navigation on confirmation.
  Future<void> _confirmAndSubmit(_CheckoutData d) async {
    final outcome = await _showSubmitPopup(d);
    if (outcome == null || !mounted) return; // user cancelled / dismissed
    if (!outcome.ok) return; // unreachable: popup stays open on error
    // The request is recorded: refresh the purchase list and premium/lock
    // states on the exam + subject pages without any manual refresh.
    PurchaseRefreshBus.bump();
    showToast(
        context,
        AppLanguage.tr(
            'Payment details submitted! Your subscription is now pending approval.',
            'भुक्तानी विवरण पेश गरियो! तपाईंको सदस्यता अब स्वीकृतिको प्रतीक्षामा छ।'),
        ToastVariant.success);
    if (outcome.examPurchaseId != null) {
      context.pushReplacement(
          '/subscription/exam-purchase/${outcome.examPurchaseId}?source=exam');
    } else if (outcome.contentPurchaseId != null) {
      context.pushReplacement(
          '/purchase-details/content/${outcome.contentPurchaseId}?source=content');
    } else {
      context.pushReplacement('/subscription');
    }
  }

  /// The actual submit work (no UI side effects): returns the outcome so the
  /// popup can stay open with an inline error on failure.
  Future<_SubmitOutcome> _performSubmit(_CheckoutData d) async {
    String fail(String en, String ne) => AppLanguage.tr(en, ne);
    try {
      final uid = AuthService.currentUser?.uid ?? '';
      final purchasable = _purchasable(d);
      final method = _method;
      if (uid.isEmpty || purchasable == null || method == null) {
        return _SubmitOutcome(
            ok: false,
            error: fail('Could not submit your payment. Please try again.',
                'तपाईंको भुक्तानी पेश गर्न सकिएन। फेरि प्रयास गर्नुहोस्।'));
      }
      // One active review request per user/exam (or content) — reuse the
      // pending one instead of uploading another receipt.
      if (d.flow == 'exam' && d.exam != null) {
        final existing =
            await fetchPendingExamPurchase(uid, '${d.exam!['id'] ?? ''}');
        if (existing != null) {
          return _SubmitOutcome(ok: true, examPurchaseId: existing.id);
        }
      }
      if (d.flow == 'content' && d.content != null) {
        final existing = await fetchPendingContentPurchase(
            uid, d.contentType ?? '', d.contentId ?? '');
        if (existing != null) {
          return _SubmitOutcome(ok: true, contentPurchaseId: existing.id);
        }
      }

      final screenshotUrl = await _uploadScreenshot();
      if (screenshotUrl == null) {
        return _SubmitOutcome(
            ok: false,
            error: fail('Payment screenshot is required.',
                'भुक्तानीको स्क्रिनसट आवश्यक छ।'));
      }

      final user = AuthService.currentUser;
      final userName =
          '${d.userDoc?['name'] ?? ''}'.isNotEmpty
              ? '${d.userDoc?['name']}'
              : user?.displayName;
      final userEmail =
          '${d.userDoc?['email'] ?? ''}'.isNotEmpty
              ? '${d.userDoc?['email']}'
              : user?.email;
      final customerMessage = _msgCtrl.text.trim().isEmpty
          ? null
          : _msgCtrl.text.trim();
      final finalAmount =
          _couponApplied?.discountedAmount ?? _originalAmount(d);

      String? submittedExamPurchaseId;
      String? submittedContentPurchaseId;
      if (d.flow == 'exam' && d.exam != null) {
        final exam = d.exam!;
        submittedExamPurchaseId = await submitExamPurchase(
          SubmitExamPurchaseInput(
            uid: uid,
            userName: userName,
            userEmail: userEmail,
            courseId: '${exam['courseId'] ?? ''}'.isEmpty
                ? null
                : '${exam['courseId']}',
            courseName: d.courseName,
            subcourseId: '${exam['subcourseId'] ?? ''}'.isEmpty
                ? null
                : '${exam['subcourseId']}',
            subcourseName: d.subcourseName,
            examSetId: '${exam['id'] ?? ''}',
            examTitle: '${exam['title'] ?? ''}',
            examContentType: '${exam['contentType'] ?? ''}',
            amount: finalAmount,
            transactionRef: _refCtrl.text.trim(),
            screenshotUrl: screenshotUrl,
            customerMessage: customerMessage,
            couponCode: _couponApplied?.code,
          ),
        );
      } else if (d.flow == 'content' && d.content != null) {
        final content = d.content!;
        final contentType = d.contentType ?? '';
        final contentId = d.contentId ?? '';
        final contentSubjectId = d.contentSubjectId ?? '';
        final contentUnitId = d.contentUnitId ?? '';
        submittedContentPurchaseId = await submitContentPurchase(
          SubmitContentPurchaseInput(
            uid: uid,
            userName: userName,
            userEmail: userEmail,
            courseId: '${content['courseId'] ?? d.userDoc?['courseId'] ?? ''}'
                    .isEmpty
                ? null
                : '${content['courseId'] ?? d.userDoc?['courseId']}',
            subcourseId:
                '${content['subcourseId'] ?? d.userDoc?['subcourseId'] ?? ''}'
                        .isEmpty
                    ? null
                    : '${content['subcourseId'] ?? d.userDoc?['subcourseId']}',
            contentType: contentType,
            contentId: contentId,
            contentTitle: '${content['title'] ?? ''}',
            contentTitleNe: '${content['titleNe'] ?? ''}',
            subjectId: contentType == 'subject' ? contentId : contentSubjectId,
            unitId: contentType == 'unit'
                ? contentId
                : contentType == 'chapter'
                    ? (contentUnitId.isEmpty ? null : contentUnitId)
                    : null,
            amount: finalAmount,
            transactionRef: _refCtrl.text.trim(),
            screenshotUrl: screenshotUrl,
            customerMessage: customerMessage,
            couponCode: _couponApplied?.code,
          ),
        );
      } else if (d.plan != null) {
        await _submitPlan(
          d,
          uid: uid,
          userName: userName,
          userEmail: userEmail,
          customerMessage: customerMessage,
          screenshotUrl: screenshotUrl,
          finalAmount: finalAmount,
          method: method,
        );
      }
      return _SubmitOutcome(
        ok: true,
        examPurchaseId: submittedExamPurchaseId,
        contentPurchaseId: submittedContentPurchaseId,
      );
    } catch (e) {
      // Log the real error for diagnosis; the user sees the friendly text.
      debugPrint('checkout submit failed: $e');
      return _SubmitOutcome(
          ok: false,
          error: fail('Could not submit your payment. Please try again.',
              'तपाईंको भुक्तानी पेश गर्न सकिएन। फेरि प्रयास गर्नुहोस्।'));
    }
  }

  /// Mirrors submitPayment() + the coupon usage increment.
  Future<void> _submitPlan(
    _CheckoutData d, {
    required String uid,
    required String? userName,
    required String? userEmail,
    required String? customerMessage,
    required String screenshotUrl,
    required num finalAmount,
    required String method,
  }) async {
    final token = await AuthService.getValidIdToken();
    final plan = d.plan!;
    final id = '${uid}_${DateTime.now().millisecondsSinceEpoch}';
    await FirestoreRest.setDocument('app_subscriptions/$id', {
      'uid': uid,
      'userName': userName,
      'userEmail': userEmail,
      'planId': plan['id'],
      'planName': plan['name'],
      'billingCycle': plan['billingCycle'],
      'amount': finalAmount,
      'currency': 'NPR',
      'method': method,
      'status': 'pending',
      'transactionRef': _refCtrl.text.trim(),
      'screenshotUrl': screenshotUrl,
      'customerMessage': customerMessage,
      'adminMessage': null,
      'couponCode': _couponApplied?.code,
      'submittedAt': DateTime.now().toIso8601String(),
      'reviewedAt': null,
      'reviewedBy': null,
      'rejectionReason': null,
      'startDate': null,
      'expiryDate': null,
      'createdAt': FirestoreRest.serverTimestamp(),
      'updatedAt': FirestoreRest.serverTimestamp(),
    }, idToken: token);
    // Index the subscription ID on the user's doc for per-user history.
    // Rules deny LIST queries on app_subscriptions for non-admins, so the
    // app resolves the user's IDs from their own doc and getDocuments each.
    // Best-effort: the subscription itself is saved; index failure only
    // affects the history list (the admin backfill can repair it).
    try {
      final userDoc = await FirestoreRest.getDocument('users/$uid', idToken: token);
      final ids = <String>[
        for (final e in (userDoc?['subscriptionIds'] as List? ?? [])) e.toString(),
      ];
      if (!ids.contains(id)) {
        ids.add(id);
        await FirestoreRest.updateDocument(
            'users/$uid', {'subscriptionIds': ids},
            idToken: token);
      }
    } catch (_) {
      // Best-effort only; never blocks checkout.
    }
    // Fire-and-forget admin push — the subscription request is recorded;
    // never blocks the checkout flow.
    final buyerName = (userName ?? '').trim();
    unawaited(AdminNotifyService.notifyAdmin(
      kind: 'subscription',
      title: 'New Subscription Request 🎫',
      body:
          '${buyerName.isEmpty ? 'Someone' : buyerName} requested the ${plan['name']} plan — Rs. $finalAmount',
      deepLink: '/admin/subscriptions/$id',
    ));
    if (_couponApplied != null) {
      await CouponService.incrementCouponUsage(_couponApplied!.code);
      if (uid.isNotEmpty) {
        await CouponService.incrementCouponUsageForUser(
            _couponApplied!.code, uid);
      }
    }
  }

  // -------------------------------------------------------------- preview

  void _openPreview({Uint8List? bytes, String? url}) {
    // Global image viewer: pinch-to-zoom only (no +/- zoom buttons).
    final ImageProvider provider;
    if (bytes != null) {
      provider = MemoryImage(bytes);
    } else if (url != null && url.isNotEmpty) {
      provider = NetworkImage(url);
    } else {
      return;
    }
    showImageViewer(context, provider);
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // System back while a payment is processing → confirm dialog
    // ("Exit Payment?"). In-app touches are blocked by the FULL-SCREEN dim
    // overlay below (covers the header too), so no state can change
    // mid-processing (user requirement).
    return PopScope(
      canPop: !_paying,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_paying) return;
        final exit = await _confirmExitPayment();
        if (exit == true && mounted) {
          await _exitPaying();
        }
      },
      child: Scaffold(
      body: Stack(
        children: [
      Column(
        children: [
          FutureBuilder<_CheckoutData>(
            future: _future,
            builder: (context, snap) => SubpageHeader(
              title: snap.hasData
                  ? _checkoutTitle(snap.data!)
                  : AppLanguage.tr('Subscription Details', 'सदस्यता विवरण'),
            ),
          ),
          Expanded(
            child: FutureBuilder<_CheckoutData>(
            future: _future,
            builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading Subscription...',
                        'सदस्यता लोड हुँदैछ...'),
                  );
                }
                if (snap.hasError || _purchasable(snap.data!) == null) {
                  if (snap.hasError) {
                    debugPrint('checkout _load FAILED error=${snap.error}');
                  } else {
                    final d = snap.data!;
                    debugPrint('checkout _load purchasable null: flow=${d.flow} '
                        'contentType=${d.contentType} contentId=${d.contentId} '
                        'examId=${d.examId} planId=${d.plan?['id']}');
                  }
                  return _notFound();
                }
                final d = snap.data!;
                final finalAmount =
                    _couponApplied?.discountedAmount ?? _originalAmount(d);
                final settingsAvailable = d.settingsAvailable;
                final esewaReady =
                    settingsAvailable && d.settings['esewa']['enabled'] == true;
                final khaltiReady =
                    settingsAvailable && d.settings['khalti']['enabled'] == true;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _summaryCard(d, finalAmount),
                      const SizedBox(height: 16),
                      _couponSection(d),
                      const SizedBox(height: 16),
                      _methodPicker(
                          settingsAvailable, esewaReady, khaltiReady),
                      const SizedBox(height: 16),
                      if (_method == 'esewa' || _method == 'khalti')
                        SyllabusEntrance(
                          delayMs: 180,
                          child: _gatewayBlock(d),
                        )
                      else if (_method == 'qr')
                        SyllabusEntrance(
                          delayMs: 180,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _qrSection(d),
                              const SizedBox(height: 16),
                              _receiptForm(),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
          // FULL-SCREEN dim overlay while a gateway payment is being
          // processed — covers the header too (v1.0.110: the header was
          // left undimmed in light mode). No popup card — the Pay button
          // itself shows the loading spinner + "Starting secure payment…".
          // Blocks ALL touches (header, coupon field, method picker, etc.).
          if (_paying)
            const ModalBarrier(
                dismissible: false, color: Colors.black54),
        ],
      ),
      ),
    );
  }

  /// "Exit Payment?" confirm shown when the system back button is pressed
  /// while a payment is processing. Returns true when the user confirms.
  Future<bool?> _confirmExitPayment() {
    return AppModalShell.show<bool>(
      context: context,
      builder: (_) => AppModalShell(
        icon: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFDE6E00).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.exit_to_app,
              size: 26, color: Color(0xFFDE6E00)),
        ),
        tagLabel: AppLanguage.tr('PAYMENT IN PROGRESS', 'भुक्तानी जारी छ'),
        title: Text(
          AppLanguage.tr('Exit Payment?', 'भुक्तानीबाट बाहिरिने?'),
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        body: Text(
          AppLanguage.tr(
            'The payment is still processing. If you exit now, it will be cancelled.',
            'भुक्तानी अझै प्रक्रिया हुँदैछ। अहिले बाहिरिनुभयो भने यो रद्द हुनेछ।',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(AppLanguage.tr(
                      'Exit Payment', 'भुक्तानीबाट बाहिरिनुहोस्')),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(AppLanguage.tr('Stay', 'रहनुहोस्')),
                ),
              ),
            ],
          ),
        ),
        onClose: () => Navigator.of(context).pop(false),
      ),
    );
  }

  /// User confirmed exiting a processing payment: fire-and-forget the
  /// server cancel, unlock the UI, and pop the checkout page.
  Future<void> _exitPaying() async {
    final txnUuid = _activeTransactionUuid;
    final purchaseType = _activePurchaseType;
    setState(() {
      _paying = false;
      _activeTransactionUuid = '';
      _activePurchaseType = 'subscription';
    });
    if (txnUuid.isNotEmpty && _method != null && _method != 'qr') {
      unawaited(GatewayPaymentService.cancelPayment(
          gateway: _method!,
          transactionUuid: txnUuid,
          purchaseType: purchaseType));
    }
    if (mounted && context.canPop()) {
      context.pop();
    }
  }

  Widget _notFound() {
    final pal = ExpoPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: pal.textDisabled),
            const SizedBox(height: 12),
            Text(
              AppLanguage.tr('Checkout not available',
                  'चेकआउट उपलब्ध छैन'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: pal.textPrimary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
              ),
              child: Text(AppLanguage.tr('Retry', 'पुनः प्रयास गर्नुहोस्')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(_CheckoutData d, num finalAmount) {
    final pal = ExpoPalette.of(context);
    final original = _originalAmount(d);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border, width: 0.5),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _checkoutTitle(d),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'Rs. ${_money(finalAmount)}',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: pal.primary),
              ),
            ],
          ),
          if (_couponApplied != null)
            Text(
              'Rs. ${_money(original)}',
              style: TextStyle(
                fontSize: 12,
                color: pal.textSecondary,
                decoration: TextDecoration.lineThrough,
              ),
            ),
        ],
      ),
    );
  }

  Widget _couponSection(_CheckoutData d) {
    final pal = ExpoPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLanguage.tr('Coupon Code (optional)', 'कुपन कोड (वैकल्पिक)'),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: pal.textSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _couponCtrl,
                enabled: _couponApplied == null,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_couponApplied != null) {
                    setState(() {
                      _couponApplied = null;
                      _couponError = null;
                    });
                  }
                },
                decoration: _premiumInputDecoration(
                  pal,
                  hintText: AppLanguage.tr(
                      'Enter coupon code', 'कुपन कोड प्रविष्ट गर्नुहोस्'),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_couponApplied != null)
              OutlinedButton(
                onPressed: () => setState(() {
                  _couponApplied = null;
                  _couponCtrl.clear();
                  _couponError = null;
                }),
                child: Text(
                    AppLanguage.tr('Remove', 'हटाउनुहोस्')),
              )
            else
              OutlinedButton(
                onPressed: (_validatingCoupon ||
                        _couponCtrl.text.trim().isEmpty)
                    ? null
                    : () => _handleApplyCoupon(d),
                child: _validatingCoupon
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : Text(AppLanguage.tr('Apply', 'लागू गर्नुहोस्')),
              ),
          ],
        ),
        if (_couponApplied != null)
          SyllabusEntrance(
            delayMs: 60,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.success.withValues(alpha: 0x12 / 0xFF),
                border: Border.all(color: pal.success),
                borderRadius: BorderRadius.circular(ExpoRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_offer_outlined,
                          size: 16, color: pal.success),
                      const SizedBox(width: 6),
                      Text(
                        '${_couponApplied!.code} ${AppLanguage.tr('applied', 'लागू भयो')}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: pal.success),
                      ),
                    ],
                  ),
                  if (_couponApplied!.label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _couponApplied!.label,
                        style: TextStyle(
                            fontSize: 12, color: pal.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          )
        else if (_couponError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _couponError!,
              style: TextStyle(fontSize: 12, color: pal.danger),
            ),
          ),
      ],
    );
  }

  Widget _methodPicker(
      bool settingsAvailable, bool esewaReady, bool khaltiReady) {
    final pal = ExpoPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLanguage.tr(
              'Choose a Payment Method', 'भुक्तानी विधि छान्नुहोस्'),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: pal.textSecondary),
        ),
        const SizedBox(height: 8),
        _MethodCard(
          logoUrl: _esewaLogo,
          label: 'eSewa',
          color: const Color(0xFF60BB46),
          ready: esewaReady,
          settingsAvailable: settingsAvailable,
          selected: _method == 'esewa',
          onPress: () {
            if (!settingsAvailable) {
              showToast(
                  context,
                  AppLanguage.tr(
                      'Payment settings are temporarily unavailable. Please use QR Method or try again later.',
                      'भुक्तानी सेटिङ अहिले अस्थायी रूपमा उपलब्ध छैन। कृपया QR विधि प्रयोग गर्नुहोस् वा केही समयपछि पुनः प्रयास गर्नुहोस्।'),
                  ToastVariant.info);
            } else if (esewaReady) {
              setState(() => _method = 'esewa');
            } else {
              showToast(
                  context,
                  AppLanguage.tr("This payment method isn't available yet.",
                      'यो भुक्तानी विधि अझै उपलब्ध छैन।'),
                  ToastVariant.info);
            }
          },
        ),
        const SizedBox(height: 8),
        _MethodCard(
          logoUrl: _khaltiLogo,
          label: 'Khalti',
          color: const Color(0xFF5C2D91),
          ready: khaltiReady,
          settingsAvailable: settingsAvailable,
          selected: _method == 'khalti',
          onPress: () {
            if (!settingsAvailable) {
              showToast(
                  context,
                  AppLanguage.tr(
                      'Payment settings are temporarily unavailable. Please use QR Method or try again later.',
                      'भुक्तानी सेटिङ अहिले अस्थायी रूपमा उपलब्ध छैन। कृपया QR विधि प्रयोग गर्नुहोस् वा केही समयपछि पुनः प्रयास गर्नुहोस्।'),
                  ToastVariant.info);
            } else if (khaltiReady) {
              setState(() => _method = 'khalti');
            } else {
              showToast(
                  context,
                  AppLanguage.tr("This payment method isn't available yet.",
                      'यो भुक्तानी विधि अझै उपलब्ध छैन।'),
                  ToastVariant.info);
            }
          },
        ),
        const SizedBox(height: 8),
        _MethodCard(
          icon: Icons.qr_code_outlined,
          label: AppLanguage.tr('QR Method (Manual)', 'QR विधि (म्यानुअल)'),
          color: const Color(0xFF0EA5E9),
          ready: true,
          settingsAvailable: true,
          selected: _method == 'qr',
          onPress: () => setState(() => _method = 'qr'),
        ),
      ],
    );
  }

  Widget _gatewayBlock(_CheckoutData d) {
    final pal = ExpoPalette.of(context);
    final gatewayName = _method == 'esewa' ? 'eSewa' : 'Khalti';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Premium gradient pay button with a security reassurance row.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.accent,
                AppColors.accent.withValues(alpha: 0.78),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _paying ? null : () => _startGatewayPayment(d),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_paying)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    else
                      const Icon(Icons.lock_outline,
                          size: 17, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      _paying
                          ? AppLanguage.tr('Starting secure payment…',
                              'सुरक्षित भुक्तानी सुरु हुँदैछ…')
                          : AppLanguage.tr('Pay securely with $gatewayName',
                              '$gatewayName बाट सुरक्षित भुक्तानी गर्नुहोस्'),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.verified_user_outlined,
                size: 14, color: pal.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                AppLanguage.tr(
                    'Payment opens inside the app. Verified securely — no screenshot needed.',
                    'भुक्तानी एपभित्रै खुल्छ। सुरक्षित रूपमा प्रमाणित हुन्छ — screenshot आवश्यक छैन।'),
                style: TextStyle(fontSize: 12, color: pal.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _qrSection(_CheckoutData d) {
    final pal = ExpoPalette.of(context);
    final manual = d.settings['manual'] as Map<String, dynamic>;
    final qrUrl = '${manual['qrImageUrl'] ?? ''}';
    final bankDetails = '${manual['bankDetails'] ?? ''}';
    final instructions = '${manual['instructions'] ?? ''}';
    final hasAny =
        qrUrl.isNotEmpty || bankDetails.isNotEmpty || instructions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasAny)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.surfaceAlt,
              border: Border.all(color: pal.border, width: 0.5),
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: pal.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLanguage.tr(
                            'Manual payment details are not available yet.',
                            'म्यानुअल भुक्तानी विवरण अहिले उपलब्ध छैन।'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        AppLanguage.tr(
                            'Please contact the administrator before making a manual payment.',
                            'म्यानुअल भुक्तानी गर्नुअघि एड्मिनसँग सम्पर्क गर्नुहोस्।'),
                        style: TextStyle(
                            fontSize: 12, color: pal.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (qrUrl.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.surface,
              border: Border.all(color: pal.border, width: 0.5),
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
            ),
            child: Column(
              children: [
                Text(
                  AppLanguage.tr(
                      'Scan QR to Pay', 'भुक्तानीको लागि QR स्क्यान गर्नुहोस्'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: Text(
                    AppLanguage.tr(
                        'Use eSewa, Khalti or any Fonepay-enabled banking app to scan the QR code below.',
                        'तलको QR कोड स्क्यान गर्न eSewa, Khalti वा कुनै पनि Fonepay-सक्षम बैंकिङ एप प्रयोग गर्नुहोस्।'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: pal.textSecondary),
                  ),
                ),
                GestureDetector(
                  onTap: () => _openPreview(url: qrUrl),
                  child: _QrImage(
                    key: ValueKey(qrUrl),
                    url: qrUrl,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _downloadingQr
                      ? null
                      : () => _handleDownloadQr(qrUrl),
                  icon: Icon(_downloadingQr
                      ? Icons.cloud_download_outlined
                      : Icons.download_outlined,
                      size: 16,
                      color: pal.primary),
                  label: Text(
                    _downloadingQr
                        ? AppLanguage.tr(
                            'Downloading…', 'डाउनलोड हुँदैछ…')
                        : AppLanguage.tr(
                            'Download QR', 'QR डाउनलोड गर्नुहोस्'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: pal.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: pal.primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ExpoRadius.pill),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (bankDetails.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.surface,
              border: Border.all(color: pal.border, width: 0.5),
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color:
                            pal.primary.withValues(alpha: 0x18 / 0xFF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.business_outlined,
                          size: 20, color: pal.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLanguage.tr(
                                'Bank Details', 'बैंक विवरण'),
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            AppLanguage.tr(
                                'Use these details for a direct transfer.',
                                'प्रत्यक्ष बैंक ट्रान्सफरका लागि यी विवरण प्रयोग गर्नुहोस्।'),
                            style: TextStyle(
                                fontSize: 12,
                                color: pal.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.shield_outlined,
                        size: 20, color: pal.success),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: pal.surfaceAlt,
                    borderRadius:
                        BorderRadius.circular(ExpoRadius.md),
                  ),
                  child: Column(
                    children: [
                      for (final line in bankDetails.split('\n'))
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin:
                                    const EdgeInsets.only(top: 7),
                                decoration: BoxDecoration(
                                  color: pal.primary,
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _handleCopyBankField(bankDetails),
                    icon: Icon(Icons.copy_outlined,
                        size: 16, color: pal.primary),
                    label: Text(
                      AppLanguage.tr('Copy all bank details',
                          'सबै बैंक विवरण कपी गर्नुहोस्'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: pal.primary),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: pal.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ExpoRadius.pill),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (instructions.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: pal.surfaceAlt,
              border: Border.all(color: pal.border, width: 0.5),
              borderRadius: BorderRadius.circular(ExpoRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color:
                            pal.primary.withValues(alpha: 0x20 / 0xFF),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(Icons.list_outlined,
                          size: 18, color: pal.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLanguage.tr(
                                'Instructions', 'निर्देशनहरू'),
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            AppLanguage.tr(
                                'Complete these steps after payment.',
                                'भुक्तानीपछि यी चरणहरू पूरा गर्नुहोस्।'),
                            style: TextStyle(
                                fontSize: 12,
                                color: pal.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._instructionSteps(instructions).map(
                  (s) => _timelineRow(s, pal),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Numbered steps with the original line index preserved (React numbers
  /// with the raw map index, including blank lines).
  List<_Step> _instructionSteps(String instructions) {
    final lines = instructions.split('\n');
    final steps = <_Step>[];
    for (var i = 0; i < lines.length; i++) {
      final step =
          lines[i].trim().replaceFirst(RegExp(r'^\d+[.)-]\s*'), '');
      if (step.isEmpty) continue;
      steps.add(_Step(number: i + 1, text: step, last: i == lines.length - 1));
    }
    return steps;
  }

  Widget _timelineRow(_Step step, ExpoPalette pal) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pal.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  '${step.number}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              if (!step.last)
                Container(
                  width: 2,
                  height: 18,
                  margin: const EdgeInsets.only(top: 3),
                  color: pal.primary.withValues(alpha: 0x35 / 0xFF),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              step.text,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  /// Premium curved input decoration for the payment form: rounded 16px
  /// corners, subtle filled background, clear focused border. Labels, hints
  /// and validation stay exactly as before — only the decoration changes.
  InputDecoration _premiumInputDecoration(
    ExpoPalette pal, {
    String? labelText,
    String? hintText,
    String? helperText,
    bool isDense = false,
  }) {
    const radius = BorderRadius.all(Radius.circular(16));
    final idleBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: pal.border),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      isDense: isDense,
      filled: true,
      fillColor: pal.surfaceAlt.withValues(alpha: 0.55),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: idleBorder,
      enabledBorder: idleBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: pal.primary, width: 1.6),
      ),
    );
  }

  Widget _receiptForm() {
    final pal = ExpoPalette.of(context);
    final canSubmit =
        _refCtrl.text.trim().isNotEmpty && _screenshotBytes != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _refCtrl,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          decoration: _premiumInputDecoration(
            pal,
            labelText:
                '${AppLanguage.tr('Transaction ID / Reference', 'ट्रान्जेक्सन आईडी / सन्दर्भ')} *',
            helperText: AppLanguage.tr(
                'Enter the transaction ID or remarks shown after your payment.',
                'तपाईंको भुक्तानी पछि देखिएको ट्रान्जेक्सन आईडी वा रिमार्क्स प्रविष्ट गर्नुहोस्।'),
            hintText: AppLanguage.tr(
                'e.g. TXN123456789', 'जस्तै TXN123456789'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              AppLanguage.tr(
                  'Payment Screenshot', 'भुक्तानी स्क्रिनसट'),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: pal.textSecondary),
            ),
            Text(' *',
                style: TextStyle(fontSize: 13, color: pal.danger)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          AppLanguage.tr(
              'Attach a screenshot of your payment as proof — required.',
              'प्रमाणको रूपमा आफ्नो भुक्तानीको स्क्रिनसट संलग्न गर्नुहोस् — आवश्यक।'),
          style:
              TextStyle(fontSize: 12, color: pal.textSecondary),
        ),
        const SizedBox(height: 8),
        if (_screenshotBytes != null)
          GestureDetector(
            onTap: () => _openPreview(bytes: _screenshotBytes),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _screenshotBytes!,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    AppLanguage.tr('Tap to view full screen and zoom',
                        'Full screen मा हेर्न र zoom गर्न थिच्नुहोस्'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: pal.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        if (_uploadingScreenshot) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _uploadProgress,
              minHeight: 8,
              backgroundColor: pal.border,
              valueColor:
                  AlwaysStoppedAnimation<Color>(pal.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${AppLanguage.tr('Uploading screenshot', 'स्क्रिनसट अपलोड हुँदैछ')} ${(_uploadProgress * 100).round()}%',
            style:
                TextStyle(fontSize: 12, color: pal.textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickScreenshot,
          icon: Icon(Icons.image_outlined, size: 16, color: pal.primary),
          label: Text(_screenshotBytes != null
              ? AppLanguage.tr('Edit', 'सम्पादन गर्नुहोस्')
              : AppLanguage.tr(
                  'Payment Screenshot', 'भुक्तानी स्क्रिनसट')),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _msgCtrl,
          maxLines: 3,
          decoration: _premiumInputDecoration(
            pal,
            labelText: AppLanguage.tr(
                'Message (optional)', 'सन्देश (वैकल्पिक)'),
            hintText: AppLanguage.tr(
                "Add a note for the admin, e.g. paid from a family member's account",
                'एड्मिनको लागि नोट थप्नुहोस्, जस्तै परिवारको सदस्यको खाताबाट तिरेको'),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: (_uploadingScreenshot || !canSubmit)
              ? null
              : () async {
                  if (_refCtrl.text.trim().isEmpty) {
                    showToast(
                        context,
                        AppLanguage.tr(
                            'Transaction ID / Reference is required.',
                            'ट्रान्जेक्सन आईडी / सन्दर्भ आवश्यक छ।'),
                        ToastVariant.error);
                    return;
                  }
                  if (_screenshotBytes == null) {
                    showToast(
                        context,
                        AppLanguage.tr('Payment screenshot is required.',
                            'भुक्तानीको स्क्रिनसट आवश्यक छ।'),
                        ToastVariant.error);
                    return;
                  }
                  final d = await _future;
                  if (mounted) await _confirmAndSubmit(d);
                },
          child: Text(
              AppLanguage.tr('Submit Payment', 'भुक्तानी पेश गर्नुहोस्'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _SettingsResult {
  final Map<String, dynamic> settings;
  final bool available;
  const _SettingsResult(this.settings, this.available);
}

class _Step {
  final int number;
  final String text;
  final bool last;
  const _Step({required this.number, required this.text, required this.last});
}

/// Mirrors MethodCard in checkout.tsx: brand logo (or icon tile), label,
/// Coming Soon / settings-unavailable badge, radio indicator.
class _MethodCard extends StatelessWidget {
  final String? logoUrl;
  final IconData? icon;
  final String label;
  final Color color;
  final bool ready;
  final bool settingsAvailable;
  final bool selected;
  final VoidCallback onPress;

  const _MethodCard({
    this.logoUrl,
    this.icon,
    required this.label,
    required this.color,
    required this.ready,
    required this.settingsAvailable,
    required this.selected,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Opacity(
      opacity: settingsAvailable ? (ready ? 1 : 0.55) : 0.7,
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(ExpoRadius.md),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
                color: selected ? color : pal.border, width: 1.5),
            borderRadius: BorderRadius.circular(ExpoRadius.md),
            color: selected
                ? color.withValues(alpha: 0x12 / 0xFF)
                : pal.surface,
          ),
          child: Row(
            children: [
              if (logoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    logoUrl!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0x17 / 0xFF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.payments_outlined,
                          size: 18, color: color),
                    ),
                  ),
                )
              else
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0x17 / 0xFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (!settingsAvailable)
                _badge(
                    pal,
                    AppLanguage.tr(
                        'Settings unavailable', 'सेटिङ उपलब्ध छैन'))
              else if (!ready)
                _badge(
                    pal,
                    AppLanguage.tr('Coming Soon', 'चाँडै आउँदैछ'))
              else
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? color : pal.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(ExpoPalette pal, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: pal.surfaceAlt,
        borderRadius: BorderRadius.circular(ExpoRadius.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: pal.textSecondary),
      ),
    );
  }
}

/// QR image with a loading placeholder until the network image resolves —
/// mirrors the Skeleton overlay + onLoadEnd in QrSection.
class _QrImage extends StatefulWidget {
  final String url;
  const _QrImage({super.key, required this.url});

  @override
  State<_QrImage> createState() => _QrImageState();
}

class _QrImageState extends State<_QrImage> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!_loaded)
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: ExpoPalette.of(context).surfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              widget.url,
              width: 220,
              height: 220,
              fit: BoxFit.contain,
              frameBuilder: (context, child, frame, _) {
                if (frame != null && !_loaded) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _loaded = true);
                  });
                }
                return child;
              },
              errorBuilder: (_, __, ___) => Container(
                width: 220,
                height: 220,
                color: ExpoPalette.of(context).surfaceAlt,
                child: const Center(
                    child: Icon(Icons.qr_code, size: 48)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
