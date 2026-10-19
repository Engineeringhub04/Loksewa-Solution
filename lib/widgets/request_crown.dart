// Shared payment-request crown card — the SAME payment card the
// subscription request detail page uses (status-driven gradient, icon,
// amount hero, method, submitted date). Exam/content purchase request pages
// use this so the visual language is identical everywhere.
//
// Extracted from subscription_detail_screen.dart's _StatusCrown (v1.0.112+)
// — layout, colors and spacing copied exactly; only the status input is a
// plain string so purchase records can use it too.
import 'package:flutter/material.dart';

import '../services/app_language.dart';
import '../theme/app_theme.dart';
import 'request_timeline.dart';

/// Crown gradient per outcome — the page's colour is the request's colour.
const Map<String, List<Color>> requestStatusGradient = {
  'pending': [Color(0xFFB45309), Color(0xFFD97706)],
  'active': [Color(0xFF047857), Color(0xFF0D9488)],
  'rejected': [Color(0xFFB91C1C), Color(0xFFDC2626)],
  'expired': [Color(0xFF475569), Color(0xFF334155)],
  'cancelled': [Color(0xFF475569), Color(0xFF334155)],
};

const Color _onGradient = Colors.white;

/// Status label — same rules as the subscription request page.
String requestStatusLabel({
  required String status,
  bool isFraud = false,
  bool hasDefinitiveFailure = false,
  bool gatewayInitiated = false,
}) {
  final s = status.toLowerCase();
  if (s == 'active') return AppLanguage.tr('Approved', 'स्वीकृत');
  if (s == 'expired') return AppLanguage.tr('Expired', 'म्याद सकिएको');
  if (s == 'rejected') return AppLanguage.tr('Rejected', 'अस्वीकृत');
  if (s == 'cancelled') return AppLanguage.tr('Cancelled', 'रद्द गरिएको');
  // pending
  if (isFraud) return AppLanguage.tr('Verification Failed', 'प्रमाणीकरण असफल');
  if (hasDefinitiveFailure) {
    return AppLanguage.tr('Payment Not Completed', 'भुक्तानी पूरा भएन');
  }
  if (gatewayInitiated) {
    return AppLanguage.tr(
        'Verification Not Confirmed', 'प्रमाणीकरण पुष्टि भएको छैन');
  }
  return AppLanguage.tr('Pending Review', 'समीक्षा बाँकी');
}

IconData requestStatusIcon(String status) {
  switch (status.toLowerCase()) {
    case 'active':
      return Icons.check_circle_outline;
    case 'rejected':
    case 'cancelled':
      return Icons.cancel_outlined;
    case 'expired':
      return Icons.schedule_outlined;
    case 'pending':
    default:
      return Icons.auto_awesome_outlined;
  }
}

String requestMoney(num v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toString();

/// 'App - eSewa' / 'App - Khalti' / 'App - Manual QR' — same rule as the
/// subscription page's platformLabel.
String requestPlatformLabel(String? platform, String method) {
  final p = (platform ?? 'app').toLowerCase();
  final prefix = p == 'web'
      ? AppLanguage.tr('Web', 'वेब')
      : AppLanguage.tr('App', 'एप');
  final methodLabel = method == 'esewa'
      ? 'eSewa'
      : method == 'khalti'
          ? 'Khalti'
          : AppLanguage.tr('Manual QR', 'म्यानुअल QR');
  return '$prefix - $methodLabel';
}

class RequestCrown extends StatelessWidget {
  /// 'pending' | 'active' | 'rejected' | 'expired' | 'cancelled'
  final String status;
  final bool isFraud;
  final bool hasDefinitiveFailure;
  final bool gatewayInitiated;

  /// Item title — exam set name, or "Subject - Chapter" etc. Long titles
  /// wrap to 2 lines with an ellipsis.
  final String title;
  final num amount;
  final String method;
  final DateTime? submittedAt;

  const RequestCrown({
    super.key,
    required this.status,
    this.isFraud = false,
    this.hasDefinitiveFailure = false,
    this.gatewayInitiated = false,
    required this.title,
    required this.amount,
    required this.method,
    this.submittedAt,
  });

  @override
  Widget build(BuildContext context) {
    final gradient =
        requestStatusGradient[status.toLowerCase()] ?? requestStatusGradient['pending']!;
    final label = requestStatusLabel(
      status: status,
      isFraud: isFraud,
      hasDefinitiveFailure: hasDefinitiveFailure,
      gatewayInitiated: gatewayInitiated,
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0x33 / 0xFF),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(ExpoSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _onGradient.withValues(alpha: 0x33 / 0xFF),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(requestStatusIcon(status),
                          size: 22, color: _onGradient),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label.toUpperCase(),
                            style: TextStyle(
                              fontSize: ExpoType.overline,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: _onGradient.withValues(alpha: 0x99 / 0xFF),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: ExpoType.h3,
                              fontWeight: FontWeight.bold,
                              color: _onGradient,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ExpoSpacing.md),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(
                      'Rs. ${requestMoney(amount)}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: _onGradient,
                        height: 1.1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        method.toUpperCase(),
                        style: TextStyle(
                          fontSize: ExpoType.bodySmall,
                          color: _onGradient.withValues(alpha: 0xDB / 0xFF),
                        ),
                      ),
                    ),
                  ],
                ),
                if (submittedAt != null) ...[
                  const SizedBox(height: ExpoSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _onGradient.withValues(alpha: 0x33 / 0xFF),
                        borderRadius: BorderRadius.circular(ExpoRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 12, color: _onGradient),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              formatRequestDateTime(submittedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: ExpoType.caption,
                                fontWeight: FontWeight.w600,
                                color: _onGradient,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ExpoRadius.lg),
                  border: Border.all(
                    color: _onGradient.withValues(alpha: 0x38 / 0xFF),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
