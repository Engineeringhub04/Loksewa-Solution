// Shared gateway payment-problem section — extracted from
// subscription_detail_screen.dart (v1.0.112) so exam/content purchase request
// pages show the SAME recovery UI: the "app was closed" message, the
// Check My Payment button (worker recheck with purchaseType), fraud handling
// (Contact Our Admin only, no retry), and the verifying/success/failure
// popup flow. Same visual language everywhere — no third variant.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/app_language.dart';
import '../services/auth_service.dart';
import '../services/gateway_payment_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';
import 'gateway_popups.dart';

/// Minimal record surface the problem section needs. Implement over
/// SubscriptionRecord / ExamPurchaseRecord / ContentPurchaseRecord.
abstract class PaymentProblemRecord {
  /// 'esewa' | 'khalti'
  String get method;
  String get transactionRef;
  String? get failureReason;

  /// Definitive failure (amount mismatch / duplicate) — no retry offered.
  bool get isFraud;

  /// Display name shown in the success popup.
  String get successTitle;
}

class PaymentProblemSection extends StatefulWidget {
  final PaymentProblemRecord record;

  /// 'subscription' | 'exam' | 'content' — forwarded to the worker's recheck.
  final String purchaseType;
  final VoidCallback onRechecked;

  const PaymentProblemSection({
    super.key,
    required this.record,
    required this.purchaseType,
    required this.onRechecked,
  });

  @override
  State<PaymentProblemSection> createState() => _PaymentProblemSectionState();
}

class _PaymentProblemSectionState extends State<PaymentProblemSection> {
  bool _checking = false;

  String get _message {
    if (widget.record.isFraud) {
      return AppLanguage.tr(
        "We couldn't verify this payment — the details don't match our records. Please contact admin.",
        'यो भुक्तानी प्रमाणीकरण हुन सकेन — विवरण हाम्रो रेकर्डसँग मिलेन। कृपया admin लाई सम्पर्क गर्नुहोस्।',
      );
    }
    if (widget.purchaseType == 'subscription') {
      return AppLanguage.tr(
        "We couldn't verify your payment because the app was closed. If you've already paid, tap Check My Payment to activate your plan.",
        'एप बन्द भएकाले भुक्तानी प्रमाणीकरण हुन सकेन। पैसा तिरिसक्नुभएको छ भने Check My Payment थिचेर plan activate गर्नुहोस्।',
      );
    }
    return AppLanguage.tr(
      "We couldn't verify your payment because the app was closed. If you've already paid, tap Check My Payment to activate your purchase.",
      'एप बन्द भएकाले भुक्तानी प्रमाणीकरण हुन सकेन। पैसा तिरिसक्नुभएको छ भने Check My Payment थिचेर खरिद activate गर्नुहोस्।',
    );
  }

  Future<void> _checkMyPayment() async {
    final record = widget.record;
    final txnId = record.transactionRef.trim();
    if (txnId.isEmpty) {
      showToast(
          context,
          AppLanguage.tr('No payment reference found. Please contact admin.',
              'भुक्तानी सन्दर्भ फेला परेन। कृपया admin लाई सम्पर्क गर्नुहोस्।'),
          ToastVariant.error);
      return;
    }
    setState(() => _checking = true);
    final closeVerifying = await showGatewayVerifyingPopup(context);
    Map<String, dynamic> res;
    try {
      res = await GatewayPaymentService.recheckPayment(
        gateway: record.method,
        transactionUuid: txnId,
        purchaseType: widget.purchaseType,
      );
    } catch (e) {
      res = {'ok': false, 'reason': 'network_error'};
    }
    if (!mounted) {
      closeVerifying();
      return;
    }
    setState(() => _checking = false);
    if (res['ok'] == true) {
      await GatewayPaymentService.clearPendingPayment();
      if (widget.purchaseType == 'subscription') {
        // Profile refresh while the verifying popup is still up — the
        // premium pill flips instantly with no blank gap.
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
      widget.onRechecked();
      closeVerifying();
      if (!mounted) return;
      await showGatewaySuccessPopup(
        context,
        planName: record.successTitle,
        onNavigate: widget.onRechecked,
      );
    } else {
      closeVerifying();
      if (!mounted) return;
      await showGatewayFailurePopup(
        context,
        message: gatewayFailureMessage(res['reason']?.toString()),
      );
      widget.onRechecked();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final fraud = widget.record.isFraud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _message,
          style: TextStyle(
              fontSize: ExpoType.bodySmall,
              color: pal.textPrimary,
              height: 1.5,
              decoration: TextDecoration.none),
        ),
        const SizedBox(height: ExpoSpacing.md),
        if (!fraud)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _checking ? null : _checkMyPayment,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                _checking
                    ? AppLanguage.tr('Checking…', 'जाँच हुँदैछ…')
                    : AppLanguage.tr(
                        'Check My Payment', 'मेरो भुक्तानी जाँच्नुहोस्'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: pal.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        if (!fraud) const SizedBox(height: ExpoSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/contact-us'),
            icon: const Icon(Icons.support_agent_outlined, size: 18),
            label: Text(
              AppLanguage.tr(
                  'Contact Our Admin', 'हाम्रो Admin लाई सम्पर्क गर्नुहोस्'),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: ExpoSpacing.sm),
        Text(
          AppLanguage.tr(
            "If verification doesn't work, please contact our admin.",
            'प्रमाणीकरण नभए कृपया admin लाई सम्पर्क गर्नुहोस्।',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: ExpoType.caption,
              color: pal.textSecondary,
              decoration: TextDecoration.none),
        ),
      ],
    );
  }
}
