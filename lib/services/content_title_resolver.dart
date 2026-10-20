// Composed display titles for content (subject / unit / chapter)
// purchases.
//
// WHY: the purchase record's stored contentTitle can be a RAW Firestore
// document ID. Gateway purchases are the gap — the worker's
// loadContentItem reads the detail doc's `title` field, but the detail
// collections store the display name in `name`/`nameNe`, so the title
// falls back to the raw ID (`civil-engineering__...__constr…`). Gateway
// records also carry NO subjectId/unitId, so the detail screens could
// never prepend the subject (and chapter-with-unit lookups tried the
// wrong collection). These helpers resolve the real names from the
// details collections — deriving subjectId/unitId from the purchased
// item's own detail doc when the record lacks them — and compose the
// user-facing title:
//
//   subject            → "Subject Name"
//   unit               → "Subject Name - Unit Name"
//   chapter (no unit)  → "Subject Name - Chapter Name"
//   chapter (in unit)  → "Subject Name - Unit Name - Chapter Name"
//
// Fallback chain: composed title → stored contentTitle → the content ID
// (cleaned to a readable tail — the raw `__` ID is never shown). Every
// lookup is fail-soft: a missing doc or a network error just drops that
// part, it never throws.
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/exam_service.dart';

typedef ContentDocFetcher = Future<Map<String, dynamic>?> Function(
    String path);
typedef ContentDocsLister = Future<List<Map<String, dynamic>>> Function(
    String collection,
    {int pageSize});

/// The three names a composed title is built from (any may be missing).
class ContentDisplayNames {
  final String? subjectName;
  final String? unitName;
  final String? ownName;

  const ContentDisplayNames({this.subjectName, this.unitName, this.ownName});
}

String? _nonEmpty(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Language-aware display name inside a detail doc: `name`/`nameNe` first
/// (the detail collections' convention), `title` as a legacy fallback.
String? contentDocDisplayName(Map<String, dynamic>? doc) {
  if (doc == null) return null;
  String? pick;
  if (AppLanguage.isNepali) {
    pick = _nonEmpty(doc['nameNe']) ?? _nonEmpty(doc['name']);
  } else {
    pick = _nonEmpty(doc['name']) ?? _nonEmpty(doc['nameNe']);
  }
  pick ??= _nonEmpty(doc['title']);
  return pick;
}

/// The unit's display name as carried by a chapter detail doc
/// (`unit` / `unitNameNe` fields).
String? _unitNameFromChapterDoc(Map<String, dynamic> doc) {
  if (AppLanguage.isNepali) {
    return _nonEmpty(doc['unitNameNe']) ?? _nonEmpty(doc['unit']);
  }
  return _nonEmpty(doc['unit']) ?? _nonEmpty(doc['unitNameNe']);
}

/// A raw Firestore doc ID (segments joined by `__`).
bool contentLooksLikeDocId(String s) => s.contains('__');

/// Fail-soft: the doc ID's last `__`-segment with dashes/underscores as
/// spaces — readable text instead of the raw ID.
String cleanDocIdName(String s) {
  if (!contentLooksLikeDocId(s)) return s;
  final last = s.split('__').lastWhere((p) => p.isNotEmpty, orElse: () => '');
  return last.replaceAll('-', ' ').replaceAll('_', ' ').trim();
}

/// Compose the user-facing title from resolved names plus the record's
/// stored fallbacks. Parts that resolved join with " - "; a unit name is
/// used only for chapter titles ("Subject - Unit - Chapter"), never for
/// a unit purchase itself (there it IS the item's own name).
/// Fallback chain: composed → stored contentTitle → content ID (cleaned).
String composeContentTitle({
  required String contentType,
  String? subjectName,
  String? unitName,
  String? ownName,
  String? storedTitle,
  String? contentId,
}) {
  final stored = _nonEmpty(storedTitle);
  // The item's own name: the resolved doc name wins; the stored title
  // counts only when it is not itself a raw doc ID.
  final own = _nonEmpty(ownName) ??
      (stored != null && !contentLooksLikeDocId(stored) ? stored : null);
  if (contentType == 'subject') {
    return own ?? _fallbackName(stored, contentId);
  }
  final parts = <String>[];
  final sub = _nonEmpty(subjectName);
  if (sub != null) parts.add(sub);
  if (contentType == 'chapter') {
    final unit = _nonEmpty(unitName);
    if (unit != null) parts.add(unit);
  }
  if (own != null) parts.add(own);
  if (parts.isEmpty) return _fallbackName(stored, contentId);
  return parts.join(' - ');
}

/// Last resort: the stored title if there is one, else the content ID —
/// a raw doc ID is cleaned to its readable tail rather than shown as-is.
String _fallbackName(String? stored, String? contentId) {
  if (stored != null) {
    return contentLooksLikeDocId(stored) ? cleanDocIdName(stored) : stored;
  }
  return cleanDocIdName(contentId ?? '');
}

// In-flight/resolved names cached per record id + language so the
// purchase list (one lookup per card) and the detail page don't re-read
// the same detail docs on every rebuild.
final Map<String, Future<ContentDisplayNames>> _namesCache = {};

/// Resolve subject / unit / own names for a purchase record from the
/// details collections. [getDoc]/[listDocs] are injectable for tests.
Future<ContentDisplayNames> resolveContentDisplayNames(
  ContentPurchaseRecord record, {
  ContentDocFetcher? getDoc,
  ContentDocsLister? listDocs,
}) {
  final fetch = getDoc ?? ExamRest.getDoc;
  final list = listDocs ?? ExamRest.listDocs;
  final key = '${record.id}__${AppLanguage.current.value}';
  return _namesCache.putIfAbsent(key, () => _resolve(record, fetch, list));
}

/// Subject name via the slug tail of [id]: the subject collection is
/// small, so scan it and match the doc ID suffix (mirrors the checkout's
/// subject fallback — survives subjectId being a slug instead of a full
/// doc ID).
Future<String?> _subjectNameBySlug(ContentDocsLister list, String id) async {
  final slug = id.split('__').lastWhere((p) => p.isNotEmpty, orElse: () => '');
  if (slug.isEmpty) return null;
  try {
    final docs = await list('app_subjects_details', pageSize: 300);
    for (final d in docs) {
      if ('${d['id'] ?? ''}'.endsWith('__$slug')) {
        final name = contentDocDisplayName(d);
        if (name != null) return name;
      }
    }
  } catch (_) {
    // Fail-soft — the slug fallback is best-effort only.
  }
  return null;
}

Future<ContentDisplayNames> _resolve(
  ContentPurchaseRecord record,
  ContentDocFetcher fetch,
  ContentDocsLister list,
) async {
  String? subjectId = _nonEmpty(record.subjectId);
  String? unitId = _nonEmpty(record.unitId);
  String? ownName;
  String? unitName;

  Future<Map<String, dynamic>?> safeGet(String path) async {
    try {
      return await fetch(path);
    } catch (_) {
      return null;
    }
  }

  Future<String?> subjectNameFor(String id) async {
    final doc = await safeGet('app_subjects_details/$id');
    return contentDocDisplayName(doc) ?? _subjectNameBySlug(list, id);
  }

  try {
    switch (record.contentType) {
      case 'subject':
        ownName = await subjectNameFor(record.contentId);
        break;
      case 'unit':
        final doc =
            await safeGet('app_subjects_units_details/${record.contentId}');
        ownName = contentDocDisplayName(doc);
        subjectId ??= _nonEmpty(doc?['subjectId']);
        break;
      case 'chapter':
      default:
        // Which chapter collection holds the doc? The record's unitId
        // decides when present; gateway records store none, so try the
        // unit-chapters collection first, then the unit-less one.
        Map<String, dynamic>? doc;
        final collections = <String>[
          'app_subjects_unit-chapters_details',
          if (unitId == null) 'app_subjects_chapter_details',
        ];
        for (final col in collections) {
          doc = await safeGet('$col/${record.contentId}');
          if (doc != null) break;
        }
        ownName = contentDocDisplayName(doc);
        if (doc != null) {
          // The chapter doc itself carries the missing links: its
          // subjectId/unitId fields and the unit's display name.
          unitId ??= _nonEmpty(doc['unitId']);
          subjectId ??= _nonEmpty(doc['subjectId']);
          unitName = _unitNameFromChapterDoc(doc);
          if (unitName == null && unitId != null) {
            final unitDoc =
                await safeGet('app_subjects_units_details/$unitId');
            unitName = contentDocDisplayName(unitDoc);
          }
        }
        break;
    }

    String? subjectName;
    if (record.contentType != 'subject' && subjectId != null) {
      subjectName = await subjectNameFor(subjectId);
    }
    return ContentDisplayNames(
      subjectName: subjectName,
      unitName: unitName,
      ownName: ownName,
    );
  } catch (_) {
    return const ContentDisplayNames();
  }
}
