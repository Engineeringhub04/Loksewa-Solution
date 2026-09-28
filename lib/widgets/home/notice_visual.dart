import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Shared look-up for the notice surfaces (Home's "Recent Notices", the full
/// Notices list, and notice detail) — mirrors
/// src/components/notice/noticeVisuals.ts + the tone system in
/// src/components/premium/tone.ts.
///
/// Each kind maps to an icon + theme tone + badge word. Tone colours come
/// from the active [ExpoPalette] (which mirrors ThemeColors in
/// src/core/theme/tokens.ts) — never hardcoded hexes, so dark mode adapts
/// exactly like the Expo app.
class NoticeVisual {
  final IconData icon;
  final Color color;
  final String label;

  const NoticeVisual(
      {required this.icon, required this.color, required this.label});
}

NoticeVisual noticeVisual(String? kind, ExpoPalette palette) {
  switch (kind) {
    case 'feature':
      return NoticeVisual(
          icon: Icons.auto_awesome, color: palette.accent, label: 'New');
    case 'update':
      return NoticeVisual(
          icon: Icons.cloud_download_outlined,
          color: palette.info,
          label: 'Update');
    case 'maintenance':
      return NoticeVisual(
          icon: Icons.build_outlined,
          color: palette.warning,
          label: 'Maintenance');
    case 'exam':
      return NoticeVisual(
          icon: Icons.calendar_today_outlined,
          color: palette.danger,
          label: 'Exam');
    case 'welcome':
      return NoticeVisual(
          icon: Icons.waving_hand_outlined,
          color: palette.success,
          label: 'Welcome');
    default:
      return NoticeVisual(
          icon: Icons.campaign_outlined,
          color: palette.primary,
          label: 'Notice');
  }
}

/// Theme tone base colour by tone name — mirrors baseColor() in tone.ts
/// ('danger' resolves to the theme error colour).
Color noticeToneBase(String tone, ExpoPalette palette) {
  switch (tone) {
    case 'info':
      return palette.info;
    case 'success':
      return palette.success;
    case 'warning':
      return palette.warning;
    case 'danger':
      return palette.danger;
    case 'accent':
      return palette.accent;
    case 'primary':
      return palette.primary;
    default:
      return palette.textSecondary;
  }
}
