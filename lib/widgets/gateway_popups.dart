// Shared gateway payment popups — AppModalShell premium style.
//
// Used by the checkout screen (verify flow) and the subscription detail
// screen ("Check My Payment" recheck flow):
//   - showGatewayVerifyingPopup: non-dismissible checking state.
//   - showGatewaySuccessPopup: plan-name message + 5s auto-redirect.
//   - showGatewayFailurePopup: real reason + Close (optional Retry).
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

import 'app_modal_shell.dart';
import 'popup_action_button.dart';

const _navy = Color(0xFF0F172A);
const _blue = Color(0xFF2563EB);
const _blueMid = Color(0xFF3B82F6);
const _blueLight = Color(0xFFBFDBFE);
const _green = Color(0xFF059669);
const _greenMid = Color(0xFF10B981);
const _greenLight = Color(0xFFA7F3D0);
const _red = Color(0xFFDC2626);
const _redMid = Color(0xFFEF4444);
const _redLight = Color(0xFFFECACA);

Widget _iconTile(Color color, Widget child) {
  return Container(
    width: 56,
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: color,
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

/// Presents [card] like AppModalShell.show but with a light dim and an
/// optional non-dismissible barrier (the verifying state must not be
/// tappable-away).
Future<T?> _presentShell<T>({
  required BuildContext context,
  required Widget card,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (pageContext, _, __) {
      return Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: card,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Non-dismissible "Verifying payment…" popup. Returns a closer.
Future<void Function()> showGatewayVerifyingPopup(BuildContext context) async {
  var closed = false;
  unawaited(_presentShell<void>(
    context: context,
    dismissible: false,
    card: AppModalShell(
      maxWidth: 340,
      borderRadius: 30,
      accent: _blue,
      accentMid: _blueMid,
      accentLight: _blueLight,
      tagColor: _blue,
      onClose: null,
      icon: _iconTile(
        _blue,
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
              strokeWidth: 3, color: Colors.white),
        ),
      ),
      tagLabel: AppLanguage.tr('SECURE PAYMENT', 'सुरक्षित भुक्तानी'),
      title: Text(
        AppLanguage.tr('Verifying payment…', 'भुक्तानी प्रमाणीकरण हुँदैछ…'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: _navy,
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLanguage.tr(
              'Confirming with the payment gateway. Please do not close the app.',
              'भुक्तानी गेटवेसँग पुष्टि हुँदैछ। कृपया एप बन्द नगर्नुहोस्।',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
              height: 1.5,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
      footer: const SizedBox.shrink(),
    ),
  ).then((_) => closed = true));
  return () {
    if (!closed) {
      closed = true;
      Navigator.of(context, rootNavigator: true).pop();
    }
  };
}

/// Success popup: "{PlanName} is now active!" + auto-redirect after 5s.
/// [onNavigate] runs on manual Continue or when the timer fires.
Future<void> showGatewaySuccessPopup(
  BuildContext context, {
  required String planName,
  required VoidCallback onNavigate,
}) {
  return _presentShell<void>(
    context: context,
    dismissible: false,
    card: _SuccessCard(planName: planName, onNavigate: onNavigate),
  );
}

class _SuccessCard extends StatefulWidget {
  final String planName;
  final VoidCallback onNavigate;
  const _SuccessCard({required this.planName, required this.onNavigate});

  @override
  State<_SuccessCard> createState() => _SuccessCardState();
}

class _SuccessCardState extends State<_SuccessCard> {
  static const _totalSecs = 5;
  int _remaining = _totalSecs;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _finish();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    Navigator.of(context, rootNavigator: true).pop();
    widget.onNavigate();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.planName.isNotEmpty
        ? AppLanguage.tr(
            '${widget.planName} is now active! Enjoy learning!',
            '${widget.planName} अब सक्रिय भयो! रमाइलो सिकाइ!',
          )
        : AppLanguage.tr(
            'Your subscription is now active! Enjoy learning!',
            'तपाईंको सदस्यता अब सक्रिय भयो! रमाइलो सिकाइ!',
          );
    return AppModalShell(
      maxWidth: 340,
      borderRadius: 30,
      accent: _green,
      accentMid: _greenMid,
      accentLight: _greenLight,
      tagColor: _green,
      onClose: null,
      icon: _iconTile(
        _green,
        const Icon(Icons.check_rounded, size: 30, color: Colors.white),
      ),
      tagLabel: AppLanguage.tr('PAYMENT COMPLETE', 'भुक्तानी पूरा भयो'),
      title: Text(
        AppLanguage.tr('Payment successful', 'भुक्तानी सफल भयो'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: _navy,
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
              height: 1.5,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: _finish,
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              AppLanguage.tr('Continue', 'जारी राख्नुहोस्'),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.tr(
              'Redirecting in $_remaining s…',
              '$_remaining सेकेन्डमा जाँदैछ…',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// Failure popup: the real reason + Close. Optional Retry (checkout flow).
Future<void> showGatewayFailurePopup(
  BuildContext context, {
  required String message,
  VoidCallback? onRetry,
  VoidCallback? onClosed,
}) {
  return _presentShell<void>(
    context: context,
    dismissible: false,
    card: AppModalShell(
      maxWidth: 340,
      borderRadius: 30,
      accent: _red,
      accentMid: _redMid,
      accentLight: _redLight,
      tagColor: _red,
      onClose: null,
      icon: _iconTile(
        _red,
        const Icon(Icons.close_rounded, size: 30, color: Colors.white),
      ),
      tagLabel: AppLanguage.tr('PAYMENT FAILED', 'भुक्तानी असफल भयो'),
      title: Text(
        AppLanguage.tr('Payment failed', 'भुक्तानी असफल भयो'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: _navy,
          height: 1.3,
          decoration: TextDecoration.none,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
              height: 1.5,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onRetry != null) ...[
            ElevatedButton(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).pop();
                onRetry();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                AppLanguage.tr('Try again', 'पुनः प्रयास गर्नुहोस्'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop();
              onClosed?.call();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              AppLanguage.tr('Close', 'बन्द गर्नुहोस्'),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Human-readable text for a worker failure reason code.
String gatewayFailureMessage(String? reason) {
  switch (reason) {
    case 'amount_mismatch':
      return AppLanguage.tr(
        "We couldn't verify this payment — the details don't match our records. Please contact admin.",
        'यो भुक्तानी प्रमाणीकरण हुन सकेन — विवरण हाम्रो रेकर्डसँग मिलेन। कृपया admin लाई सम्पर्क गर्नुहोस्।',
      );
    case 'duplicate':
      return AppLanguage.tr(
        'This payment was already used. Please contact admin if you need help.',
        'यो भुक्तानी पहिले नै प्रयोग भइसकेको छ। सहयोग चाहिएमा कृपया admin लाई सम्पर्क गर्नुहोस्।',
      );
    case 'order_mismatch':
    case 'uuid_mismatch':
      return AppLanguage.tr(
        "We couldn't match this payment to your order. Please don't pay again — contact admin with your payment reference.",
        'यो भुक्तानी तपाईंको अर्डरसँग मिलाउन सकिएन। कृपया फेरि पैसा नतिर्नुहोस् — आफ्नो भुक्तानी सन्दर्भ सहित admin लाई सम्पर्क गर्नुहोस्।',
      );
    case 'signature_mismatch':
    case 'product_code_mismatch':
      return AppLanguage.tr(
        "We couldn't verify this payment — the payment details look tampered. Please contact admin.",
        'यो भुक्तानी प्रमाणीकरण हुन सकेन — भुक्तानी विवरण शंकास्पद देखियो। कृपया admin लाई सम्पर्क गर्नुहोस्।',
      );
    case 'payment_not_completed':
      return AppLanguage.tr(
        'The payment was not completed at the gateway. No amount was charged.',
        'गेटवैमा भुक्तानी पूरा भएन। कुनै रकम काटिएन।',
      );
    case 'not_found':
      return AppLanguage.tr(
        'We could not find this payment. Please contact admin.',
        'यो भुक्तानी फेला पार्न सकिएन। कृपया admin लाई सम्पर्क गर्नुहोस्।',
      );
    case 'gateway_disabled':
      return AppLanguage.tr(
        'This payment method is currently disabled.',
        'यो भुक्तानी विधि अहिले बन्द छ।',
      );
    default:
      return AppLanguage.tr(
        'Payment verification failed. Please try again or contact admin.',
        'भुक्तानी प्रमाणीकरण असफल भयो। कृपया पुनः प्रयास गर्नुहोस् वा admin लाई सम्पर्क गर्नुहोस्।',
      );
  }
}

/// "Cancel payment?" confirm — shown when the user backs out of a gateway
/// (eSewa/Khalti) page: app-bar back, Android system back, or the iOS
/// swipe-back (all vetoed by the page's PopScope). Returns true when the
/// user confirms the cancel; false/null on dismiss.
///
/// The caller owns the cancel itself (worker /payments/cancel → pop).
/// Shared AppModalShell design, EN+NE strings.
Future<bool> showCancelPaymentConfirm(BuildContext context) async {
  final confirmed = await AppModalShell.show<bool>(
    context: context,
    builder: (dialogContext) => AppModalShell(
      accent: AppColors.navy,
      accentMid: const Color(0xFF1E3A8A),
      accentLight: const Color(0xFFBFDBFE),
      tagColor: AppColors.navy,
      tagLabel: AppLanguage.tr('PAYMENT', 'भुक्तानी'),
      onClose: () => Navigator.of(dialogContext).pop(false),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppColors.navy,
        ),
        child: const Icon(Icons.money_off_rounded,
            size: 28, color: Colors.white),
      ),
      title: Text(
        AppLanguage.tr('Cancel payment?', 'भुक्तानी रद्द गर्ने?'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
          decoration: TextDecoration.none,
        ),
      ),
      body: Text(
        AppLanguage.tr(
          'If you go back now, this payment is cancelled and its payment record is removed completely.',
          'अहिले फर्कनुभयो भने यो भुक्तानी रद्द हुन्छ र यसको भुक्तानी रेकर्ड पूर्ण रूपमा हट्छ।',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF475569),
            decoration: TextDecoration.none),
      ),
      footer: Row(
        children: [
          Expanded(
            child: PopupCancelButton(
              label: AppLanguage.tr('Stay', 'रहनुहोस्'),
              onTap: () => Navigator.of(dialogContext).pop(false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PopupActionButton(
              label: AppLanguage.tr('Cancel Payment', 'भुक्तानी रद्द गर्नुहोस्'),
              backgroundColor: const Color(0xFFDC2626),
              onTap: () => Navigator.of(dialogContext).pop(true),
            ),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}
