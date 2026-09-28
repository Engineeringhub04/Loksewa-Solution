import 'dart:async';

import 'package:flutter/material.dart';

import '../services/exam_service.dart';
import 'app_toast.dart';

/// Which slot of the Daily Test feed a card is in.
enum DailyTestSlot { upcoming, today, missed, completed }

String dailyTestSlotLabel(DailyTestSlot slot) {
  switch (slot) {
    case DailyTestSlot.upcoming:
      return "UPCOMING";
    case DailyTestSlot.today:
      return "TODAY'S TEST";
    case DailyTestSlot.missed:
      return "MISSED";
    case DailyTestSlot.completed:
      return "COMPLETED";
  }
}

// ---------------------------------------------------------------------------
// Card palettes — exact port of CARD_PALETTES / paletteFor in
// DailyTestModelCard.tsx. Colour belongs to the model (FNV-1a of its id), not
// the slot; missed cards keep their hue but are pulled 0.66 toward slate.
// ---------------------------------------------------------------------------

const List<List<Color>> _cardPalettes = [
  [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF0B1F5B)],
  [Color(0xFF4F46E5), Color(0xFF3730A3), Color(0xFF1E1B4B)],
  [Color(0xFF7C3AED), Color(0xFF5B21B6), Color(0xFF2A0E4F)],
  [Color(0xFFA21CAF), Color(0xFF701A75), Color(0xFF2E0A31)],
  [Color(0xFF0E7490), Color(0xFF155E75), Color(0xFF082F3F)],
  [Color(0xFF0369A1), Color(0xFF075985), Color(0xFF082F49)],
  [Color(0xFF4338CA), Color(0xFF312E81), Color(0xFF171449)],
  [Color(0xFF6D28D9), Color(0xFF4C1D95), Color(0xFF241063)],
];

const Color _missedMix = Color(0xFF1E293B);
const double _missedMixAmount = 0.66;

int _hashString(String value) {
  var hash = 2166136261;
  for (var i = 0; i < value.length; i++) {
    hash ^= value.codeUnitAt(i);
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  // Match JS Math.imul signed semantics before Math.abs().
  if (hash >= 0x80000000) hash -= 0x100000000;
  return hash.abs();
}

Color _mix(Color from, Color to, double amount) {
  int blend(double x, double y) =>
      ((x + (y - x) * amount) * 255).round().clamp(0, 255);
  return Color.fromARGB(
      255, blend(from.r, to.r), blend(from.g, to.g), blend(from.b, to.b));
}

/// Gradient stops for a model card; missed slots are pulled toward slate.
List<Color> dailyTestPaletteFor(String modelId, DailyTestSlot slot) {
  final base = _cardPalettes[_hashString(modelId) % _cardPalettes.length];
  if (slot != DailyTestSlot.missed) return base;
  return base.map((c) => _mix(c, _missedMix, _missedMixAmount)).toList();
}

// ---------------------------------------------------------------------------
// Category meta — easy/medium/hard chip colours and icons.
// ---------------------------------------------------------------------------

class DailyTestCategoryMeta {
  final String label;
  final Color color;
  final IconData icon;

  const DailyTestCategoryMeta(this.label, this.color, this.icon);
}

DailyTestCategoryMeta dailyTestCategoryMeta(String category) {
  switch (category.toLowerCase()) {
    case 'easy':
      return const DailyTestCategoryMeta(
          'Easy', Color(0xFF86EFAC), Icons.eco);
    case 'hard':
      return const DailyTestCategoryMeta(
          'Hard', Color(0xFFFCA5A5), Icons.warning_amber_rounded);
    default:
      return const DailyTestCategoryMeta(
          'Medium', Color(0xFFFDE68A), Icons.local_fire_department);
  }
}

// ---------------------------------------------------------------------------
// Big gradient model card (the carousel slides).
// ---------------------------------------------------------------------------

class DailyTestCard extends StatelessWidget {
  final DailyTestModel model;
  final DailyTestSlot slot;
  final bool completed;
  final int? scorePercent;
  final bool hasPremiumAccess;
  final bool demo;
  final int? indexInDay;
  final int? totalInDay;
  final String? todayKey;
  final VoidCallback onPrimaryPress;
  final VoidCallback onSubscribePress;

  const DailyTestCard({
    super.key,
    required this.model,
    required this.slot,
    this.completed = false,
    this.scorePercent,
    this.hasPremiumAccess = false,
    this.demo = false,
    this.indexInDay,
    this.totalInDay,
    this.todayKey,
    required this.onPrimaryPress,
    required this.onSubscribePress,
  });

  bool get _isMissed => slot == DailyTestSlot.missed;

  /// A missed test is locked by date, so premium gating is irrelevant to it —
  /// the subscribe CTA would be a false promise.
  bool get _locked =>
      model.isPro && !hasPremiumAccess && slot != DailyTestSlot.missed;

  @override
  Widget build(BuildContext context) {
    final palette = dailyTestPaletteFor(model.id, slot);
    final isLive = slot == DailyTestSlot.today && !completed;
    final category = dailyTestCategoryMeta(model.category);
    final dateLabel = model.testDate.isNotEmpty
        ? (todayKey != null
            ? relativeDayLabel(model.testDate, todayKey)
            : formatDateKeyShort(model.testDate))
        : '';

    final meta = demo
        ? const [
            _MetaChip(Icons.auto_awesome, 'Fresh questions'),
            _MetaChip(Icons.timer_outlined, 'Timed per question'),
            _MetaChip(Icons.notifications_outlined, 'Unlocks at 12:00 AM'),
          ]
        : [
            _MetaChip(
                Icons.help_outline, '${model.questions.length} Qs'),
            _MetaChip(Icons.timer_outlined,
                '${model.perQuestionTimeSeconds}s / Q'),
            _MetaChip(Icons.hourglass_empty,
                formatDailyTestDuration(totalTestSeconds(model))),
            _MetaChip(
                model.negativeMarking
                    ? Icons.remove_circle_outline
                    : Icons.check_circle_outline,
                model.negativeMarking
                    ? 'Neg -${(model.negativeMarkPercent * 100).round()}%'
                    : 'No neg. marking'),
          ];

    final cta = _cta();
    final ctaInk = cta.muted
        ? const Color.fromRGBO(255, 255, 255, 0.9)
        : cta.green
            ? Colors.white
            : palette.first;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.first.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Glow decorations.
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              left: 60,
              bottom: -55,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status + tier row.
                  Row(
                    children: [
                      _pill(_statusPill(isLive)),
                      const Spacer(),
                      _pill(_tierPill()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Eyebrow: slot · release date · test X of Y.
                  _Eyebrow(
                    slotLabel: dailyTestSlotLabel(slot),
                    dateLabel: dateLabel,
                    indexInDay: indexInDay,
                    totalInDay: totalInDay,
                  ),
                  const SizedBox(height: 4),
                  // Title + score badge.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          model.modelName.isNotEmpty
                              ? model.modelName
                              : model.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (completed && scorePercent != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$scorePercent%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Category row.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(_PillData(
                          icon: category.icon,
                          iconColor: category.color,
                          text: category.label,
                          textColor: category.color,
                          soft: true)),
                      if (!demo)
                        _pill(_PillData(
                            icon: Icons.emoji_events_outlined,
                            iconColor: const Color(0xFFE0E7FF),
                            text: 'Pass ${model.passPercent}%',
                            textColor: const Color(0xFFE0E7FF),
                            soft: true)),
                      if (_locked && model.price > 0)
                        _pill(_PillData(
                            icon: Icons.sell_outlined,
                            iconColor: const Color(0xFFFDE68A),
                            text:
                                'Rs. ${model.price == model.price.roundToDouble() ? model.price.toInt() : model.price}',
                            textColor: const Color(0xFFFEF3C7),
                            soft: true)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Exam config chips.
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: meta
                        .map((m) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(m.icon,
                                    size: 13,
                                    color: Colors.white
                                        .withValues(alpha: 0.82)),
                                const SizedBox(width: 5),
                                Text(
                                  m.label,
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.82),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ))
                        .toList(),
                  ),
                  // Pushes the CTA to the bottom edge so every card in the
                  // strip lines up.
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: Opacity(
                      opacity: cta.onPress == null ? 1 : 1,
                      child: ElevatedButton.icon(
                        onPressed: cta.onPress,
                        icon: Icon(cta.icon, size: 16, color: ctaInk),
                        label: Text(cta.label,
                            style: TextStyle(
                                color: ctaInk,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cta.muted
                              ? Colors.transparent
                              : cta.green
                                  ? const Color(0xFF16A34A)
                                  : Colors.white,
                          foregroundColor: ctaInk,
                          disabledBackgroundColor: cta.muted
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: 0.5),
                          elevation: 0,
                          side: cta.muted
                              ? const BorderSide(
                                  color: Color.fromRGBO(255, 255, 255, 0.5))
                              : BorderSide.none,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _PillData _statusPill(bool isLive) {
    if (_isMissed) {
      return const _PillData(
          icon: Icons.lock,
          iconColor: Color(0xFFFECACA),
          text: 'Missed',
          textColor: Color(0xFFFEE2E2),
          bg: Color.fromRGBO(0, 0, 0, 0.30));
    }
    if (isLive) {
      return const _PillData(
          icon: null,
          iconColor: Colors.transparent,
          text: 'LIVE',
          textColor: Color(0xFF7F1D1D),
          bg: Color(0xFFFCA5A5),
          live: true);
    }
    if (completed) {
      return const _PillData(
          icon: Icons.check_circle,
          iconColor: Colors.white,
          text: 'Completed',
          textColor: Colors.white,
          bg: Color(0xFF16A34A));
    }
    return const _PillData(
        icon: Icons.calendar_today_outlined,
        iconColor: Color(0xFFE0E7FF),
        text: 'Upcoming',
        textColor: Color(0xFFE0E7FF),
        soft: true);
  }

  _PillData _tierPill() {
    if (model.isPro && !demo) {
      if (hasPremiumAccess) {
        return const _PillData(
            icon: Icons.verified_user,
            iconColor: Color(0xFFBBF7D0),
            text: 'Purchased (active)',
            textColor: Color(0xFFDCFCE7),
            bg: Color.fromRGBO(22, 163, 74, 0.35));
      }
      return const _PillData(
          icon: Icons.diamond,
          iconColor: Color(0xFFFFEDD5),
          text: 'Premium',
          textColor: Color(0xFFFFF7ED),
          bg: Color.fromRGBO(217, 119, 6, 0.45));
    }
    return const _PillData(
        icon: Icons.card_giftcard,
        iconColor: Color(0xFFBBF7D0),
        text: 'Free',
        textColor: Color(0xFFDCFCE7),
        soft: true);
  }

  _CtaData _cta() {
    if (_isMissed) {
      return const _CtaData(
          label: 'Missed - Locked',
          icon: Icons.lock,
          onPress: null,
          muted: true);
    }
    if (_locked) {
      return _CtaData(
          label: 'Go to Subscription',
          icon: Icons.credit_card_outlined,
          onPress: onSubscribePress,
          muted: false);
    }
    if (completed) {
      return _CtaData(
          label: 'View Result',
          icon: Icons.visibility_outlined,
          onPress: onPrimaryPress,
          muted: false,
          green: true);
    }
    return _CtaData(
        label: 'Start Test',
        icon: Icons.play_arrow,
        onPress: onPrimaryPress,
        muted: false);
  }

  Widget _pill(_PillData p) {
    if (p.live) {
      return _LivePill(bg: p.bg ?? Colors.white);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.bg ??
            (p.soft
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.icon != null) Icon(p.icon, size: 12, color: p.iconColor),
          if (p.icon != null) const SizedBox(width: 5),
          Text(p.text,
              style: TextStyle(
                  color: p.textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PillData {
  final IconData? icon;
  final Color iconColor;
  final String text;
  final Color textColor;
  final Color? bg;
  final bool soft;
  final bool live;

  const _PillData(
      {this.icon,
      required this.iconColor,
      required this.text,
      required this.textColor,
      this.bg,
      this.soft = false,
      this.live = false});
}

class _CtaData {
  final String label;
  final IconData icon;
  final VoidCallback? onPress;
  final bool muted;
  final bool green;

  const _CtaData(
      {required this.label,
      required this.icon,
      required this.onPress,
      this.muted = false,
      this.green = false});
}

class _MetaChip {
  final IconData icon;
  final String label;

  const _MetaChip(this.icon, this.label);
}

/// The pulsing LIVE pill — the whole pill breathes, not just the dot.
class _LivePill extends StatefulWidget {
  final Color bg;

  const _LivePill({required this.bg});

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill> {
  double _opacity = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 620), (_) {
      if (mounted) setState(() => _opacity = _opacity == 1 ? 0.45 : 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 620),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.bg,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
                color: Color(0xFFEF4444), blurRadius: 8, spreadRadius: 1)
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: Color(0xFF7F1D1D), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Text('LIVE',
                style: TextStyle(
                    color: Color(0xFF7F1D1D),
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String slotLabel;
  final String dateLabel;
  final int? indexInDay;
  final int? totalInDay;

  const _Eyebrow(
      {required this.slotLabel,
      required this.dateLabel,
      this.indexInDay,
      this.totalInDay});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        color: Color.fromRGBO(255, 255, 255, 0.85),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      children: [
        Text(slotLabel, style: style),
        if (dateLabel.isNotEmpty) ...[
          Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                  color: Colors.white70, shape: BoxShape.circle)),
          const Icon(Icons.calendar_today,
              size: 11, color: Color.fromRGBO(255, 255, 255, 0.72)),
          Text(dateLabel, style: style),
        ],
        if (indexInDay != null &&
            totalInDay != null &&
            totalInDay! > 1) ...[
          Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                  color: Colors.white70, shape: BoxShape.circle)),
          Text('TEST $indexInDay OF $totalInDay', style: style),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Flat mini row (the "All Models" list).
// ---------------------------------------------------------------------------

class DailyTestMiniCard extends StatelessWidget {
  final DailyTestModel model;
  final DailyTestSlot slot;
  final bool completed;
  final int? scorePercent;
  final bool hasPremiumAccess;
  final String? todayKey;
  final VoidCallback? onTap;

  const DailyTestMiniCard({
    super.key,
    required this.model,
    required this.slot,
    this.completed = false,
    this.scorePercent,
    this.hasPremiumAccess = false,
    this.todayKey,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locked =
        model.isPro && !hasPremiumAccess && slot != DailyTestSlot.missed;

    late final Color tone;
    late final IconData icon;
    late final String label;
    if (completed) {
      tone = const Color(0xFF16A34A);
      icon = Icons.check_circle;
      label = 'Completed';
    } else if (slot == DailyTestSlot.today) {
      tone = const Color(0xFF2563EB);
      icon = Icons.play_circle_fill;
      label = 'Live now';
    } else if (slot == DailyTestSlot.upcoming) {
      tone = const Color(0xFF6366F1);
      icon = Icons.schedule;
      label = 'Upcoming';
    } else {
      tone = const Color(0xFFDC2626);
      icon = Icons.lock;
      label = 'Missed';
    }

    final dateLabel = model.testDate.isNotEmpty
        ? (todayKey != null
            ? relativeDayLabel(model.testDate, todayKey)
            : formatDateKeyShort(model.testDate))
        : '';

    final surface =
        isDark ? const Color(0xFF151D2E) : Colors.white;
    final border =
        isDark ? const Color(0xFF26314B) : const Color(0xFFE5E7EB);
    final disabled =
        isDark ? const Color(0xFF64748B) : const Color(0xFF9CA3AF);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -14,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 17, color: tone),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(label.toUpperCase(),
                              style: TextStyle(
                                  color: tone,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                          if (dateLabel.isNotEmpty) ...[
                            Container(
                                width: 3,
                                height: 3,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                decoration: BoxDecoration(
                                    color: disabled,
                                    shape: BoxShape.circle)),
                            Text(dateLabel,
                                style: TextStyle(
                                    color: secondary, fontSize: 11)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        model.modelName.isNotEmpty
                            ? model.modelName
                            : model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 1),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        children: [
                          Text('${model.questions.length} Qs',
                              style: TextStyle(
                                  color: secondary, fontSize: 11)),
                          Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                  color: disabled, shape: BoxShape.circle)),
                          Text('Pass ${model.passPercent}%',
                              style: TextStyle(
                                  color: secondary, fontSize: 11)),
                          if (model.isPro) ...[
                            Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                    color: disabled,
                                    shape: BoxShape.circle)),
                            Text(
                              hasPremiumAccess
                                  ? 'Premium · active'
                                  : 'Premium',
                              style: TextStyle(
                                  color: hasPremiumAccess
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFD97706),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // One trailing signal only: the score if there is one,
                // otherwise why the row cannot be opened, otherwise "go".
                _trailing(
                    completed: completed,
                    scorePercent: scorePercent,
                    locked: locked,
                    slot: slot,
                    secondary: secondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _trailing(
      {required bool completed,
      required int? scorePercent,
      required bool locked,
      required DailyTestSlot slot,
      required Color secondary}) {
    if (completed && scorePercent != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF16A34A).withValues(alpha: 0.08),
          border: Border.all(color: const Color(0xFF16A34A)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('$scorePercent%',
            style: const TextStyle(
                color: Color(0xFF16A34A),
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
    }
    if (locked) {
      return const Icon(Icons.diamond,
          size: 16, color: Color(0xFFD97706));
    }
    if (slot == DailyTestSlot.missed) {
      return Icon(Icons.lock, size: 15, color: secondary);
    }
    if (slot == DailyTestSlot.upcoming) {
      return Icon(Icons.lock_outline, size: 15, color: secondary);
    }
    return Icon(Icons.chevron_right, size: 17, color: secondary);
  }
}

// ---------------------------------------------------------------------------
// Rules dialog — "Check the rules before you begin", chips row, numbered rules,
// "I understood (Start)" / "Not now". Returns true when the user confirms.
// ---------------------------------------------------------------------------

Future<bool> showDailyTestRulesDialog(
    BuildContext context, DailyTestModel model) {
  final rules = buildDailyTestRules(model);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
  final text = isDark ? Colors.white : const Color(0xFF0F172A);
  final secondary =
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  final chipBg =
      isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF);

  final chips = [
    _RuleChip(Icons.help_outline, '${model.questions.length} questions'),
    _RuleChip(Icons.timer_outlined,
        '${model.perQuestionTimeSeconds}s/question'),
    _RuleChip(Icons.hourglass_empty,
        formatDailyTestDuration(totalTestSeconds(model))),
    _RuleChip(
        model.negativeMarking
            ? Icons.remove_circle_outline
            : Icons.check_circle_outline,
        model.negativeMarking ? 'Negative marking' : 'No negative marking'),
  ];

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      backgroundColor: surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.rule,
                        size: 20, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Check the rules before you begin',
                      style: TextStyle(
                          color: text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: chips
                    .map((c) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: chipBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(c.icon,
                                  size: 13,
                                  color: const Color(0xFF2563EB)),
                              const SizedBox(width: 6),
                              Text(c.label,
                                  style: TextStyle(
                                      color: secondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < rules.length; i++)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                margin:
                                    const EdgeInsets.only(top: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB)
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        color: Color(0xFF2563EB),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(rules[i],
                                    style: TextStyle(
                                        color: secondary,
                                        fontSize: 13,
                                        height: 1.45)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                      ),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: const Icon(Icons.check,
                          size: 16, color: Colors.white),
                      label: const Text('I understood (Start)',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ).then((v) => v ?? false);
}

class _RuleChip {
  final IconData icon;
  final String label;

  const _RuleChip(this.icon, this.label);
}

/// Shared "no test today" slim strip with a live countdown to midnight.
class DailyTestNoTestStrip extends StatelessWidget {
  final String countdown;

  const DailyTestNoTestStrip({super.key, required this.countdown});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151D2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark
                ? const Color(0xFF26314B)
                : const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.access_time,
                size: 17, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'No test today — Next test unlocks tomorrow',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color:
                  const Color(0xFF2563EB).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              countdown,
              style: const TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared history card (landing's recent section + history page rows use it).
class DailyTestHistoryCard extends StatelessWidget {
  final DailyTestActivity activity;
  final VoidCallback? onTap;

  const DailyTestHistoryCard(
      {super.key, required this.activity, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final passed = activity.isPassed;
    final accent =
        passed ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final border =
        isDark ? const Color(0xFF26314B) : const Color(0xFFE5E7EB);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    final d = DateTime.fromMillisecondsSinceEpoch(activity.completedAt);
    final dateStr =
        '${d.day} ${_monthName(d.month)} ${d.year}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -14,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        activity.modelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(dateStr,
                        style: TextStyle(
                            color: secondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Ring(percent: activity.score, accent: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              passed ? 'PASSED' : 'FAILED',
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _tag('${activity.totalQuestions} Qs',
                                  secondary),
                              _tag(
                                  '${activity.correct} correct',
                                  secondary),
                              _tag(
                                  formatDailyTestDuration(
                                      activity.timeTakenSeconds),
                                  secondary),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: secondary),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 0),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      );
}

String _monthName(int m) => const [
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
    ][m - 1];

class _Ring extends StatelessWidget {
  final int percent;
  final Color accent;

  const _Ring({required this.percent, required this.accent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: (percent.clamp(0, 100)) / 100,
              strokeWidth: 6,
              backgroundColor: isDark
                  ? const Color(0xFF26314B)
                  : const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          Text('$percent%',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Toast for schedule-blocked taps on the models list.
void dailyTestScheduleToast(
    BuildContext context, DailyTestModel model, String todayKey) {
  if (model.testDate.isEmpty) {
    showToast(context, 'Test not scheduled.', ToastVariant.info);
  } else if (model.testDate.compareTo(todayKey) > 0) {
    showToast(
        context,
        'Not unlocked yet. This test unlocks on ${formatDateKeyShort(model.testDate)} at 12:00 AM.',
        ToastVariant.info);
  } else {
    showToast(
        context,
        'Test missed. This test was only available on ${formatDateKeyShort(model.testDate)}.',
        ToastVariant.warning);
  }
}
