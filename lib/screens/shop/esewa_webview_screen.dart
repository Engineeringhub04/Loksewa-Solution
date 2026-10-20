import 'dart:async';
import 'dart:io' show Platform;

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

/// Result of the blank-page DOM probe (see [_EsewaWebViewScreenState]).
///
/// The probe is a single delimited string from the page's own JS:
/// `readyState|innerTextLength|interactiveElementCount`. Parsing it as a
/// pipe-delimited string (instead of JSON) is deliberate: Android's
/// webview_flutter returns JS strings JSON-quoted, iOS's returns them
/// bare — [tryParse] handles both.
class EsewaProbeResult {
  final String readyState;
  final int textLength;
  final int interactiveCount;

  const EsewaProbeResult({
    required this.readyState,
    required this.textLength,
    required this.interactiveCount,
  });

  /// Null when the probe value is unusable (eval failed, 'error' token,
  /// or malformed) — an inconclusive probe must NEVER count as a blank
  /// verdict.
  static EsewaProbeResult? tryParse(Object? raw) {
    if (raw == null) return null;
    var s = '$raw'.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    final parts = s.split('|');
    if (parts.length != 3 || parts[0] == 'error') return null;
    final text = int.tryParse(parts[1]);
    final interactive = int.tryParse(parts[2]);
    if (text == null || interactive == null) return null;
    return EsewaProbeResult(
      readyState: parts[0],
      textLength: text,
      interactiveCount: interactive,
    );
  }

  /// Blank = the page finished loading but renders nothing: eSewa's JS
  /// SPA never mounted (e.g. iOS 15's JavaScriptCore cannot run its
  /// bundle). Plain white page, no recovery by waiting.
  bool get looksBlank =>
      readyState == 'complete' && textLength < 20 && interactiveCount < 3;
}

/// Why the blank panel is shown: drives the panel's message. The STATE is
/// decided by the DOM probe ([EsewaProbeResult.looksBlank]) — the
/// platform is only consulted for the message, never for the verdict.
enum EsewaBlankKind { oldSystem, loadFailed }

/// oldSystem = iOS below 16 (WebKit too old for eSewa's SPA);
/// loadFailed = anything else (newer iOS or Android: network / eSewa
/// outage — the message offers a retry instead of blaming the device).
EsewaBlankKind esewaBlankKind({
  required bool isIOS,
  required int? iosMajor,
}) =>
    (isIOS && iosMajor != null && iosMajor < 16)
        ? EsewaBlankKind.oldSystem
        : EsewaBlankKind.loadFailed;

/// Parses the leading major version from
/// [Platform.operatingSystemVersion] ("Version 15.8.3 (Build 19H386)" →
/// 15). Null when unparseable.
int? parseIosMajorVersion(String osVersion) {
  final match = RegExp(r'(\d+)').firstMatch(osVersion);
  return match == null ? null : int.tryParse(match.group(1)!);
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

  /// Guards the cancel-confirm dialog against stacked back presses —
  /// true only while [_confirmCancel] is running its flow.
  bool _confirmingCancel = false;

  /// True ONLY while the cancel-confirm dialog route is actually on
  /// screen. Cleared the moment [showCancelPaymentConfirm]'s future
  /// completes (the dialog pops itself with the result). [_finish] and
  /// [_expire] use this to decide whether a dismiss-pop is safe — keying
  /// it off [_confirmingCancel] used to misfire onto the page itself.
  bool _cancelDialogOpen = false;

  /// iOS/WKWebView quirk: webview_flutter answers every navigation
  /// decision asynchronously, which breaks the auto-submit form POST's
  /// body — so the delegate must NOT be installed while the form posts.
  /// The delegate (success/failure interception) is attached only AFTER
  /// the webview commits to an eSewa host, detected by the poll below.
  Timer? _delegatePollTimer;
  bool _delegateAttached = false;

  /// Blank-page liveness detection: eSewa's payment page is a JS SPA that
  /// silently renders nothing on old WebKit (iOS 15 — proven on-device:
  /// mobile Safari on the same phone is also white, so no app-side
  /// loading change can fix it). After the webview commits to an eSewa
  /// host, probes at +8s and +14s check the page's own DOM; both blank =
  /// verdict → the unsupported panel replaces the eternal white screen.
  /// Platform-agnostic: also catches eSewa downtime on Android.
  Timer? _livenessTimer;

  /// Generation counter: any navigation / retry / finish invalidates
  /// pending probe timers — they abort instead of firing late.
  int _livenessGen = 0;

  /// The URL the current liveness window was started for. A navigation to
  /// a new URL resets the window.
  String? _livenessUrl;

  /// Set once a probe proves the page rendered — probing stops for good.
  bool _pageAlive = false;

  /// True once the blank verdict fired: the webview is covered by the
  /// unsupported panel below (the header loses its countdown timer in
  /// this state — title + back/close only).
  bool _blankPanel = false;

  /// UX-only purchase countdown (the worker sweep is the source of truth
  /// for expiry — it also covers the app-closed case).
  static const int _sessionSecs = 15 * 60;
  int _remainingSecs = _sessionSecs;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // NOTE: no navigation delegate here — on iOS/WKWebView the delegate's
    // asynchronous decidePolicyFor round-trip breaks the auto-submit form
    // POST's body (eSewa answers with an HTTP error page: silent white
    // screen). The delegate is attached later, only once the webview has
    // committed to an eSewa host (see _startDelegatePoll).
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0F1A))
      ..setOnConsoleMessage((message) {
        debugPrint('[EsewaWebView] console: ${message.message}');
      });
    _loadForm();
    _startDelegatePoll();
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

  /// True when [host] is eSewa itself (live / sandbox subdomains).
  static bool _isEsewaHost(String host) =>
      host == 'esewa.com.np' || host.endsWith('.esewa.com.np');

  /// "Reached" = the webview committed to an eSewa host AND is not still
  /// sitting on the raw form-submit endpoint (an error page committed
  /// there is exactly the silent-white case) nor on the worker origin.
  bool _hasReachedEsewa(String? url) {
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !_isEsewaHost(uri.host)) return false;
    if (uri.path == '/api/epay/main/v2/form') return false;
    return true;
  }

  /// Polls [WebViewController.currentUrl] until the webview commits to
  /// an eSewa host, then attaches the navigation delegate (see initState
  /// note). The success/failure redirect only happens after the user
  /// finishes paying, long after arrival — late attachment cannot miss
  /// it. Runs at most once per screen.
  void _startDelegatePoll() {
    if (_delegateAttached || (_delegatePollTimer?.isActive ?? false)) return;
    _delegatePollTimer = Timer.periodic(const Duration(milliseconds: 500),
        (_) async {
      if (!mounted || _done || _delegateAttached) {
        _delegatePollTimer?.cancel();
        return;
      }
      String? url;
      try {
        url = await _controller.currentUrl();
      } catch (_) {
        url = null;
      }
      if (!mounted || _done || _delegateAttached) return;
      final uri = url == null ? null : Uri.tryParse(url);
      if (uri == null || !_isEsewaHost(uri.host)) return;
      _attachNavigationDelegate();
    });
  }

  /// Installs the navigation delegate (success/failure interception) —
  /// called exactly once, after the form POST has safely committed.
  void _attachNavigationDelegate() {
    if (_delegateAttached) return;
    _delegateAttached = true;
    _delegatePollTimer?.cancel();
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _onNavigationRequest,
        onPageStarted: (url) {
          if (mounted) setState(() => _loadingPage = true);
          // A fresh navigation on eSewa's pages restarts the liveness
          // window — the new page gets its own full blank-check budget.
          if (_livenessEligible(url) && url != _livenessUrl) {
            _livenessUrl = url;
            _startLivenessWatch();
          }
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
        onHttpError: (error) {
          // An HTTP error status (e.g. eSewa rejecting a request) renders
          // as a silent white page otherwise — log it so a future
          // on-device test can report exactly what failed.
          debugPrint('[EsewaWebView] http error '
              '${error.response?.statusCode} ${error.request?.uri}');
        },
      ),
    );
    // The committed eSewa page loaded before the delegate existed, so no
    // onPageFinished will fire for it — drop the loading overlay now.
    if (mounted && !_done) setState(() => _loadingPage = false);
    // The webview has committed to an eSewa host — start watching for
    // the silent-blank case (see _livenessProbe).
    _startLivenessWatch();
  }

  /// If the eSewa payment page was not reached within 10s, offer a manual
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
      if (!_hasReachedEsewa(url)) {
        debugPrint('[EsewaWebView] watchdog: eSewa page not reached '
            '(currentUrl: $url) — showing Continue.');
        setState(() {
          _loadingPage = false;
          _showContinue = true;
        });
      }
    });
  }

  /// The DOM probe evaluated inside the eSewa page. Returns
  /// `readyState|innerTextLength|interactiveCount`; 'error|0|0' when the
  /// page's JS itself throws (treated as inconclusive by [tryParse] —
  /// an eval failure is never a blank verdict).
  static const _probeJs = '(function(){try{'
      'var t=(document.body&&document.body.innerText)'
      '?document.body.innerText.trim().length:0;'
      "var n=document.querySelectorAll('input,button,select,a,img').length;"
      "return (document.readyState||'')+'|'+t+'|'+n;"
      "}catch(e){return 'error|0|0';}})()";

  /// Liveness probes only make sense while the webview sits on eSewa's
  /// own pages — never on the worker form page, never on the
  /// success/failure redirects (the delegate finishes on those).
  bool _livenessEligible(String? url) {
    if (url == null) return false;
    if (url.startsWith(_successPrefix) || url.startsWith(_failurePrefix)) {
      return false;
    }
    final uri = Uri.tryParse(url);
    return uri != null && _isEsewaHost(uri.host);
  }

  /// Invalidates any pending probe and stops the liveness machinery.
  void _stopLiveness() {
    _livenessGen++;
    _livenessTimer?.cancel();
  }

  /// (Re)starts a liveness window for the page the webview is now on:
  /// probes at ~+8s and ~+14s. Any navigation to a new URL, retry, or
  /// finish restarts/stops it via [_livenessGen].
  void _startLivenessWatch() {
    if (_done || _pageAlive || _blankPanel) return;
    final gen = ++_livenessGen;
    _livenessTimer?.cancel();
    _livenessTimer = Timer(const Duration(seconds: 8),
        () => _livenessProbe(gen, second: false, firstBlank: false));
  }

  /// One liveness probe. A verdict needs BOTH probes of a window to see
  /// an empty DOM at a stable eSewa URL ([firstBlank] carries the first
  /// probe's result); a single alive result marks the page alive for
  /// good; an inconclusive probe just ends the window quietly (never a
  /// verdict).
  Future<void> _livenessProbe(int gen,
      {required bool second, required bool firstBlank}) async {
    if (gen != _livenessGen || _done || !mounted ||
        _pageAlive || _blankPanel) {
      return;
    }
    String? url;
    try {
      url = await _controller.currentUrl();
    } catch (_) {
      url = null;
    }
    if (gen != _livenessGen || _done || !mounted) return;
    if (!_livenessEligible(url)) return; // window ends — not eSewa's page
    if (_livenessUrl != null && url != _livenessUrl) {
      // Navigated since the window started — restart the window for the
      // new URL instead of judging the old page.
      _livenessUrl = url;
      _startLivenessWatch();
      return;
    }
    _livenessUrl ??= url;
    EsewaProbeResult? probe;
    try {
      probe = EsewaProbeResult.tryParse(
          await _controller.runJavaScriptReturningResult(_probeJs));
    } catch (e) {
      debugPrint('[EsewaWebView] probe eval failed: $e');
      probe = null;
    }
    if (gen != _livenessGen || _done || !mounted) return;
    if (probe == null) {
      debugPrint('[EsewaWebView] probe inconclusive '
          '(check ${second ? 2 : 1}) — no verdict.');
      if (!second) {
        _livenessTimer = Timer(const Duration(seconds: 6),
            () => _livenessProbe(gen, second: true, firstBlank: false));
      }
      return;
    }
    if (!probe.looksBlank) {
      _pageAlive = true;
      debugPrint('[EsewaWebView] page alive: text=${probe.textLength} '
          'interactive=${probe.interactiveCount}');
      return;
    }
    debugPrint('[EsewaWebView] probe blank (check ${second ? 2 : 1}): '
        'text=${probe.textLength} interactive=${probe.interactiveCount} '
        'url=$url');
    if (!second) {
      _livenessTimer = Timer(const Duration(seconds: 6),
          () => _livenessProbe(gen, second: true, firstBlank: true));
      return;
    }
    if (!firstBlank) {
      // Only ONE actual empty-DOM result in this window (the first probe
      // was inconclusive) — that never counts as a verdict.
      debugPrint('[EsewaWebView] single blank result only — no verdict.');
      return;
    }
    // Both probes blank at a stable eSewa URL — the page cannot render
    // here. Show the unsupported panel instead of an eternal white screen.
    debugPrint('[EsewaWebView] blank verdict — showing unsupported panel '
        '(url: $url)');
    setState(() {
      _blankPanel = true;
      _loadingPage = false;
      _showContinue = false;
    });
  }

  /// 'Try Again' on the blank panel: reload the page and run a fresh
  /// liveness window (a transient failure can still recover; a genuinely
  /// unsupported device simply earns the panel again).
  Future<void> _retryFromBlankPanel() async {
    if (_done || !mounted) return;
    setState(() {
      _blankPanel = false;
      _loadingPage = true;
    });
    _livenessUrl = null;
    try {
      await _controller.reload();
      _startLivenessWatch();
    } catch (_) {
      // No page to reload (e.g. load never committed) — reload the whole
      // form flow instead.
      _loadForm();
    }
  }

  /// Shared tail of every user-cancel path: fire-and-forget server
  /// cancel, then finish as 'cancelled' so checkout resets and shows its
  /// single end toast.
  void _cancelAndFinish() {
    unawaited(GatewayPaymentService.cancelPayment(
      gateway: widget.gateway,
      transactionUuid: widget.transactionUuid,
      purchaseType: widget.purchaseType,
    ));
    _finish(const EsewaWebResult(status: 'cancelled'));
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _countdownTimer?.cancel();
    _watchdogTimer?.cancel();
    _delegatePollTimer?.cancel();
    _stopLiveness();
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
    _delegatePollTimer?.cancel();
    _stopLiveness();
    await GatewayPaymentService.cancelPayment(
      gateway: widget.gateway,
      transactionUuid: widget.transactionUuid,
      purchaseType: widget.purchaseType,
    );
    if (!mounted) return;
    // Dismiss the cancel-confirm dialog ONLY if it is genuinely open
    // right now — a stale flag here would pop the page itself.
    if (_cancelDialogOpen) {
      _cancelDialogOpen = false;
      Navigator.of(context).pop();
    }
    // Lift the back-veto (canPop follows _done), then pop post-frame —
    // but only while this page is still the top route, so a stale
    // callback can never pop another page.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(const EsewaWebResult(status: 'expired'));
      }
    });
  }

  /// Which blank-panel message to show (see [esewaBlankKind] — the
  /// platform only picks the message; the DOM probe picked the state).
  EsewaBlankKind get _blankKind => esewaBlankKind(
        isIOS: Platform.isIOS,
        iosMajor: Platform.isIOS
            ? parseIosMajorVersion(Platform.operatingSystemVersion)
            : null,
      );

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
    _delegatePollTimer?.cancel();
    _stopLiveness();
    // Dismiss the cancel-confirm dialog ONLY if it is genuinely open
    // right now: the dialog is a separate route (the page's PopScope
    // does not veto its pop), and an extra pop here would remove the
    // page itself with a null result.
    if (_cancelDialogOpen) {
      _cancelDialogOpen = false;
      Navigator.of(context).pop();
    }
    // Lift the back-veto (canPop follows _done) so the result pop below
    // is not blocked, then pop after the PopScope rebuilds — an
    // immediate pop would still be vetoed. Guarded by isCurrent so a
    // stale callback can never pop a different page.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(r);
      }
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
      _cancelDialogOpen = true;
      final confirmed = await showCancelPaymentConfirm(context);
      // The dialog popped itself with its result — it is NO LONGER open,
      // so _finish must not dismiss-pop anything: its single result pop
      // below is the only pop on this path.
      _cancelDialogOpen = false;
      if (!mounted || _done) return;
      if (confirmed) {
        // Fire-and-forget server cancel (mirrors the Khalti path) so the
        // page closes immediately instead of pausing on the gateway page
        // for the network round-trip. Checkout issues its own cancel when
        // it receives the 'cancelled' result — the worker is idempotent
        // and treats the duplicate as not_found.
        _cancelAndFinish();
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
          // Blank verdict: eSewa's page cannot render on this device —
          // cover the (eternally white) webview with a graceful panel.
          // The webview stays mounted underneath; only the panel's or
          // the header's actions can leave this state.
          if (_blankPanel && !_done)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF0B0F1A),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                Colors.amber.withValues(alpha: 0.16),
                            border: Border.all(
                                color:
                                    Colors.amber.withValues(alpha: 0.45)),
                          ),
                          child: const Icon(
                              Icons.warning_amber_rounded,
                              size: 36,
                              color: Colors.amber),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          AppLanguage.tr("Payment page couldn't load",
                              'भुक्तानी पेज लोड हुन सकेन'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _blankKind == EsewaBlankKind.oldSystem
                              ? AppLanguage.tr(
                                  "This device's system can't display eSewa's payment page. Please pay with Khalti or QR, or use a newer device.",
                                  'यो डिभाइसको प्रणालीले eSewa को भुक्तानी पेज देखाउन सक्दैन। कृपया Khalti वा QR बाट भुक्तानी गर्नुहोस्, वा नयाँ डिभाइस प्रयोग गर्नुहोस्।')
                              : AppLanguage.tr(
                                  'The payment page failed to load. Check your connection.',
                                  'भुक्तानी पेज लोड हुन सकेन। आफ्नो इन्टरनेट जडान जाँच गर्नुहोस्।'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFFCBD5E1), fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLanguage.tr(
                            'No payment was made — nothing was charged.',
                            'कुनै भुक्तानी भएन — केही शुल्क लागेन।',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            // Same exit as the cancel-confirm's confirm:
                            // unawaited worker cancel + 'cancelled'
                            // result → checkout shows its single end
                            // toast. No second confirm popup — picking
                            // another method IS the decision.
                            onPressed: _cancelAndFinish,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(AppLanguage.tr(
                                'Choose Another Method',
                                'अर्को विधि छान्नुहोस्')),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _retryFromBlankPanel,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFE2E8F0),
                              side: const BorderSide(
                                  color: Color(0xFF475569)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(AppLanguage.tr(
                                'Try Again', 'पुनः प्रयास गर्नुहोस्')),
                          ),
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
              // In the blank-panel state the header carries title +
              // back/close ONLY (user's spec): no countdown timer (it is
              // meaningless when the page itself cannot render), no TEST
              // chip. The session countdown keeps running silently —
              // expiry still applies.
              actions: _blankPanel
                  ? const []
                  : [
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
