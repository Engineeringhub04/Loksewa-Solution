import 'package:flutter/material.dart';

import '../../services/analytics/analytics_strings.dart';
import '../../services/analytics/analytics_types.dart';
import '../../services/app_language.dart';

/// Shared bilingual strings and tiny helpers for the analytics widgets.
///
/// Every user-facing string goes through [AppLanguage.tr] (pure English /
/// pure Devanagari Nepali), mirroring the values in the React app's i18n —
/// the screen and the widgets all read from these.

/// Parses a '#RRGGBB' source colour into an opaque [Color].
Color analyticsHex(String hex) {
  final clean = hex.startsWith('#') ? hex.substring(1) : hex;
  final value = int.tryParse(clean, radix: 16) ?? 0x000000;
  return Color(0xFF000000 | value);
}

/// Turns a theme [Color] into a '#RRGGBB' string for the data layer, which
/// carries milestone palette colours as hex.
String colorToHex(Color color) {
  final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2).toUpperCase()}';
}

/// Trims a trailing ".0" so whole percentages don't read as false precision.
String formatPercent(double value) {
  final safe = value.isFinite ? value : 0.0;
  final rounded = (safe * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}%'
      : '${rounded.toStringAsFixed(1)}%';
}

/// Keeps four-digit figures from pushing hero strip cells out of alignment.
String formatCount(num value) {
  final safe = value.isFinite ? value.round() : 0;
  if (safe >= 10000) return '${(safe / 1000).toStringAsFixed(1)}k';
  return '$safe';
}

/// Display name for each learning source (mirrors `analytics.sources`).
String analyticsSourceLabel(AnalyticsSourceKey key) {
  switch (key) {
    case AnalyticsSourceKey.exam:
      return AnalyticsStrings.sourceExam;
    case AnalyticsSourceKey.dailyTest:
      return AnalyticsStrings.sourceDailyTest;
    case AnalyticsSourceKey.practice:
      return AnalyticsStrings.sourcePractice;
    case AnalyticsSourceKey.qotd:
      return AnalyticsStrings.sourceQotd;
    case AnalyticsSourceKey.gkPm:
      return AnalyticsStrings.sourceGkPm;
    case AnalyticsSourceKey.reading:
      return AnalyticsStrings.sourceReading;
  }
}

/// Display name for a points-breakdown row, resolved from the row's label key
/// (the data layer emits i18n keys like `analytics.sources.exam`).
String pointsRowLabel(String labelKey) {
  switch (labelKey) {
    case 'analytics.sources.exam':
      return AnalyticsStrings.sourceExam;
    case 'analytics.sources.dailyTest':
      return AnalyticsStrings.sourceDailyTest;
    case 'analytics.sources.practice':
      return AnalyticsStrings.sourcePractice;
    case 'analytics.sources.qotd':
      return AnalyticsStrings.sourceQotd;
    case 'analytics.sources.gkPm':
      return AnalyticsStrings.sourceGkPm;
    case 'analytics.sources.reading':
      return AnalyticsStrings.sourceReading;
    case 'analytics.sources.time':
      return AnalyticsStrings.sourceTime;
    case 'analytics.sources.bonus':
      return AnalyticsStrings.sourceBonus;
    default:
      return labelKey;
  }
}

/// Where an insight card's CTA sends the user, in this app's routes.
///
/// Practice and reading point at the subject list rather than a deep practice
/// screen: those screens require course/subcourse/subject params, and pushing
/// them bare lands the user on a broken screen. The subject list is the real
/// entry point to both flows.
///
/// Exam has no bare route in this app — the exam entry point is the Exam tab
/// inside the tab shell, which has no programmatic route — so it falls back
/// to the exam history screen, the closest exam destination with a route.
String analyticsSourceRoute(AnalyticsSourceKey key) {
  switch (key) {
    case AnalyticsSourceKey.exam:
      return '/exam-history';
    case AnalyticsSourceKey.dailyTest:
      return '/daily-test';
    case AnalyticsSourceKey.practice:
      return '/subjects';
    case AnalyticsSourceKey.qotd:
      return '/question-of-the-day';
    case AnalyticsSourceKey.gkPm:
      return '/additional-features/gk';
    case AnalyticsSourceKey.reading:
      return '/subjects';
  }
}
