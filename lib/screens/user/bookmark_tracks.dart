import 'package:flutter/material.dart';

/// User-facing bookmark tracks shared by the bookmarks list and detail
/// screens.
///
/// Raw `context` values saved on bookmark docs are grouped into tracks:
///
/// - subject practice / read / theory (`practice`, `read`, `chapter`)
///   → "Subject Question" (one track for all subject material)
/// - GK/PM topic screens save the *mode* as context (`read`/`practice`),
///   so they are detected via the feature-id prefix in `sourceLabel`
///   (e.g. "gk · Read Mode") → "GK" / "PM"
/// - `exam` → "Exam", `article` → "Article"
/// - anything else keeps its own track
///
/// Storage is untouched — this is grouping/filter/display only.
///
/// Language rule: [label] is pure English, [labelNe] is pure Devanagari
/// Nepali. Callers render them through `AppLanguage.tr(label, labelNe)`.
class BookmarkTrack {
  final String key;
  final String label;
  final String labelNe;
  final IconData icon;
  final Color color;
  const BookmarkTrack(
      this.key, this.label, this.labelNe, this.icon, this.color);
}

const bookmarkTracks = <String, BookmarkTrack>{
  'subject': BookmarkTrack('subject', 'Subject Question', 'विषय प्रश्न',
      Icons.quiz_outlined, Color(0xFFEA580C)),
  'gk': BookmarkTrack(
      'gk', 'GK', 'सामान्य ज्ञान', Icons.public_outlined, Color(0xFF0284C7)),
  'pm': BookmarkTrack('pm', 'PM', 'सार्वजनिक व्यवस्थापन',
      Icons.account_balance_outlined, Color(0xFF0D9488)),
  'exam': BookmarkTrack(
      'exam', 'Exam', 'परीक्षा', Icons.school_outlined, Color(0xFF2563EB)),
  'article': BookmarkTrack('article', 'Article', 'लेख',
      Icons.newspaper_outlined, Color(0xFF059669)),
  'daily-test': BookmarkTrack('daily-test', 'Daily Test', 'दैनिक परीक्षा',
      Icons.calendar_today_outlined, Color(0xFF7C3AED)),
  'qotd': BookmarkTrack('qotd', 'QOTD', 'आजको प्रश्न',
      Icons.wb_sunny_outlined, Color(0xFFD97706)),
  'quiz': BookmarkTrack(
      'quiz', 'Quiz', 'क्विज', Icons.help_outline, Color(0xFFDB2777)),
  'discussion': BookmarkTrack('discussion', 'Discussion', 'छलफल',
      Icons.forum_outlined, Color(0xFF4F46E5)),
  'note': BookmarkTrack('note', 'Note', 'नोट',
      Icons.description_outlined, Color(0xFF475569)),
  'other': BookmarkTrack('other', 'Other', 'अन्य',
      Icons.bookmark_outline, Color(0xFF64748B)),
};

/// Track key for one bookmark doc. Pure — safe to unit test.
String bookmarkTrackKey(Map<String, dynamic> b) {
  final ctx = (b['context'] ?? 'other').toString();
  final src = (b['sourceLabel'] ?? '').toString();
  // GK/PM topic screens reuse the read/practice contexts; the feature id
  // rides in the sourceLabel prefix ("gk · Read Mode").
  final prefix = src.split('·').first.trim().toLowerCase();
  if (prefix == 'gk') return 'gk';
  if (prefix == 'pm') return 'pm';
  switch (ctx) {
    case 'practice':
    case 'read':
    case 'chapter':
      return 'subject';
    default:
      return bookmarkTracks.containsKey(ctx) ? ctx : 'other';
  }
}

/// Track for one bookmark doc (never null).
BookmarkTrack bookmarkTrackOf(Map<String, dynamic> b) =>
    bookmarkTracks[bookmarkTrackKey(b)] ?? bookmarkTracks['other']!;

/// Track chips for the filter row: one entry per track present in [items],
/// sorted by count desc. Pure — safe to unit test.
List<MapEntry<String, int>> buildTrackChips(
    List<Map<String, dynamic>> items) {
  final counts = <String, int>{};
  for (final b in items) {
    final t = bookmarkTrackKey(b);
    counts[t] = (counts[t] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries;
}
