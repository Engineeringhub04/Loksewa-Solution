// Pure unit tests for lib/screens/shop/report_visuals.dart — the shared
// status/source/target lookups shared by the report-history list and the
// report-detail page. Mirrors reportVisuals.ts behavior, including the
// targetKey quirk where `app` / `content` fall through to the Comment
// label, and the pending default for unknown statuses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/shop/report_visuals.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

void main() {
  group('reportStatusVisual', () {
    test('pending → warning tone, schedule icon, bilingual label', () {
      final v = reportStatusVisual('pending');
      expect(v.tone, ReportTone.warning);
      expect(v.icon, Icons.schedule_outlined);
      expect(v.labelEn, 'Pending review');
      expect(v.labelNe, 'समीक्षा बाँकी');
    });

    test('reviewed → info tone, eye icon', () {
      final v = reportStatusVisual('reviewed');
      expect(v.tone, ReportTone.info);
      expect(v.icon, Icons.visibility_outlined);
      expect(v.labelEn, 'Reviewed');
      expect(v.labelNe, 'समीक्षा भयो');
    });

    test('resolved → success tone, check icon', () {
      final v = reportStatusVisual('resolved');
      expect(v.tone, ReportTone.success);
      expect(v.icon, Icons.check_circle_outlined);
      expect(v.labelEn, 'Resolved');
      expect(v.labelNe, 'समाधान भयो');
    });

    test('dismissed → danger tone, cancel icon', () {
      final v = reportStatusVisual('dismissed');
      expect(v.tone, ReportTone.danger);
      expect(v.icon, Icons.cancel_outlined);
      expect(v.labelEn, 'Dismissed');
      expect(v.labelNe, 'खारेज गरियो');
    });

    test('unknown status falls back to pending', () {
      for (final s in ['', 'in-progress', 'PENDING', 'archived']) {
        final v = reportStatusVisual(s);
        expect(v.labelEn, 'Pending review', reason: 'status=$s');
        expect(v.tone, ReportTone.warning);
      }
    });
  });

  group('reportSourceVisual', () {
    test('each source has its own tone + icon + bilingual label', () {
      expect(reportSourceVisual('question').tone, ReportTone.primary);
      expect(reportSourceVisual('question').labelEn, 'Question');
      expect(reportSourceVisual('question').labelNe, 'प्रश्न');
      expect(reportSourceVisual('discussion').tone, ReportTone.accent);
      expect(reportSourceVisual('discussion').labelNe, 'छलफल');
      expect(reportSourceVisual('comment').tone, ReportTone.info);
      expect(reportSourceVisual('comment').labelNe, 'टिप्पणी');
      expect(reportSourceVisual('app').tone, ReportTone.danger);
      expect(reportSourceVisual('app').labelNe, 'एप');
      expect(reportSourceVisual('read').tone, ReportTone.success);
      expect(reportSourceVisual('read').labelNe, 'पठन');
      expect(reportSourceVisual('article').tone, ReportTone.warning);
      expect(reportSourceVisual('article').labelNe, 'लेख');
    });

    test('unknown source falls back to Other', () {
      final v = reportSourceVisual('something-new');
      expect(v.labelEn, 'Other');
      expect(v.labelNe, 'अन्य');
      expect(v.tone, ReportTone.neutral);
    });
  });

  group('reportTargetIcon', () {
    test('per-type icons', () {
      expect(reportTargetIcon('question'), Icons.help_outline);
      expect(reportTargetIcon('post'), Icons.forum_outlined);
      expect(reportTargetIcon('reply'), Icons.reply_outlined);
      expect(reportTargetIcon('app'), Icons.smartphone_outlined);
      expect(reportTargetIcon('content'), Icons.description_outlined);
    });

    test('unknown type falls back to the comment icon', () {
      expect(reportTargetIcon('mystery'), Icons.chat_bubble_outline);
    });
  });

  group('reportTargetVisual', () {
    test('question / post / reply have their own labels', () {
      expect(reportTargetVisual('question').labelEn, 'Question');
      expect(reportTargetVisual('question').labelNe, 'प्रश्न');
      expect(reportTargetVisual('post').labelEn, 'Post');
      expect(reportTargetVisual('post').labelNe, 'पोस्ट');
      expect(reportTargetVisual('reply').labelEn, 'Reply');
      expect(reportTargetVisual('reply').labelNe, 'रिप्लाइ');
    });

    test('app / content fall through to the Comment label (React quirk)', () {
      // Mirrors targetKey: `app` and `content` have icons but no label of
      // their own — they land on the comment entry.
      final app = reportTargetVisual('app');
      expect(app.labelEn, 'Comment');
      expect(app.labelNe, 'कमेन्ट');
      expect(app.icon, Icons.smartphone_outlined);

      final content = reportTargetVisual('content');
      expect(content.labelEn, 'Comment');
      expect(content.labelNe, 'कमेन्ट');
      expect(content.icon, Icons.description_outlined);
    });

    test('unknown target type defaults to Comment', () {
      expect(reportTargetVisual('mystery').labelEn, 'Comment');
      expect(reportTargetVisual('mystery').icon, Icons.chat_bubble_outline);
    });
  });

  group('reportToneColor', () {
    test('maps every tone onto the palette', () {
      const pal = ExpoPalette.light;
      expect(reportToneColor(pal, ReportTone.primary), pal.primary);
      expect(reportToneColor(pal, ReportTone.accent), pal.accent);
      expect(reportToneColor(pal, ReportTone.info), pal.info);
      expect(reportToneColor(pal, ReportTone.success), pal.success);
      expect(reportToneColor(pal, ReportTone.warning), pal.warning);
      expect(reportToneColor(pal, ReportTone.danger), pal.danger);
      expect(reportToneColor(pal, ReportTone.neutral), pal.textSecondary);
    });
  });
}
