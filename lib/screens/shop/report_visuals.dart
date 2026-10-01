import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Shared look-up for the report screens (user list + detail).
///
/// Mirrors `src/components/report/reportVisuals.ts` from the Expo app:
/// one place that decides which icon and which tone goes with a report
/// source / review status / target type, so the screens never drift apart.
///
/// Language rule: [labelEn] is pure English, [labelNe] is pure Devanagari
/// Nepali. Callers render them through `AppLanguage.tr(labelEn, labelNe)`.
enum ReportTone { primary, accent, info, success, warning, danger, neutral }

class ReportVisual {
  final IconData icon;
  final ReportTone tone;
  final String labelEn;
  final String labelNe;
  const ReportVisual(this.icon, this.tone, this.labelEn, this.labelNe);
}

Color reportToneColor(ExpoPalette pal, ReportTone tone) {
  switch (tone) {
    case ReportTone.primary:
      return pal.primary;
    case ReportTone.accent:
      return pal.accent;
    case ReportTone.info:
      return pal.info;
    case ReportTone.success:
      return pal.success;
    case ReportTone.warning:
      return pal.warning;
    case ReportTone.danger:
      return pal.danger;
    case ReportTone.neutral:
      return pal.textSecondary;
  }
}

/// Tone + icon + label per review state — the one place that decides
/// "resolved is green". Mirrors `statusTone` / `statusIcon` / `statusKey`.
ReportVisual reportStatusVisual(String status) {
  switch (status) {
    case 'resolved':
      return const ReportVisual(Icons.check_circle_outlined,
          ReportTone.success, 'Resolved', 'समाधान भयो');
    case 'dismissed':
      return const ReportVisual(Icons.cancel_outlined, ReportTone.danger,
          'Dismissed', 'खारेज गरियो');
    case 'reviewed':
      return const ReportVisual(Icons.visibility_outlined, ReportTone.info,
          'Reviewed', 'समीक्षा भयो');
    default:
      return const ReportVisual(Icons.schedule_outlined, ReportTone.warning,
          'Pending review', 'समीक्षा बाँकी');
  }
}

/// Icon + tone per report origin. A new source falls back to `other`.
/// Mirrors `sourceVisual`.
ReportVisual reportSourceVisual(String source) {
  switch (source) {
    case 'question':
      return const ReportVisual(Icons.help_outline, ReportTone.primary,
          'Question', 'प्रश्न');
    case 'discussion':
      return const ReportVisual(Icons.forum_outlined, ReportTone.accent,
          'Discussion', 'छलफल');
    case 'comment':
      return const ReportVisual(Icons.chat_bubble_outline, ReportTone.info,
          'Comment', 'टिप्पणी');
    case 'app':
      return const ReportVisual(Icons.smartphone_outlined, ReportTone.danger,
          'App', 'एप');
    case 'read':
      return const ReportVisual(
          Icons.book_outlined, ReportTone.success, 'Reading', 'पठन');
    case 'article':
      return const ReportVisual(Icons.newspaper_outlined, ReportTone.warning,
          'Article', 'लेख');
    default:
      return const ReportVisual(Icons.flag_outlined, ReportTone.neutral,
          'Other', 'अन्य');
  }
}

/// Icon per target type. Mirrors `targetIcon`.
IconData reportTargetIcon(String targetType) {
  switch (targetType) {
    case 'question':
      return Icons.help_outline;
    case 'post':
      return Icons.forum_outlined;
    case 'reply':
      return Icons.reply_outlined;
    case 'app':
      return Icons.smartphone_outlined;
    case 'content':
      return Icons.description_outlined;
    default:
      return Icons.chat_bubble_outline;
  }
}

/// Label per target type. Mirrors `targetKey` — including its quirk that
/// `app` / `content` fall through to the Comment label.
ReportVisual reportTargetVisual(String targetType) {
  switch (targetType) {
    case 'question':
      return ReportVisual(reportTargetIcon(targetType), ReportTone.neutral,
          'Question', 'प्रश्न');
    case 'post':
      return ReportVisual(reportTargetIcon(targetType), ReportTone.neutral,
          'Post', 'पोस्ट');
    case 'reply':
      return ReportVisual(reportTargetIcon(targetType), ReportTone.neutral,
          'Reply', 'रिप्लाइ');
    default:
      return ReportVisual(reportTargetIcon(targetType), ReportTone.neutral,
          'Comment', 'कमेन्ट');
  }
}
