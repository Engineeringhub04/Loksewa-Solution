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
// Selecting eSewa/Khalti shows only a gateway action (the gateway itself is
// still under construction — the Expo app only toasts here, so this screen
// does the same). Manual receipt fields are rendered for QR only. Provider
// secrets are never fetched by this screen.
//
// Writes mirror submitPayment / submitExamPurchase / submitContentPurchase
// exactly (via the existing services), then route to the detail screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/coupon_service.dart';
import 'package:loksewa_solution/services/exam_purchases.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/subpage_header.dart';

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
  bool _submitting = false;
  bool _downloadingQr = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
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
    return {
      'esewa': {'enabled': asBool(esewa['enabled'])},
      'khalti': {'enabled': asBool(khalti['enabled'])},
      'manual': {
        'qrImageUrl':
            pick([manual['qrImageUrl'], d['qrImageUrl'], manual['qrUrl']]),
        'bankDetails': pick([manual['bankDetails'], d['bankDetails']]),
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
    if (type == 'subject') {
      return FirestoreRest.getDocument('app_learning_subjects/$subjectId',
          idToken: token);
    }
    if (type == 'unit') {
      return FirestoreRest.getDocument(
          'app_learning_subjects/$subjectId/units/$contentId',
          idToken: token);
    }
    final path = (unitId != null && unitId.isNotEmpty)
        ? 'app_learning_subjects/$subjectId/units/$unitId/chapters/$contentId'
        : 'app_learning_subjects/$subjectId/chapters/$contentId';
    return FirestoreRest.getDocument(path, idToken: token);
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
      final result = await CouponService.validateCoupon(
          _couponCtrl.text.trim(), category, _originalAmount(d));
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

  /// Opens only the provider checkout. Receipt ID/screenshot submission is
  /// QR-only. Mirrors handleOpenGateway: the gateway itself is still under
  /// construction, so this only toasts like the Expo app does.
  void _handleOpenGateway(_CheckoutData d) {
    if (d.flow == 'exam' || d.plan == null || _method == null || _method == 'qr') {
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
    showToast(
        context,
        AppLanguage.tr(
            'This gateway is enabled in settings, but secure gateway processing is still under construction. Please use QR Method for now.',
            'यो gateway सेटिङमा सक्रिय छ, तर सुरक्षित gateway processing अझै निर्माणाधीन छ। अहिले QR विधि प्रयोग गर्नुहोस्।'),
        ToastVariant.info);
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

  Future<bool> _confirmSubmit() async {
    final ok = await AppModalShell.show<bool>(
      context: context,
      builder: (ctx) {
        final pal = ExpoPalette.of(ctx);
        return AppModalShell(
          maxWidth: 340,
          tagLabel: AppLanguage.tr('Payment', 'भुक्तानी'),
          accent: pal.primary,
          accentMid: pal.info,
          accentLight: pal.info.withValues(alpha: 0x33 / 0xFF),
          tagColor: pal.primary,
          onClose: () => Navigator.of(ctx).pop(false),
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
          body: Text(
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
          footer: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
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
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(AppLanguage.tr(
                      'Submit Payment', 'भुक्तानी पेश गर्नुहोस्')),
                ),
              ),
            ],
          ),
        );
      },
    );
    return ok == true;
  }

  Future<void> _handleSubmitManual(_CheckoutData d) async {
    final uid = AuthService.currentUser?.uid ?? '';
    final purchasable = _purchasable(d);
    final method = _method;
    if (uid.isEmpty || purchasable == null || method == null) return;
    if (_refCtrl.text.trim().isEmpty) {
      showToast(
          context,
          AppLanguage.tr('Transaction ID / Reference is required.',
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
    setState(() => _submitting = true);
    try {
      // One active review request per user/exam (or content) — reuse the
      // pending one instead of uploading another receipt.
      if (d.flow == 'exam' && d.exam != null) {
        final existing =
            await fetchPendingExamPurchase(uid, '${d.exam!['id'] ?? ''}');
        if (existing != null) {
          if (!mounted) return;
          showToast(context,
              AppLanguage.tr('Purchase Pending', 'खरिद समीक्षा हुँदैछ'),
              ToastVariant.info);
          context.pushReplacement(
              '/subscription/exam-purchase/${existing.id}?source=exam');
          return;
        }
      }
      if (d.flow == 'content' && d.content != null) {
        final existing = await fetchPendingContentPurchase(
            uid, d.contentType ?? '', d.contentId ?? '');
        if (existing != null) {
          if (!mounted) return;
          showToast(context,
              AppLanguage.tr('Purchase Pending', 'खरिद समीक्षा हुँदैछ'),
              ToastVariant.info);
          context.pushReplacement(
              '/purchase-details/content/${existing.id}?source=content');
          return;
        }
      }

      final screenshotUrl = await _uploadScreenshot();
      if (screenshotUrl == null) {
        if (mounted) {
          showToast(
              context,
              AppLanguage.tr('Payment screenshot is required.',
                  'भुक्तानीको स्क्रिनसट आवश्यक छ।'),
              ToastVariant.error);
        }
        return;
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
      if (!mounted) return;
      showToast(
          context,
          AppLanguage.tr(
              'Payment details submitted! Your subscription is now pending approval.',
              'भुक्तानी विवरण पेश गरियो! तपाईंको सदस्यता अब स्वीकृतिको प्रतीक्षामा छ।'),
          ToastVariant.success);
      if (submittedExamPurchaseId != null) {
        context.pushReplacement(
            '/subscription/exam-purchase/$submittedExamPurchaseId?source=exam');
      } else if (submittedContentPurchaseId != null) {
        context.pushReplacement(
            '/purchase-details/content/$submittedContentPurchaseId?source=content');
      } else {
        context.pushReplacement('/subscription');
      }
    } catch (_) {
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Could not submit your payment. Please try again.',
                'तपाईंको भुक्तानी पेश गर्न सकिएन। फेरि प्रयास गर्नुहोस्।'),
            ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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
    if (_couponApplied != null) {
      await CouponService.incrementCouponUsage(_couponApplied!.code);
    }
  }

  // -------------------------------------------------------------- preview

  void _openPreview({Uint8List? bytes, String? url}) {
    showDialog(
      context: context,
      barrierColor: const Color(0xFA030712), // rgba(3, 7, 18, 0.98)
      builder: (ctx) => _ImagePreviewDialog(bytes: bytes, url: url),
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
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
    );
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
                decoration: InputDecoration(
                  hintText: AppLanguage.tr(
                      'Enter coupon code', 'कुपन कोड प्रविष्ट गर्नुहोस्'),
                  border: const OutlineInputBorder(),
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
                onPressed:
                    _validatingCoupon ? null : () => _handleApplyCoupon(d),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => _handleOpenGateway(d),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(AppLanguage.tr('Continue to Payment Gateway',
              'भुक्तानी गेटवेमा जानुहोस्')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppLanguage.tr(
              'Complete payment in the gateway. Transaction ID and screenshot are not required here.',
              'Gateway मा भुक्तानी पूरा गर्नुहोस्। यहाँ Transaction ID वा screenshot आवश्यक छैन।'),
          style: TextStyle(fontSize: 12, color: pal.textSecondary),
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
          decoration: InputDecoration(
            labelText:
                '${AppLanguage.tr('Transaction ID / Reference', 'ट्रान्जेक्सन आईडी / सन्दर्भ')} *',
            helperText: AppLanguage.tr(
                'Enter the transaction ID or remarks shown after your payment.',
                'तपाईंको भुक्तानी पछि देखिएको ट्रान्जेक्सन आईडी वा रिमार्क्स प्रविष्ट गर्नुहोस्।'),
            hintText: AppLanguage.tr(
                'e.g. TXN123456789', 'जस्तै TXN123456789'),
            border: const OutlineInputBorder(),
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
          decoration: InputDecoration(
            labelText: AppLanguage.tr(
                'Message (optional)', 'सन्देश (वैकल्पिक)'),
            hintText: AppLanguage.tr(
                "Add a note for the admin, e.g. paid from a family member's account",
                'एड्मिनको लागि नोट थप्नुहोस्, जस्तै परिवारको सदस्यको खाताबाट तिरेको'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: (_submitting || _uploadingScreenshot || !canSubmit)
              ? null
              : () async {
                  if (await _confirmSubmit()) {
                    final d = await _future;
                    if (mounted) _handleSubmitManual(d);
                  }
                },
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(
                  AppLanguage.tr(
                      'Submit Payment', 'भुक्तानी पेश गर्नुहोस्'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
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

/// Full-screen image preview with 1x–4x zoom controls — mirrors the preview
/// Modal in checkout.tsx (header + stage + - % + controls).
class _ImagePreviewDialog extends StatefulWidget {
  final Uint8List? bytes;
  final String? url;
  const _ImagePreviewDialog({this.bytes, this.url});

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final image = widget.bytes != null
        ? Image.memory(widget.bytes!, fit: BoxFit.contain)
        : Image.network(widget.url ?? '', fit: BoxFit.contain);
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          SizedBox(
            height: 62,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLanguage.tr(
                        'Payment Screenshot', 'भुक्तानी स्क्रिनसट'),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        decoration: TextDecoration.none),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close,
                        size: 28, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Transform.scale(
                scale: _scale,
                child: image,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _zoomButton(
                    Icons.remove,
                    () => setState(
                        () => _scale = (_scale - 0.25).clamp(1.0, 4.0))),
                const SizedBox(width: 22),
                Text(
                  '${(_scale * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(width: 22),
                _zoomButton(
                    Icons.add,
                    () => setState(
                        () => _scale = (_scale + 0.25).clamp(1.0, 4.0))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0x29 / 0xFF),
          borderRadius: BorderRadius.circular(21),
        ),
        child: Icon(icon, size: 24, color: Colors.white),
      ),
    );
  }
}
