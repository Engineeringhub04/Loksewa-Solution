import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/gateway_payment_service.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
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

  /// Worker purchaseType ('subscription' | 'exam' | 'content') — the
  /// expiry-cancel must target the right collection.
  final String purchaseType;

  const EsewaWebViewScreen({
    super.key,
    required this.endpoint,
    required this.fields,
    required this.testMode,
    required this.transactionUuid,
    this.gateway = 'esewa',
    this.purchaseType = 'subscription',
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
      purchaseType: widget.purchaseType,
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
    // The gateway page starts BELOW the curved header (small gap, no
    // overlap). The header's own height = status-bar inset + 12 top
    // padding + 36 content + 20 bottom padding — mirror it here so the
    // webview never slides under the header.
    final headerBottom =
        MediaQuery.of(context).padding.top + 12 + 36 + 20 + 8;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      // Full-bleed: the webview fills the screen below the header and the
      // curved Header renders FIRST (immediately on open); the webview
      // loads underneath. The loading overlay sits between them — behind
      // the header, above the webview — so the header is never covered.
      body: Stack(
        children: [
          Positioned(
            top: headerBottom,
            left: 0,
            right: 0,
            bottom: 0,
            child: InAppWebView(
              // iOS (WKWebView) intermittently renders initialData as a
              // blank page, so the auto-POST HTML is loaded explicitly via
              // the controller with explicit mimeType/encoding/baseUrl —
              // the documented workaround. Single load only (no
              // initialData): the form auto-submits on load, so loading
              // twice would double-submit the payment POST.
              initialUrlRequest: URLRequest(url: WebUri('about:blank')),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                supportMultipleWindows: false,
              ),
              onWebViewCreated: (controller) {
                controller.loadData(
                  data: _autoPostHtml,
                  mimeType: 'text/html',
                  encoding: 'utf8',
                  baseUrl: WebUri(widget.endpoint),
                );
              },
              shouldOverrideUrlLoading: _onShouldOverride,
              onLoadStart: (_, __) {
                if (mounted) setState(() => _loadingPage = true);
              },
              onLoadStop: (_, __) {
                if (mounted) setState(() => _loadingPage = false);
              },
              onReceivedError: (controller, request, error) {
                // iOS diagnostics: surface the failing URL + description so
                // a future on-device test can report exactly what failed.
                debugPrint(
                    '[EsewaWebView] load error: ${error.description} '
                    '(url: ${request.url})');
                if (mounted) setState(() => _loadingPage = false);
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint(
                    '[EsewaWebView] console[${consoleMessage.messageLevel}]: '
                    '${consoleMessage.message}');
              },
            ),
          ),
          if (_loadingPage)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF0B0F1A),
                child: Center(
                  child: PreloadingWidget(
                    label: AppLanguage.tr(
                        'Connecting to eSewa…', 'eSewa मा जडान हुँदैछ…'),
                  ),
                ),
              ),
            ),
          // Curved header overlaid on top of everything — always visible,
          // never hidden behind the loading state.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SubpageHeader(
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
          ),
        ],
      ),
    );
  }
}
