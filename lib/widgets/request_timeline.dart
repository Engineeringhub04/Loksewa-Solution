// Shared request timeline — extracted from subscription_detail_screen.dart
// (v1.0.112) so exam/content purchase request pages use the SAME visual
// language: vertical rail, 30px icon nodes, a pulse on the step the request
// is sitting at, and a one-shot pop on completed steps. Nothing else
// animates on a loop (low-end-device friendly).
import 'package:flutter/material.dart';

import '../services/app_language.dart';
import '../theme/app_theme.dart';
import 'status_pill.dart';

enum RequestStepState { done, current, upcoming, failed }

class RequestTimelineStep {
  final String key;
  final String title;
  final DateTime? timestamp;
  final IconData icon;
  final RequestStepState state;
  final Color tone;
  const RequestTimelineStep({
    required this.key,
    required this.title,
    required this.timestamp,
    required this.icon,
    required this.state,
    required this.tone,
  });
}

class RequestTimeline extends StatelessWidget {
  final List<RequestTimelineStep> steps;
  const RequestTimeline({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: steps.asMap().entries.map((entry) {
        return _TimelineRow(
          step: entry.value,
          last: entry.key == steps.length - 1,
        );
      }).toList(),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final RequestTimelineStep step;
  final bool last;
  const _TimelineRow({required this.step, required this.last});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final dim = step.state == RequestStepState.upcoming;
    final node = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: dim ? pal.surfaceAlt : step.tone.withValues(alpha: 0x1F / 0xFF),
        border: Border.all(
          color: dim ? pal.border : step.tone.withValues(alpha: 0x33 / 0xFF),
          width: 0.5,
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child:
          Icon(step.icon, size: 15, color: dim ? pal.textDisabled : step.tone),
    );
    // Current step pulses, done steps pop once (cheap, no loops).
    final animatedNode = step.state == RequestStepState.current
        ? _Pulse(child: node)
        : step.state == RequestStepState.done
            ? _PopIn(child: node)
            : node;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                animatedNode,
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: pal.divider,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : ExpoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      fontSize: ExpoType.body,
                      fontWeight: dim ? FontWeight.normal : FontWeight.w600,
                      color: dim ? pal.textDisabled : pal.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (step.timestamp != null)
                    Text(
                      formatRequestDateTime(step.timestamp),
                      style: TextStyle(
                          fontSize: ExpoType.caption, color: pal.textSecondary),
                    )
                  else if (step.state == RequestStepState.current)
                    StatusPill(label: '•••', color: pal.warning),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one looping animation on the timeline: it marks the step the request
/// is actually sitting at.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1, end: 1.16).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// One-shot scale pop for completed timeline steps. Plays once on build
/// (no repeat loop) — cheap on low-end devices.
class _PopIn extends StatefulWidget {
  final Widget child;
  const _PopIn({required this.child});

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

const List<String> _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "19 Oct 2026, 15:17" — same format the subscription timeline uses.
String formatRequestDateTime(DateTime? dt) {
  if (dt == null) return '—';
  final d = dt.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day.toString().padLeft(2, '0')} ${_monthShort[d.month - 1]} ${d.year}, $hh:$mm';
}

/// Gateway (eSewa/Khalti) request timeline — no admin review step; the
/// worker verifies server-side. Same step language as the subscription
/// detail's gateway timeline: submitted → payment verification → verified
/// & activated. Used by the exam/content purchase request pages.
List<RequestTimelineStep> buildGatewayRequestSteps({
  required ExpoPalette pal,
  DateTime? submittedAt,
  String gatewayStatus = '',
  String status = 'pending',
  String? verifiedBy,
  DateTime? reviewedAt,
  DateTime? activatedAt,
  bool isStaleInitiated = false,
}) {
  String t(String en, String ne) => AppLanguage.tr(en, ne);
  final submitted = RequestTimelineStep(
    key: 'submitted',
    title: t('Payment submitted', 'भुक्तानी पेस भयो'),
    timestamp: submittedAt,
    icon: Icons.send_outlined,
    state: RequestStepState.done,
    tone: pal.info,
  );
  final verified =
      gatewayStatus == 'verified' || status == 'active';
  if (verified) {
    // Who verified is recorded in `verifiedBy` ('gateway' | 'user' |
    // 'admin') — a manual step is inserted so the user can tell HOW this
    // payment was verified.
    final steps = <RequestTimelineStep>[
      submitted,
      RequestTimelineStep(
        key: 'verification',
        title: t('Payment Verification', 'भुक्तानी प्रमाणीकरण'),
        timestamp: reviewedAt,
        icon: Icons.verified_outlined,
        state: RequestStepState.done,
        tone: pal.info,
      ),
    ];
    final by = (verifiedBy ?? 'gateway').toLowerCase();
    if (by == 'user') {
      steps.add(RequestTimelineStep(
        key: 'manual_verification',
        title: t('Manual Verification By User',
            'प्रयोगकर्ताद्वारा म्यानुअल प्रमाणीकरण'),
        timestamp: reviewedAt,
        icon: Icons.touch_app_outlined,
        state: RequestStepState.done,
        tone: pal.info,
      ));
    } else if (by == 'admin') {
      steps.add(RequestTimelineStep(
        key: 'admin_review',
        title:
            t('Waiting for admin review', 'एड्मिन समीक्षाको प्रतीक्षामा'),
        timestamp: reviewedAt,
        icon: Icons.search_outlined,
        state: RequestStepState.done,
        tone: pal.info,
      ));
    }
    steps.add(RequestTimelineStep(
      key: 'activated',
      title: t('Verified & Activated', 'प्रमाणित तथा सक्रिय'),
      timestamp: activatedAt,
      icon: Icons.check_circle_outline,
      state: RequestStepState.done,
      tone: pal.success,
    ));
    return steps;
  }
  if (gatewayStatus == 'cancelled') {
    return [
      submitted,
      RequestTimelineStep(
        key: 'verification',
        title: t('Payment Verification', 'भुक्तानी प्रमाणीकरण'),
        timestamp: null,
        icon: Icons.search_outlined,
        state: RequestStepState.upcoming,
        tone: pal.textDisabled,
      ),
      RequestTimelineStep(
        key: 'cancelled',
        title: t('Payment cancelled', 'भुक्तानी रद्द गरियो'),
        timestamp: null,
        icon: Icons.cancel_outlined,
        state: RequestStepState.failed,
        tone: pal.textDisabled,
      ),
    ];
  }
  // Pending verification: fresh initiated is still in progress; failed or
  // stale initiated means verification failed.
  final failed = gatewayStatus == 'failed' || isStaleInitiated;
  return [
    submitted,
    RequestTimelineStep(
      key: 'verification',
      title: failed
          ? t('Payment Verification Failed', 'भुक्तानी प्रमाणीकरण असफल')
          : t('Payment Verification', 'भुक्तानी प्रमाणीकरण'),
      timestamp: null,
      icon: failed ? Icons.error_outline : Icons.search_outlined,
      state: failed ? RequestStepState.failed : RequestStepState.current,
      tone: failed ? pal.danger : pal.warning,
    ),
    RequestTimelineStep(
      key: 'activated',
      title: t('Verified & Activated', 'प्रमाणित तथा सक्रिय'),
      timestamp: null,
      icon: Icons.check_circle_outline,
      state: RequestStepState.upcoming,
      tone: pal.textDisabled,
    ),
  ];
}

/// Manual (QR) request timeline — mirrors the subscription detail's manual
/// timeline exactly: submitted → waiting for admin review → final outcome.
/// Used by the exam/content purchase request pages for non-gateway records.
List<RequestTimelineStep> buildManualRequestSteps({
  required ExpoPalette pal,
  DateTime? submittedAt,
  String status = 'pending',
  DateTime? reviewedAt,
  DateTime? activatedAt,
  DateTime? expiryDate,
}) {
  String t(String en, String ne) => AppLanguage.tr(en, ne);
  final s = status.toLowerCase();
  final reviewed = reviewedAt != null || s != 'pending';
  late final RequestTimelineStep finalStep;
  switch (s) {
    case 'active':
      finalStep = RequestTimelineStep(
        key: 'approved',
        title: t('Approved & activated', 'स्वीकृत तथा सक्रिय'),
        timestamp: activatedAt ?? reviewedAt,
        icon: Icons.check_circle_outline,
        state: RequestStepState.done,
        tone: pal.success,
      );
    case 'rejected':
      finalStep = RequestTimelineStep(
        key: 'rejected',
        title: t('Rejected by admin', 'एड्मिनद्वारा अस्वीकृत'),
        timestamp: reviewedAt,
        icon: Icons.cancel_outlined,
        state: RequestStepState.failed,
        tone: pal.danger,
      );
    case 'expired':
      finalStep = RequestTimelineStep(
        key: 'expired',
        title: t('Purchase expired', 'खरिदको म्याद सकियो'),
        timestamp: expiryDate,
        icon: Icons.schedule_outlined,
        state: RequestStepState.done,
        tone: pal.textDisabled,
      );
    case 'cancelled':
      finalStep = RequestTimelineStep(
        key: 'cancelled',
        title: t('Cancelled', 'रद्द गरिएको'),
        timestamp: null,
        icon: Icons.cancel_outlined,
        state: RequestStepState.upcoming,
        tone: pal.textDisabled,
      );
    case 'pending':
    default:
      finalStep = RequestTimelineStep(
        key: 'approved',
        title: t('Approved & activated', 'स्वीकृत तथा सक्रिय'),
        timestamp: null,
        icon: Icons.check_circle_outline,
        state: RequestStepState.upcoming,
        tone: pal.textDisabled,
      );
  }
  return [
    RequestTimelineStep(
      key: 'submitted',
      title: t('Payment submitted', 'भुक्तानी पेस भयो'),
      timestamp: submittedAt,
      icon: Icons.send_outlined,
      state: RequestStepState.done,
      tone: pal.info,
    ),
    RequestTimelineStep(
      key: 'review',
      title: t('Waiting for admin review', 'एड्मिन समीक्षाको प्रतीक्षामा'),
      timestamp: reviewedAt,
      icon: Icons.search_outlined,
      state: reviewed ? RequestStepState.done : RequestStepState.current,
      tone: reviewed ? pal.info : pal.warning,
    ),
    finalStep,
  ];
}
