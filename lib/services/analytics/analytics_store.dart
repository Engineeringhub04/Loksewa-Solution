// Read-only fetch layer for the analytics documents at
// `users/{uid}/app_analytics/{subcourseId}`.
//
// Dart port of fetchAnalyticsDocument / listAnalyticsSubcourses in
// LoksewasolutionApp/src/core/services/analyticsSnapshot.ts. Read-only by
// design: the write path (recordAnalyticsSnapshot) is intentionally not
// ported. These functions never throw — a missing document or a network
// failure simply yields null / an empty list, and the UI renders the empty
// state.
import '../cf_api.dart';
import 'analytics_series.dart';
import 'analytics_types.dart';

int _toInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.isFinite ? value.round() : fallback;
  if (value is String) {
    // D1 rows carry migrated values as text — '594' must read as 594.
    final parsed = num.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) return parsed.round();
  }
  return fallback;
}

double _toDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.isFinite ? value.toDouble() : fallback;
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return fallback;
}

String _toStr(dynamic value, [String fallback = '']) =>
    (value is String && value.isNotEmpty) ? value : fallback;

/// Light summary of one subcourse the user has analytics for — for the switcher.
class AnalyticsSubcourseRow {
  final String subcourseId;
  final String courseId;
  final double percent;
  final int points;

  const AnalyticsSubcourseRow({
    required this.subcourseId,
    required this.courseId,
    required this.percent,
    required this.points,
  });
}

/// Reads the stored analytics document. Returns null when none exists yet or
/// when the read fails. Never throws.
/// Phase-1: GET /analytics?subcourseId (Bearer — the [uid] parameter is
/// kept for signature parity).
Future<AnalyticsDocument?> fetchAnalyticsDocument(
    String uid, String subcourseId) async {
  if (uid.isEmpty || subcourseId.isEmpty) return null;
  try {
    final raw = await CfApi.getAnalytics(subcourseId);
    if (raw == null) return null;
    return parseAnalyticsDocument(raw, subcourseId);
  } catch (_) {
    return null;
  }
}

/// The bare document id of a D1 user-subcollection row: its `id` column is
/// `<uid>__<docId>`, where the old Firestore fallback read the bare doc id.
String _rowDocId(Map<String, dynamic> doc, String uid) {
  final raw = _toStr(doc['id']);
  final prefix = '${uid}__';
  return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
}

/// Light summary of every subcourse the user has analytics for — for the
/// switcher. Returns an empty list when the read fails. Never throws.
///
/// Phase-1: GET /analytics/list (Bearer — the [uid] parameter is kept for
/// signature parity, and strips the `<uid>__` prefix above). The endpoint
/// returns the caller's `users_app_analytics` rows flat, so percent/points
/// may arrive as text (coerced by the helpers at the top of this file).
/// Rows are sorted by subcourseId, matching the old Firestore list order
/// (document id = subcourseId, ascending).
Future<List<AnalyticsSubcourseRow>> listAnalyticsSubcourses(String uid) async {
  if (uid.isEmpty) return <AnalyticsSubcourseRow>[];
  try {
    final docs = await CfApi.getAnalyticsList();
    final rows = <AnalyticsSubcourseRow>[];
    for (final doc in docs) {
      final subcourseId = _toStr(doc['subcourseId'], _rowDocId(doc, uid));
      if (subcourseId.isEmpty) continue;
      rows.add(AnalyticsSubcourseRow(
        subcourseId: subcourseId,
        courseId: _toStr(doc['courseId']),
        percent: _toDouble(doc['percent']),
        points: _toInt(doc['points']),
      ));
    }
    rows.sort((a, b) => a.subcourseId.compareTo(b.subcourseId));
    return rows;
  } catch (_) {
    return <AnalyticsSubcourseRow>[];
  }
}
