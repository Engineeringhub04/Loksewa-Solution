// Subscription plans + my request history.
//
// Mirrors app/subscription/index.tsx: a status hero (active plan / free plan
// with expiry + days-left + pending-review chips), a "Your Requests" section
// (request rows -> /subscription/:id with status pills and the rejection
// reason quote), staggered plan cards each rendering the SAME ordered feature
// catalogue as a matrix (the plan's own features[] is the truth; unknown
// stored features render in a trailing "extras" group), a yearly savings
// percentage computed from the live plans, the free plan card wearing the
// "Your Free Services" pill (it never claims "Currently Active"), and a
// "We Accept" payment-methods section with the brand logos rendered as a
// subtle watermark (no boxes) — plus a memory-only precache of those logos
// during the page's preloading phase.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/subscription_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/subpage_header.dart';

/// Brand logos — brand marks drawn for a light background, shown as a
/// subtle watermark (reduced opacity, no chips or boxes) directly on the
/// page surface in both themes.
const List<String> _paymentLogos = [
  'https://i.ibb.co/HLpHmnQz/esewa-icon-large.png',
  'https://i.ibb.co/tMHZRHKQ/Khalti-Logo-New-3.png',
  'https://i.ibb.co/YBT7bXZQ/fonepay-logo-png-seeklogo-385625.png',
];

/// Ink for anything drawn ON a plan gradient — fixed, because the gradient is.
const Color _onGradient = Colors.white;

class SubscriptionScreenData {
  final List<SubscriptionPlan> plans;
  final List<SubscriptionRecord> history;
  const SubscriptionScreenData({required this.plans, required this.history});
}

class SubscriptionScreen extends StatefulWidget {
  /// Test seam: overrides the network load.
  final Future<SubscriptionScreenData> Function()? loader;

  const SubscriptionScreen({super.key, this.loader});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<SubscriptionScreenData> _future = _load();

  /// Session guard for the logo warmup below: the payment logos live in
  /// Flutter's in-memory ImageCache only — never on disk — so a cold
  /// start needs exactly one warmup and a reopened page renders them
  /// instantly for the rest of the session.
  static bool _logosPrecached = false;

  /// Warms the in-memory logo cache while the preloading phase is on
  /// screen. Runs once per app run; on an already-warm cache,
  /// [precacheImage] is a cheap no-op anyway.
  void _warmLogoCache(BuildContext context) {
    if (_logosPrecached) return;
    _logosPrecached = true;
    for (final uri in _paymentLogos) {
      // Swallow load failures — the section's errorBuilder covers them.
      // Passing onError keeps a failed precache from being reported to
      // FlutterError (which would trip widget tests that hold the page's
      // loader open).
      precacheImage(NetworkImage(uri), context, onError: (_, __) {});
    }
  }

  Future<SubscriptionScreenData> _load() async {
    if (widget.loader != null) return widget.loader!();
    final uid = AuthService.currentUser?.uid;
    if (uid == null) {
      return const SubscriptionScreenData(plans: [], history: []);
    }
    // Best-effort: sweep an expired active subscription before reading.
    try {
      await SubscriptionService.expireIfPastDue(uid);
    } catch (_) {}
    final results = await Future.wait([
      SubscriptionService.fetchSubscriptionPlans(),
      SubscriptionService.fetchMySubscriptionHistory(uid),
    ]);
    return SubscriptionScreenData(
      plans: results[0] as List<SubscriptionPlan>,
      history: results[1] as List<SubscriptionRecord>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Subscription Details', 'सदस्यता विवरण')),
          Expanded(
            child: FutureBuilder<SubscriptionScreenData>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  // In-memory-only logo warmup: runs during this page's
                  // preloading phase, once per app run.
                  _warmLogoCache(context);
                  return PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr(
                        'Loading Subscription...', 'सदस्यता लोड हुँदैछ...'),
                    hint: AppLanguage.tr('Fetching your purchase history',
                        'खरिद इतिहास ल्याउँदै'),
                  );
                }
                if (snap.hasError) {
                  return _LoadError(
                    onRetry: () {
                      setState(() {
                        _future = _load();
                      });
                    },
                  );
                }
                final data = snap.data!;
                SubscriptionRecord? activeRecord;
                for (final r in data.history) {
                  if (r.status == SubscriptionStatus.active) {
                    activeRecord = r;
                    break;
                  }
                }
                final pendingCount = data.history
                    .where((r) => r.status == SubscriptionStatus.pending)
                    .length;
                final savePercent =
                    SubscriptionService.yearlySavePercent(data.plans);

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _future = _load();
                    });
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(ExpoSpacing.screenPadding),
                    children: [
                      _PlanStatusHero(
                          record: activeRecord, pendingCount: pendingCount),
                      const SizedBox(height: ExpoSpacing.md),
                      if (data.history.isNotEmpty) ...[
                        _RequestsSection(history: data.history),
                        const SizedBox(height: ExpoSpacing.md),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: ExpoSpacing.sm, top: ExpoSpacing.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLanguage.tr(
                                  'Choose Your Plan', 'आफ्नो योजना छान्नुहोस्'),
                              style: const TextStyle(
                                  fontSize: ExpoType.h3,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppLanguage.tr(
                                  'Everything the app offers, and exactly what each plan unlocks.',
                                  'एपले दिने सबै सुविधा, र कुन योजनाले के खोल्छ भन्ने स्पष्ट विवरण।'),
                              style: TextStyle(
                                  fontSize: ExpoType.bodySmall,
                                  color: ExpoPalette.of(context).textSecondary),
                            ),
                          ],
                        ),
                      ),
                      ...data.plans.asMap().entries.map((entry) {
                        final plan = entry.value;
                        final isCurrent = activeRecord != null &&
                            activeRecord.planId == plan.id;
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: ExpoSpacing.md),
                          child: SyllabusEntrance(
                            delayMs: min(entry.key, 8) * 60,
                            child: _PlanCard(
                              plan: plan,
                              isCurrent: isCurrent,
                              savePercent:
                                  plan.billingCycle == BillingCycle.yearly
                                      ? savePercent
                                      : null,
                              onSubscribe: () =>
                                  context.push('/checkout?planId=${plan.id}'),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: ExpoSpacing.sm),
                      const _WeAcceptSection(),
                      const SizedBox(height: ExpoSpacing.lg),
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
}

// ===================== Load error =====================

class _LoadError extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ExpoSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: pal.textDisabled),
            const SizedBox(height: ExpoSpacing.sm),
            Text(
              AppLanguage.tr('Could not load subscription details.',
                  'सदस्यता विवरण लोड गर्न सकिएन।'),
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textSecondary),
            ),
            const SizedBox(height: ExpoSpacing.md),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(AppLanguage.tr('Try again', 'पुनः प्रयास गर्नुहोस्')),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== Status hero =====================

class _PlanStatusHero extends StatelessWidget {
  final SubscriptionRecord? record;
  final int pendingCount;
  const _PlanStatusHero({required this.record, required this.pendingCount});

  int? _daysUntil(DateTime target) {
    final ms = target.difference(DateTime.now()).inMilliseconds;
    return max(0, (ms / (24 * 60 * 60 * 1000)).ceil());
  }

  @override
  Widget build(BuildContext context) {
    final premium = record != null;
    final gradient = premium
        ? const [Color(0xFF0F766E), Color(0xFF1D4ED8), Color(0xFF4338CA)]
        : const [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF475569)];
    final daysLeft =
        record?.expiryDate != null ? _daysUntil(record!.expiryDate!) : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0x2E / 0xFF),
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
                      child: Icon(
                          premium
                              ? Icons.diamond_outlined
                              : Icons.card_giftcard_outlined,
                          size: 22,
                          color: _onGradient),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLanguage.tr('Your Plan', 'तपाईंको योजना')
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: ExpoType.overline,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: _onGradient.withValues(alpha: 0x9E / 0xFF),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            record?.planName ??
                                AppLanguage.tr('Free Plan', 'निःशुल्क योजना'),
                            maxLines: 1,
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
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (record?.expiryDate != null) ...[
                      _GradientChip(
                        icon: Icons.calendar_today_outlined,
                        label:
                            '${AppLanguage.tr('Active until', 'सक्रिय रहने मिति')} · ${_fmtDate(record!.expiryDate)}',
                      ),
                      if (daysLeft != null)
                        _GradientChip(
                          icon: Icons.hourglass_empty_outlined,
                          label: daysLeft <= 1
                              ? AppLanguage.tr('Last day', 'अन्तिम दिन')
                              : AppLanguage.tr(
                                  '$daysLeft days left', '$daysLeft दिन बाँकी'),
                          urgent: daysLeft <= 7,
                        ),
                    ] else
                      _GradientChip(
                        icon: Icons.auto_awesome_outlined,
                        label: AppLanguage.tr(
                            'Upgrade any time — your remaining days carry over.',
                            'जुनसुकै बेला अपग्रेड गर्न सकिन्छ — बाँकी दिन जोडिन्छ।'),
                      ),
                    if (pendingCount > 0)
                      _GradientChip(
                        icon: Icons.schedule_outlined,
                        label:
                            '${AppLanguage.tr('Pending Review', 'समीक्षा हुँदैछ')} · $pendingCount',
                        urgent: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Glass edge: hairline white border over the gradient.
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

class _GradientChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool urgent;
  const _GradientChip(
      {required this.icon, required this.label, this.urgent = false});

  @override
  Widget build(BuildContext context) {
    const urgentInk = Color(0xFF7C2D12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: urgent
            ? const Color(0xFFFBBF24)
            : _onGradient.withValues(alpha: 0x33 / 0xFF),
        borderRadius: BorderRadius.circular(ExpoRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: urgent ? urgentInk : _onGradient),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ExpoType.caption,
                fontWeight: FontWeight.w600,
                color: urgent ? urgentInk : _onGradient,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== Request history =====================

Color _statusToneColor(SubscriptionStatus status, ExpoPalette pal) {
  switch (status) {
    case SubscriptionStatus.active:
      return pal.success;
    case SubscriptionStatus.rejected:
      return pal.danger;
    case SubscriptionStatus.expired:
      return pal.textDisabled;
    case SubscriptionStatus.pending:
      return pal.warning;
  }
}

IconData _statusIcon(SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.active:
      return Icons.check_circle_outline;
    case SubscriptionStatus.rejected:
      return Icons.cancel_outlined;
    case SubscriptionStatus.expired:
      return Icons.schedule_outlined;
    case SubscriptionStatus.pending:
      return Icons.auto_awesome_outlined;
  }
}

String _statusTag(SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.active:
      return AppLanguage.tr('Approved', 'स्वीकृत');
    case SubscriptionStatus.rejected:
      return AppLanguage.tr('Rejected', 'अस्वीकृत');
    case SubscriptionStatus.expired:
      return AppLanguage.tr('Expired', 'म्याद सकिएको');
    case SubscriptionStatus.pending:
      return AppLanguage.tr('New', 'नयाँ');
  }
}

class _RequestsSection extends StatelessWidget {
  final List<SubscriptionRecord> history;
  const _RequestsSection({required this.history});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final tone = pal.info;
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ExpoSpacing.md, ExpoSpacing.md, ExpoSpacing.md, ExpoSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0x1F / 0xFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child:
                      Icon(Icons.receipt_long_outlined, size: 18, color: tone),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLanguage.tr('Your Requests', 'तपाईंका अनुरोधहरू'),
                        style: const TextStyle(
                            fontSize: ExpoType.body,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        AppLanguage.tr(
                            'Every request you have sent, with its live status.',
                            'तपाईंले पठाउनुभएका सबै अनुरोध, हालको स्थितिसहित।'),
                        style: TextStyle(
                            fontSize: ExpoType.caption,
                            color: pal.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...history.asMap().entries.map((entry) {
            final record = entry.value;
            final last = entry.key == history.length - 1;
            return _RequestRow(record: record, last: last);
          }),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final SubscriptionRecord record;
  final bool last;
  const _RequestRow({required this.record, required this.last});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final tone = _statusToneColor(record.status, pal);
    return InkWell(
      onTap: () => context.push('/subscription/${record.id}'),
      borderRadius: BorderRadius.circular(ExpoRadius.md),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: ExpoSpacing.sm),
        padding: const EdgeInsets.symmetric(
            vertical: ExpoSpacing.sm, horizontal: ExpoSpacing.xs),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: last ? Colors.transparent : pal.divider,
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0x1F / 0xFF),
                    border: Border.all(
                        color: tone.withValues(alpha: 0x33 / 0xFF), width: 0.5),
                    borderRadius: BorderRadius.circular(ExpoRadius.md),
                  ),
                  alignment: Alignment.center,
                  child:
                      Icon(_statusIcon(record.status), size: 18, color: tone),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.planName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rs. ${_money(record.amount)} · ${record.method.toUpperCase()}${record.submittedAt != null ? ' · ${_fmtDate(record.submittedAt)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: ExpoType.caption,
                            color: pal.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      StatusPill(label: _statusTag(record.status), color: tone),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: pal.textDisabled),
              ],
            ),
            if (record.status == SubscriptionStatus.rejected &&
                (record.rejectionReason ?? '').isNotEmpty)
              _QuotePanel(
                tone: pal.danger,
                icon: Icons.error_outline,
                child: Text(
                  record.rejectionReason!,
                  style: const TextStyle(fontSize: ExpoType.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ===================== Feature matrix =====================

IconData _groupIcon(String key) {
  switch (key) {
    case 'learning':
      return Icons.menu_book_outlined;
    case 'practice':
      return Icons.description_outlined;
    case 'progress':
      return Icons.bar_chart_outlined;
    case 'community':
      return Icons.people_outline;
    case 'extras':
      return Icons.add_circle_outline;
    default:
      return Icons.star_outline;
  }
}

class _FeatureRow extends StatelessWidget {
  final FeatureMatrixRow row;
  const _FeatureRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final tone = row.included ? pal.success : pal.textDisabled;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: row.included
                  ? tone.withValues(alpha: 0x1F / 0xFF)
                  : Colors.transparent,
              border: Border.all(
                color: row.included
                    ? tone.withValues(alpha: 0x33 / 0xFF)
                    : pal.border,
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              row.included ? Icons.check : Icons.close,
              size: 14,
              color: row.included ? tone : pal.textDisabled,
            ),
          ),
          const SizedBox(width: 10),
          // Excluded rows stay fully legible — dimmed, never struck through.
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(
                fontSize: ExpoType.body,
                fontWeight: row.included ? FontWeight.w500 : FontWeight.normal,
                color: row.included ? pal.textPrimary : pal.textDisabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureGroupBlock extends StatelessWidget {
  final FeatureMatrixGroup group;
  const _FeatureGroupBlock({required this.group});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final complete = group.includedCount == group.rows.length;
    final tone = complete ? pal.success : pal.textDisabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0x1F / 0xFF),
                border: Border.all(
                    color: tone.withValues(alpha: 0x33 / 0xFF), width: 0.5),
                borderRadius: BorderRadius.circular(ExpoRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(_groupIcon(group.icon), size: 13, color: tone),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                AppLanguage.tr(group.titleEn, group.titleNe),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ExpoType.overline,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: pal.textSecondary,
                ),
              ),
            ),
            Text(
              '${group.includedCount}/${group.rows.length}',
              style: TextStyle(
                  fontSize: ExpoType.caption,
                  fontWeight: FontWeight.bold,
                  color: tone),
            ),
          ],
        ),
        const SizedBox(height: ExpoSpacing.xs),
        ...group.rows.map((row) => _FeatureRow(row: row)),
      ],
    );
  }
}

// ===================== Plan card =====================

List<Color> _planGradient(SubscriptionPlan plan) {
  Color parse(String hex) {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  if (plan.billingCycle != BillingCycle.free &&
      plan.colorFrom != null &&
      plan.colorTo != null) {
    try {
      return [parse(plan.colorFrom!), parse(plan.colorTo!)];
    } catch (_) {}
  }
  switch (plan.billingCycle) {
    case BillingCycle.free:
      return const [Color(0xFF64748B), Color(0xFF334155)];
    case BillingCycle.yearly:
      return const [Color(0xFF0F766E), Color(0xFF4338CA)];
    default:
      return const [Color(0xFF7C3AED), Color(0xFFDB2777)];
  }
}

class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isCurrent;
  final int? savePercent;
  final VoidCallback onSubscribe;
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.savePercent,
    required this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final isFree = plan.billingCycle == BillingCycle.free;
    final isYearly = plan.billingCycle == BillingCycle.yearly;
    final gradient = _planGradient(plan);
    final matrix = buildFeatureMatrix(plan.features, AppLanguage.isNepali);
    final included = matrix.fold<int>(0, (s, g) => s + g.includedCount);
    final total = matrix.fold<int>(0, (s, g) => s + g.rows.length);
    final priceSuffix = plan.billingCycle == BillingCycle.monthly
        ? AppLanguage.tr('/ month', '/ महिना')
        : isYearly
            ? AppLanguage.tr('/ year', '/ वर्ष')
            : '';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        // The active plan wears the theme's primary ring; everyone else gets
        // a hairline in their own gradient colour.
        border: Border.all(
          color: isCurrent ? pal.primary : pal.border,
          width: isCurrent ? 2 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0x14 / 0xFF),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== Crown: fixed gradient, fixed ink =====
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _onGradient.withValues(alpha: 0x33 / 0xFF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isFree
                            ? Icons.card_giftcard_outlined
                            : isYearly
                                ? Icons.diamond_outlined
                                : Icons.bolt_outlined,
                        size: 20,
                        color: _onGradient,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: ExpoType.h3,
                              fontWeight: FontWeight.bold,
                              color: _onGradient,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLanguage.tr('$included of $total features',
                                '$total मध्ये $included सुविधा'),
                            style: TextStyle(
                              fontSize: ExpoType.caption,
                              color: _onGradient.withValues(alpha: 0x9E / 0xFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isYearly)
                      _CrownBadge(
                          icon: Icons.star,
                          label: AppLanguage.tr('Best Value', 'उत्तम मूल्य'))
                    else if (!isFree)
                      _CrownBadge(
                          icon: Icons.local_fire_department_outlined,
                          label: AppLanguage.tr(
                              'Most Popular', 'सबैभन्दा लोकप्रिय')),
                  ],
                ),
                const SizedBox(height: ExpoSpacing.md),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    Text(
                      isFree
                          ? AppLanguage.tr('Free', 'निःशुल्क')
                          : 'Rs. ${_money(plan.price)}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: _onGradient,
                        height: 1.1,
                      ),
                    ),
                    if (priceSuffix.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          priceSuffix,
                          style: TextStyle(
                            fontSize: ExpoType.body,
                            color: _onGradient.withValues(alpha: 0xE0 / 0xFF),
                          ),
                        ),
                      ),
                    if (savePercent != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBBF24),
                            borderRadius:
                                BorderRadius.circular(ExpoRadius.pill),
                          ),
                          child: Text(
                            AppLanguage.tr(
                                'Save $savePercent%', '$savePercent% बचत'),
                            style: const TextStyle(
                              fontSize: ExpoType.caption,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7C2D12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // Progress of the matrix, drawn on the crown.
                const SizedBox(height: ExpoSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(ExpoRadius.pill),
                  child: Container(
                    height: 5,
                    color: _onGradient.withValues(alpha: 0x38 / 0xFF),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: total > 0 ? included / total : 0,
                      child: Container(color: _onGradient),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ===== Body: themed surface, tone-coloured marks =====
          Padding(
            padding: const EdgeInsets.all(ExpoSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...matrix.map((group) => Padding(
                      padding: const EdgeInsets.only(bottom: ExpoSpacing.md),
                      child: _FeatureGroupBlock(group: group),
                    )),
                // Three states — and the free card is deliberately NOT one of
                // the paid states. "Currently Active" answers "which plan am I
                // paying for?", so it only ever sits on one card. The free
                // tier is the floor under every account, so it always reads
                // "Your Free Services".
                if (isFree)
                  _StatePill(
                    icon: Icons.card_giftcard_outlined,
                    iconColor: pal.textSecondary,
                    label: AppLanguage.tr(
                        'Your Free Services', 'तपाईंका निःशुल्क सेवा'),
                    labelColor: pal.textSecondary,
                    background: pal.surfaceAlt,
                    border: pal.border,
                  )
                else if (isCurrent)
                  _StatePill(
                    icon: Icons.check_circle_outline,
                    iconColor: pal.success,
                    label: AppLanguage.tr('Currently Active', 'हाल सक्रिय'),
                    labelColor: pal.success,
                    background: pal.success.withValues(alpha: 0x1F / 0xFF),
                    border: pal.success.withValues(alpha: 0x33 / 0xFF),
                    bold: true,
                  )
                else
                  _SubscribeButton(
                    gradient: gradient,
                    label: AppLanguage.tr(
                        'Subscribe Now', 'अहिले सदस्यता लिनुहोस्'),
                    onPress: onSubscribe,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CrownBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CrownBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _onGradient.withValues(alpha: 0x33 / 0xFF),
        borderRadius: BorderRadius.circular(ExpoRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: _onGradient),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: ExpoType.overline,
              fontWeight: FontWeight.bold,
              color: _onGradient,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final Color background;
  final Color border;
  final bool bold;
  const _StatePill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.background,
    required this.border,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border, width: 0.5),
        borderRadius: BorderRadius.circular(ExpoRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: ExpoType.bodySmall,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// The CTA carries the plan's own gradient, so the button a reader presses is
/// visibly the same object as the crown they just read.
class _SubscribeButton extends StatefulWidget {
  final List<Color> gradient;
  final String label;
  final VoidCallback onPress;
  const _SubscribeButton(
      {required this.gradient, required this.label, required this.onPress});

  @override
  State<_SubscribeButton> createState() => _SubscribeButtonState();
}

class _SubscribeButtonState extends State<_SubscribeButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onPress,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.gradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(ExpoRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.diamond_outlined, size: 17, color: _onGradient),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: ExpoType.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: _onGradient,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================== We Accept =====================

class _WeAcceptSection extends StatelessWidget {
  const _WeAcceptSection();

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Watermark-style payment logos: NO boxes, NO borders — the brand
    // marks sit directly on the page background at reduced opacity so
    // they read as a subtle watermark in both themes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: pal.success.withValues(alpha: 0x1F / 0xFF),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.credit_card_outlined,
                  size: 18, color: pal.success),
            ),
            const SizedBox(width: 12),
            Text(
              AppLanguage.tr('We Accept', 'हामी स्वीकार गर्छौं'),
              style: const TextStyle(
                  fontSize: ExpoType.body, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: ExpoSpacing.sm),
        Row(
          children: _paymentLogos
              .map((uri) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Opacity(
                        // A touch stronger in dark mode so the
                        // light-background brand marks stay legible.
                        opacity: isDark ? 0.7 : 0.55,
                        child: Image.network(
                          uri,
                          height: 34,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox(height: 34),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ===================== Shared bits =====================

/// Tinted quote panel with a tone spine. Mirrors QuotePanel.
class _QuotePanel extends StatelessWidget {
  final Color tone;
  final IconData icon;
  final Widget child;
  const _QuotePanel({
    required this.tone,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: ExpoSpacing.sm),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0x14 / 0xFF),
        border:
            Border.all(color: tone.withValues(alpha: 0x33 / 0xFF), width: 0.5),
        borderRadius: BorderRadius.circular(ExpoRadius.md),
      ),
      // Clip the spine to the card's curve: the spine's square inner
      // corners would otherwise poke ~2px past the rounded corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ExpoRadius.md),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(ExpoRadius.md),
                    bottomLeft: Radius.circular(ExpoRadius.md),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(ExpoSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 15, color: tone),
                      const SizedBox(height: 6),
                      child,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _money(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

const List<String> _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

String _fmtDate(DateTime? dt) {
  if (dt == null) return '—';
  final d = dt.toLocal();
  return '${d.day.toString().padLeft(2, '0')} ${_monthShort[d.month - 1]} ${d.year}';
}
