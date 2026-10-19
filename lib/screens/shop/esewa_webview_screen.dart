import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/gateway_payment_service.dart';
import 'package:loksewa_solution/widgets/gateway_popups.dart';
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

  /// Worker-served auto-post form URL (GET /payments/esewa/form/:txnId).
  /// When present the webview loads this REAL URL (Khalti's proven
  /// pattern) instead of an HTML string — the HTML-string loading path is
  /// broken on iOS/WKWebView. Null = old worker → HTML-string fallback.
  final String? formUrl;

  const EsewaWebViewScreen({
    super.key,
    required this.endpoint,
    required this.fields,
    required this.testMode,
    required this.transactionUuid,
    this.gateway = 'esewa',
    this.purchaseType = 'subscription',
    this.formUrl,
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

  /// webview_flutter controller. The eSewa form is loaded from the
  /// worker-served HTTPS URL (real navigation — the proven iOS pattern);
  /// the HTML-string path is only a fallback for old workers.
  late final WebViewController _controller;

  /// Watchdog: the iOS string-loading path rendered a permanent white
  /// screen with no recovery. If 10s after load the webview has not
  /// reached an eSewa host, show a "Continue" button that reloads —
  /// never a silent permanent white screen again.
  Timer? _watchdogTimer;
  bool _showContinue = false;

  /// Guards the cancel-confirm dialog against stacked back presses.
  bool _confirmingCancel = false;

  /// UX-only purchase countdown (the worker sweep is the source of truth
  /// for expiry — it also covers the app-closed case).
  static const int _sessionSecs = 15 * 60;
  int _remainingSecs = _sessionSecs;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0F1A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (_) {
            if (mounted) setState(() => _loadingPage = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loadingPage = false);
          },
          onWebResourceError: (error) {
            // iOS diagnostics: surface the failing URL + description so
            // a future on-device test can report exactly what failed.
            debugPrint('[EsewaWebView] load error: ${error.description} '
                '(url: ${error.url})');
            if (mounted) setState(() => _loadingPage = false);
          },
        ),
      )
      ..setOnConsoleMessage((message) {
        debugPrint('[EsewaWebView] console: ${message.message}');
      });
    _loadForm();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _done) return;
      if (_remainingSecs <= 1) {
        _expire();
      } else {
        setState(() => _remainingSecs--);
      }
    });
  }

  /// Loads the worker-served form URL when available (real URL load —
  /// the iOS-proven pattern), otherwise the legacy HTML-string fallback.
  Future<void> _loadForm() async {
    _watchdogTimer?.cancel();
    if (mounted) setState(() => _showContinue = false);
    final formUrl = widget.formUrl;
    if (formUrl != null && formUrl.isNotEmpty) {
      String token = '';
      try {
        token = await AuthService.getValidIdToken();
      } catch (_) {
        // Best-effort: the worker will 401 without it and the watchdog
        // below offers the Continue recovery.
      }
      if (!mounted || _done) return;
      await _controller.loadRequest(
        Uri.parse(formUrl),
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
      );
    } else {
      await _controller.loadHtmlString(_autoPostHtml);
    }
    _armWatchdog();
  }

  /// If the eSewa host is not reached within 10s, offer a manual
  /// "Continue" recovery instead of a permanent white screen.
  void _armWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(const Duration(seconds: 10), () async {
      if (!mounted || _done) return;
      String? url;
      try {
        url = await _controller.currentUrl();
      } catch (_) {
        url = null;
      }
      if (!mounted || _done) return;
      if (url == null || !url.contains('esewa.com')) {
        debugPrint('[EsewaWebView] watchdog: eSewa host not reached '
            '(currentUrl: $url) — showing Continue.');
        setState(() {
          _loadingPage = false;
          _showContinue = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _countdownTimer?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }

  /// Session expired: best-effort server cancel, then report 'expired' so
  /// the checkout can reset its state and toast.
  Future<void> _expire() async {
    if (_done) return;
    _done = true;
    _countdownTimer?.cancel();
    _redirectTimer?.cancel();
    _watchdogTimer?.cancel();
    await GatewayPaymentService.cancelPayment(
      gateway: widget.gateway,
      transactionUuid: widget.transactionUuid,
      purchaseType: widget.purchaseType,
    );
    if (!mounted) return;
    // Dismiss the cancel-confirm dialog first if it is open (see _finish).
    if (_confirmingCancel) Navigator.of(context).pop();
    // Lift the back-veto (canPop follows _done), then pop post-frame.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(const EsewaWebResult(status: 'expired'));
      }
    });
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
    _watchdogTimer?.cancel();
    // If the cancel-confirm dialog is open, dismiss it first so the
    // result pop below removes the page and not the dialog (the dialog
    // is a separate route — the page's PopScope does not veto its pop).
    if (_confirmingCancel) Navigator.of(context).pop();
    // Lift the back-veto (canPop follows _done) so the result pop below
    // is not blocked, then pop after the PopScope rebuilds — an
    // immediate pop would still be vetoed.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(r);
    });
  }

  /// Back pressed (app-bar back, Android system back, or iOS swipe-back —
  /// all vetoed by the PopScope below): confirm first. On confirm, the
  /// pending payment is cancelled server-side (zero trace, per the
  /// request-save rule) and the page reports 'cancelled' so the checkout
  /// resets its state. On dismiss, the user stays on the payment page.
  Future<void> _confirmCancel() async {
    if (_done || _confirmingCancel || !mounted) return;
    _confirmingCancel = true;
    try {
      final confirmed = await showCancelPaymentConfirm(context);
      if (!mounted || _done) return;
      if (confirmed) {
        // Best-effort server cancel first (never throws), then report
        // 'cancelled'. The checkout also fires its own best-effort cancel
        // on this result — the worker treats the duplicate as not_found.
        await GatewayPaymentService.cancelPayment(
          gateway: widget.gateway,
          transactionUuid: widget.transactionUuid,
          purchaseType: widget.purchaseType,
        );
        _finish(const EsewaWebResult(status: 'cancelled'));
      }
    } finally {
      _confirmingCancel = false;
    }
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

  FutureOr<NavigationDecision> _onNavigationRequest(NavigationRequest request) {
    final raw = request.url;
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
      return NavigationDecision.prevent;
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
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  @override
  Widget build(BuildContext context) {
    // The gateway page starts BELOW the curved header (small gap, no
    // overlap). The header's own height = status-bar inset + 12 top
    // padding + 36 content + 20 bottom padding — mirror it here so the
    // webview never slides under the header.
    final headerBottom =
        MediaQuery.of(context).padding.top + 12 + 36 + 20 + 8;
    // canPop: false vetoes EVERY back path while the payment is in
    // progress: the app-bar back button, the Android system back, and the
    // iOS edge-swipe-back (the gesture is disabled while a PopScope veto
    // is active). It flips to true via _done when the page finishes
    // (success/failure/expiry/cancel) so the result pop is not blocked.
    // The webview's internal history never hijacks back — back always
    // means the cancel flow.
    return PopScope(
      canPop: _done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: Scaffold(
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
            child: WebViewWidget(controller: _controller),
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
          // Watchdog recovery: the eSewa host was not reached in time
          // (the old permanent-white case) — offer a manual Continue
          // that reloads the form instead of a dead screen.
          if (_showContinue && !_done)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF0B0F1A),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.signal_wifi_off_rounded,
                            size: 40, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 12),
                        Text(
                          AppLanguage.tr(
                            'The eSewa page is taking too long to open.',
                            'eSewa पेज खोल्न धेरै समय लागिरहेको छ।',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFFE2E8F0), fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() => _loadingPage = true);
                            _loadForm();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF60BB46),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 12),
                          ),
                          child: Text(AppLanguage.tr(
                              'Continue', 'जारी राख्नुहोस्')),
                        ),
                      ],
                    ),
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
              onBackPress: _confirmCancel,
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
      ),
    );
  }
}
