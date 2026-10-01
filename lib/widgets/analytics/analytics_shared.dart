import 'package:flutter/material.dart';

import '../../services/analytics/analytics_types.dart';

/// Shared English strings and tiny helpers for the analytics widgets.
///
/// The app has no l10n infra, so every user-facing string lives here in
/// English (mirroring the English values in the React app's i18n), exactly
/// once — the screen and the widgets all read from these.

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
      return 'Exam';
    case AnalyticsSourceKey.dailyTest:
      return 'Daily Test';
    case AnalyticsSourceKey.practice:
      return 'Practice';
    case AnalyticsSourceKey.qotd:
      return 'Question of the Day';
    case AnalyticsSourceKey.gkPm:
      return 'GK & Current Affairs';
    case AnalyticsSourceKey.reading:
      return 'Reading';
  }
}

/// Display name for a points-breakdown row, resolved from the row's label key
/// (the data layer emits i18n keys like `analytics.sources.exam`).
String pointsRowLabel(String labelKey) {
  switch (labelKey) {
    case 'analytics.sources.exam':
      return 'Exam';
    case 'analytics.sources.dailyTest':
      return 'Daily Test';
    case 'analytics.sources.practice':
      return 'Practice';
    case 'analytics.sources.qotd':
      return 'Question of the Day';
    case 'analytics.sources.gkPm':
      return 'GK & Current Affairs';
    case 'analytics.sources.reading':
      return 'Reading';
    case 'analytics.sources.time':
      return 'Study Time';
    case 'analytics.sources.bonus':
      return 'Bonus';
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
