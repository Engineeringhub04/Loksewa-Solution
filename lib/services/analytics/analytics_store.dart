// Read-only fetch layer for the analytics documents at
// `users/{uid}/app_analytics/{subcourseId}`.
//
// Dart port of fetchAnalyticsDocument / listAnalyticsSubcourses in
// LoksewasolutionApp/src/core/services/analyticsSnapshot.ts. Read-only by
// design: the write path (recordAnalyticsSnapshot) is intentionally not
// ported. These functions never throw — a missing document or a network
// failure simply yields null / an empty list, and the UI renders the empty
// state.
import '../auth_service.dart';
import '../firestore_rest.dart';
import 'analytics_series.dart';
import 'analytics_types.dart';

int _toInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.isFinite ? value.round() : fallback;
  return fallback;
}

double _toDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.isFinite ? value.toDouble() : fallback;
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
Future<AnalyticsDocument?> fetchAnalyticsDocument(
    String uid, String subcourseId) async {
  if (uid.isEmpty || subcourseId.isEmpty) return null;
  try {
    final idToken = await AuthService.getValidIdToken();
    final raw = await FirestoreRest.getDocument(
      'users/$uid/app_analytics/$subcourseId',
      idToken: idToken,
    );
    if (raw == null) return null;
    return parseAnalyticsDocument(raw, subcourseId);
  } catch (_) {
    return null;
  }
}

/// Light summary of every subcourse the user has analytics for — for the
/// switcher. Returns an empty list when the read fails. Never throws.
Future<List<AnalyticsSubcourseRow>> listAnalyticsSubcourses(String uid) async {
  if (uid.isEmpty) return <AnalyticsSubcourseRow>[];
  try {
    final idToken = await AuthService.getValidIdToken();
    final docs = await FirestoreRest.listDocuments(
      'users/$uid/app_analytics',
      idToken: idToken,
    );
    final rows = <AnalyticsSubcourseRow>[];
    for (final doc in docs) {
      final subcourseId = _toStr(doc['subcourseId'], _toStr(doc['id']));
      if (subcourseId.isEmpty) continue;
      rows.add(AnalyticsSubcourseRow(
        subcourseId: subcourseId,
        courseId: _toStr(doc['courseId']),
        percent: _toDouble(doc['percent']),
        points: _toInt(doc['points']),
      ));
    }
    return rows;
  } catch (_) {
    return <AnalyticsSubcourseRow>[];
  }
}
