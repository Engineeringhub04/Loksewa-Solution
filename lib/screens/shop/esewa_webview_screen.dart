import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Result returned by [EsewaWebViewScreen] via Navigator.pop.
class EsewaWebResult {
  /// 'success' | 'failure' | 'cancelled'
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

  const EsewaWebViewScreen({
    super.key,
    required this.endpoint,
    required this.fields,
    required this.testMode,
  });

  @override
  State<EsewaWebViewScreen> createState() => _EsewaWebViewScreenState();
}

class _EsewaWebViewScreenState extends State<EsewaWebViewScreen> {
  static const _successPrefix = 'https://kbr.com.np/payments/esewa/success';
  static const _failurePrefix = 'https://kbr.com.np/payments/esewa/failure';

  bool _loadingPage = true;
  bool _done = false;

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
    Navigator.of(context).pop(r);
  }

  Future<NavigationActionPolicy?> _onShouldOverride(
      InAppWebViewController controller, NavigationAction action) async {
    final raw = action.request.url?.toString() ?? '';
    if (raw.startsWith(_successPrefix)) {
      final uri = Uri.tryParse(raw);
      final data = uri?.queryParameters['data'];
      if (data != null && data.isNotEmpty) {
        _finish(EsewaWebResult(status: 'success', data: data));
      } else {
        _finish(EsewaWebResult(
            status: 'failure',
            message: AppLanguage.tr('eSewa returned no payment data.',
                'eSewa ले भुक्तानी डेटा फर्काएन।')));
      }
      return NavigationActionPolicy.CANCEL;
    }
    if (raw.startsWith(_failurePrefix)) {
      final uri = Uri.tryParse(raw);
      final msg = uri?.queryParameters['message'];
      _finish(EsewaWebResult(
          status: 'failure',
          message: msg?.isNotEmpty == true
              ? msg
              : AppLanguage.tr(
                  'Payment was not completed.', 'भुक्तानी पूरा भएन।')));
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      appBar: AppBar(
        backgroundColor: pal.surface,
        foregroundColor: pal.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _finish(const EsewaWebResult(status: 'cancelled')),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLanguage.tr('eSewa Payment', 'eSewa भुक्तानी'),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (widget.testMode) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.5)),
                ),
                child: Text(AppLanguage.tr('TEST', 'टेस्ट'),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.amber)),
              ),
            ],
          ],
        ),
        centerTitle: true,
      ),
      body: Stack(
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
    );
  }
}
