import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/gateway_payment_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/subpage_header.dart';

/// Result returned by [EsewaWebViewScreen] via Navigator.pop.
class EsewaWebResult {
  /// 'success' | 'failure' | 'cancelled' | 'expired'
  final String status;

  /// Base64 `data` query param from eSewa's success redirect (proof).
  final String? data;

  /// Human-readable failure reason, when [status] == 'failure'.
  final String? message;

  const EsewaWebResult({required this.status, this.data, this.message});
}

/// In-app eSewa payment page — everything stays inside the app, never
/// opens Chrome. Auto-POSTs the worker-signed form fields to eSewa and
/// intercepts the success/failure redirects configured in the worker.
class EsewaWebViewScreen extends StatefulWidget {
  final String endpoint;
  final Map<String, String> fields;
  final bool testMode;

  /// Worker transaction id — used to cancel the pending payment on expiry.
  final String transactionUuid;

  /// 'esewa' (kept explicit so the cancel call is never ambiguous).
  final String gateway;

  const EsewaWebViewScreen({
    super.key,
    required this.endpoint,
    required this.fields,
    required this.testMode,
    required this.transactionUuid,
    this.gateway = 'esewa',
  });

  @override
  State<EsewaWebViewScreen> createState() => _EsewaWebViewScreenState();
}

class _EsewaWebViewScreenState extends State<EsewaWebViewScreen> {
  static const _successPrefix = 'https://kbr.com.np/payments/esewa/success';
  static const _failurePrefix = 'https://kbr.com.np/payments/esewa/failure';

  bool _loadingPage = true;
  bool _done = false;
  Timer? _redirectTimer;

  /// UX-only purchase countdown (the worker sweep is the source of truth
  /// for expiry — it also covers the app-closed case).
  static const int _sessionSecs = 15 * 60;
  int _remainingSecs = _sessionSecs;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _done) return;
      if (_remainingSecs <= 1) {
        _expire();
      } else {
        setState(() => _remainingSecs--);
      }
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Session expired: best-effort server cancel, then report 'expired' so
  /// the checkout can reset its state and toast.
  Future<void> _expire() async {
    if (_done) return;
    _done = true;
    _countdownTimer?.cancel();
    _redirectTimer?.cancel();
    await GatewayPaymentService.cancelPayment(
      gateway: widget.gateway,
      transactionUuid: widget.transactionUuid,
    );
    if (!mounted) return;
    Navigator.of(context).pop(const EsewaWebResult(status: 'expired'));
  }

  String get _countdownText {
    final m = (_remainingSecs ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String get _autoPostHtml {
    final inputs = widget.fields.entries
        .map((e) =>
            '<input type="hidden" name="${_esc(e.key)}" value="${_esc(e.value)}">')
        .join('\n');
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="background:#0B0F1A;color:#94A3B8;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
<div>Redirecting to eSewa…</div>
<form id="f" method="post" action="${_esc(widget.endpoint)}">
$inputs
</form>
<script>document.getElementById('f').submit();</script>
</body></html>
''';
  }

  void _finish(EsewaWebResult r) {
    if (_done || !mounted) return;
    _done = true;
    _countdownTimer?.cancel();
    _redirectTimer?.cancel();
    Navigator.of(context).pop(r);
  }

  /// eSewa's own "Redirecting, Please Wait!" page must stay visible while
  /// the redirect happens — so when the success/failure URL is detected we
  /// CANCEL the navigation (the webview keeps showing eSewa's page) and
  /// only finish after a short delay.
  void _finishDelayed(EsewaWebResult r, Duration delay) {
    if (_done) return;
    _redirectTimer?.cancel();
    _redirectTimer = Timer(delay, () => _finish(r));
  }

  Future<NavigationActionPolicy?> _onShouldOverride(
      InAppWebViewController controller, NavigationAction action) async {
    final raw = action.request.url?.toString() ?? '';
    if (raw.startsWith(_successPrefix)) {
      final uri = Uri.tryParse(raw);
      final data = uri?.queryParameters['data'];
      if (data != null && data.isNotEmpty) {
        _finishDelayed(EsewaWebResult(status: 'success', data: data),
            const Duration(milliseconds: 1200));
      } else {
        _finishDelayed(
            EsewaWebResult(
                status: 'failure',
                message: AppLanguage.tr('eSewa returned no payment data.',
                    'eSewa ले भुक्तानी डेटा फर्काएन।')),
            const Duration(milliseconds: 800));
      }
      return NavigationActionPolicy.CANCEL;
    }
    if (raw.startsWith(_failurePrefix)) {
      final uri = Uri.tryParse(raw);
      final msg = uri?.queryParameters['message'];
      _finishDelayed(
          EsewaWebResult(
              status: 'failure',
              message: msg?.isNotEmpty == true
                  ? msg
                  : AppLanguage.tr(
                      'Payment was not completed.', 'भुक्तानी पूरा भएन।')),
          const Duration(milliseconds: 800));
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      // The app's curved header (eSewa's own page content is untouchable).
      body: Column(
        children: [
          SubpageHeader(
            title: AppLanguage.tr('eSewa Payment', 'eSewa भुक्तानी'),
            onBackPress: () =>
                _finish(const EsewaWebResult(status: 'cancelled')),
            showThemeToggle: false,
            actions: [
              // Visible purchase countdown — UX only; the worker sweep is
              // the source of truth for expiry.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${AppLanguage.tr('Purchase Time', 'खरिद समय')}: $_countdownText',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
              if (widget.testMode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.6)),
                  ),
                  child: Text(AppLanguage.tr('TEST', 'टेस्ट'),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.amber)),
                ),
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
            initialData: InAppWebViewInitialData(data: _autoPostHtml),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              supportMultipleWindows: false,
            ),
            shouldOverrideUrlLoading: _onShouldOverride,
            onLoadStart: (_, __) {
              if (mounted) setState(() => _loadingPage = true);
            },
            onLoadStop: (_, __) {
              if (mounted) setState(() => _loadingPage = false);
            },
            onReceivedError: (_, __, ___) {
              if (mounted) setState(() => _loadingPage = false);
            },
          ),
          if (_loadingPage)
            Container(
              color: pal.background,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.accent),
                    const SizedBox(height: 14),
                    Text(
                      AppLanguage.tr('Connecting to eSewa…',
                          'eSewa मा जडान हुँदैछ…'),
                      style: TextStyle(
                          fontSize: 13, color: pal.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
