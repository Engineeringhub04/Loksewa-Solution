// Tests for the composed content-purchase display titles
// (content_title_resolver.dart).
//
// The headline case is the gateway chapter purchase the user hit: the
// worker stored the RAW doc ID as contentTitle and the record carries
// NO subjectId/unitId — the resolver must derive both from the chapter's
// own detail doc and compose "Subject - Unit - Chapter".
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/content_title_resolver.dart';

ContentPurchaseRecord _record(Map<String, dynamic> overrides) {
  return ContentPurchaseRecord.fromMap(<String, dynamic>{
    'id': 'r1',
    'uid': 'u1',
    'contentType': 'chapter',
    'contentId': '',
    'contentTitle': '',
    'contentTitleNe': '',
    'subjectId': '',
    'amount': 50,
    'currency': 'NPR',
    'method': 'qr',
    'status': 'active',
    'screenshotUrl': '',
    ...overrides,
  });
}

Future<Map<String, dynamic>?> Function(String) _fetcher(
        Map<String, Map<String, dynamic>> docs) =>
    (path) async => docs[path];

Future<List<Map<String, dynamic>>> Function(String, {int pageSize}) _lister(
        [List<Map<String, dynamic>> docs = const []]) =>
    (collection, {int pageSize = 200}) async => docs;

String _compose(ContentPurchaseRecord r, ContentDisplayNames n) =>
    composeContentTitle(
      contentType: r.contentType,
      subjectName: n.subjectName,
      unitName: n.unitName,
      ownName: n.ownName,
      storedTitle: r.contentTitle,
      contentId: r.contentId,
    );

void main() {
  tearDown(() => AppLanguage.current.value = AppLanguage.english);

  group('composeContentTitle', () {
    test('subject purchase shows the subject name alone', () {
      expect(
        composeContentTitle(
          contentType: 'subject',
          ownName: 'Physics',
          storedTitle: 'Physics',
          contentId: 'c__s__physics',
        ),
        'Physics',
      );
    });

    test('unit purchase is "Subject - Unit" (unitName param ignored)', () {
      expect(
        composeContentTitle(
          contentType: 'unit',
          subjectName: 'Mathematics',
          unitName: 'Should Not Appear',
          ownName: 'Algebra',
          storedTitle: '',
          contentId: 'u1',
        ),
        'Mathematics - Algebra',
      );
    });

    test('chapter without unit is "Subject - Chapter"', () {
      expect(
        composeContentTitle(
          contentType: 'chapter',
          subjectName: 'Math',
          ownName: 'Introduction',
          storedTitle: '',
          contentId: 'ch1',
        ),
        'Math - Introduction',
      );
    });

    test('chapter with unit is "Subject - Unit - Chapter"', () {
      expect(
        composeContentTitle(
          contentType: 'chapter',
          subjectName: 'Technical Subject',
          unitName: 'Materials',
          ownName: 'Construction Materials 2 3',
          storedTitle: '',
          contentId: 'ch1',
        ),
        'Technical Subject - Materials - Construction Materials 2 3',
      );
    });

    test('fallback chain: readable stored title wins when nothing resolves',
        () {
      expect(
        composeContentTitle(
          contentType: 'chapter',
          storedTitle: 'My Chapter Notes',
          contentId: 'ch1',
        ),
        'My Chapter Notes',
      );
    });

    test('fallback chain: raw doc ID stored title is cleaned, never raw', () {
      expect(
        composeContentTitle(
          contentType: 'chapter',
          storedTitle:
              'civil-engineering__civil-sub-engineer__technical-subject__construction-materials-2-3',
          contentId:
              'civil-engineering__civil-sub-engineer__technical-subject__construction-materials-2-3',
        ),
        'construction materials 2 3',
      );
    });
  });

  group('resolveContentDisplayNames', () {
    const chapterId =
        'civil-engineering__civil-sub-engineer__technical-subject__construction-materials-2-3';
    const subjectId =
        'civil-engineering__civil-sub-engineer__technical-subject';

    test(
        'gateway chapter-with-unit: subject/unit derived from the chapter doc',
        () async {
      // Worker's record shape: contentTitle is the raw ID, no
      // subjectId, no unitId.
      final record = _record({
        'id': 'gw-unit-chapter',
        'contentId': chapterId,
        'contentTitle': chapterId,
        'method': 'esewa',
      });
      final docs = <String, Map<String, dynamic>>{
        'app_subjects_unit-chapters_details/$chapterId': {
          'id': chapterId,
          'name': 'Construction Materials 2 3',
          'nameNe': 'निर्माण सामग्री २ ३',
          'unitId': '${subjectId}__materials',
          'unit': 'Materials',
          'unitNameNe': 'सामग्री',
          'subjectId': subjectId,
        },
        'app_subjects_details/$subjectId': {
          'id': subjectId,
          'name': 'Technical Subject',
          'nameNe': 'प्राविधिक विषय',
        },
      };
      final names = await resolveContentDisplayNames(record,
          getDoc: _fetcher(docs), listDocs: _lister());
      expect(names.subjectName, 'Technical Subject');
      expect(names.unitName, 'Materials');
      expect(names.ownName, 'Construction Materials 2 3');
      expect(_compose(record, names),
          'Technical Subject - Materials - Construction Materials 2 3');
    });

    test('same record in Nepali composes nameNe names', () async {
      AppLanguage.current.value = AppLanguage.nepali;
      final record = _record({
        'id': 'gw-unit-chapter-ne',
        'contentId': chapterId,
        'contentTitle': chapterId,
        'method': 'esewa',
      });
      final docs = <String, Map<String, dynamic>>{
        'app_subjects_unit-chapters_details/$chapterId': {
          'id': chapterId,
          'name': 'Construction Materials 2 3',
          'nameNe': 'निर्माण सामग्री २ ३',
          'unitId': '${subjectId}__materials',
          'unit': 'Materials',
          'unitNameNe': 'सामग्री',
          'subjectId': subjectId,
        },
        'app_subjects_details/$subjectId': {
          'id': subjectId,
          'name': 'Technical Subject',
          'nameNe': 'प्राविधिक विषय',
        },
      };
      final names = await resolveContentDisplayNames(record,
          getDoc: _fetcher(docs), listDocs: _lister());
      expect(_compose(record, names),
          'प्राविधिक विषय - सामग्री - निर्माण सामग्री २ ३');
    });

    test('chapter without unit falls back to the unit-less collection',
        () async {
      final record = _record({
        'id': 'plain-chapter',
        'contentId': 'c__s__intro',
      });
      final docs = <String, Map<String, dynamic>>{
        'app_subjects_chapter_details/c__s__intro': {
          'id': 'c__s__intro',
          'name': 'Introduction',
          'subjectId': 'c__s',
        },
        'app_subjects_details/c__s': {
          'id': 'c__s',
          'name': 'Mathematics',
        },
      };
      final names = await resolveContentDisplayNames(record,
          getDoc: _fetcher(docs), listDocs: _lister());
      expect(names.unitName, isNull);
      expect(_compose(record, names), 'Mathematics - Introduction');
    });

    test('unit name falls back to the unit doc when the chapter lacks it',
        () async {
      final record = _record({
        'id': 'chapter-unit-doc',
        'contentId': 'ch9',
      });
      final docs = <String, Map<String, dynamic>>{
        'app_subjects_unit-chapters_details/ch9': {
          'id': 'ch9',
          'name': 'Chapter Nine',
          'unitId': 'unit9',
          'subjectId': 'subj9',
        },
        'app_subjects_units_details/unit9': {
          'id': 'unit9',
          'name': 'Unit Nine',
          'subjectId': 'subj9',
        },
        'app_subjects_details/subj9': {
          'id': 'subj9',
          'name': 'Subject Nine',
        },
      };
      final names = await resolveContentDisplayNames(record,
          getDoc: _fetcher(docs), listDocs: _lister());
      expect(_compose(record, names), 'Subject Nine - Unit Nine - Chapter Nine');
    });

    test('unit purchase derives the subject from the unit doc', () async {
      final record = _record({
        'id': 'unit-purchase',
        'contentType': 'unit',
        'contentId': 'u-algebra',
      });
      final docs = <String, Map<String, dynamic>>{
        'app_subjects_units_details/u-algebra': {
          'id': 'u-algebra',
          'name': 'Algebra',
          'subjectId': 'math',
        },
        'app_subjects_details/math': {
          'id': 'math',
          'name': 'Mathematics',
        },
      };
      final names = await resolveContentDisplayNames(record,
          getDoc: _fetcher(docs), listDocs: _lister());
      expect(_compose(record, names), 'Mathematics - Algebra');
    });

    test('subject purchase resolves its own name', () async {
      final record = _record({
        'id': 'subject-purchase',
        'contentType': 'subject',
        'contentId': 'c__s__physics',
        'contentTitle': 'c__s__physics',
      });
      final docs = <String, Map<String, dynamic>>{
        'app_subjects_details/c__s__physics': {
          'id': 'c__s__physics',
          'name': 'Physics',
        },
      };
      final names = await resolveContentDisplayNames(record,
          getDoc: _fetcher(docs), listDocs: _lister());
      expect(_compose(record, names), 'Physics');
    });

    test('subject name resolves by slug scan when subjectId is a slug',
        () async {
      final record = _record({
        'id': 'slug-subject',
        'contentId': 'ch-slug',
      });
      final docs = <String, Map<String, dynamic>>{
        'app_subjects_chapter_details/ch-slug': {
          'id': 'ch-slug',
          'name': 'Slug Chapter',
          'subjectId': 'physics',
        },
      };
      final names = await resolveContentDisplayNames(
        record,
        getDoc: _fetcher(docs),
        listDocs: _lister(const [
          {'id': 'course__sub__physics', 'name': 'Physics'},
        ]),
      );
      expect(names.subjectName, 'Physics');
    });

    test('total miss never throws and falls back to the stored title',
        () async {
      final record = _record({
        'id': 'total-miss',
        'contentId': 'gone',
        'contentTitle': 'Readable Stored Title',
      });
      final names = await resolveContentDisplayNames(record,
          getDoc: _fetcher(const {}), listDocs: _lister());
      expect(names.ownName, isNull);
      expect(_compose(record, names), 'Readable Stored Title');
    });

    test('fetch errors are swallowed (fail-soft)', () async {
      final record = _record({
        'id': 'fetch-error',
        'contentId': 'boom',
        'contentTitle': 'Boom Chapter',
      });
      final names = await resolveContentDisplayNames(
        record,
        getDoc: (path) async => throw Exception('network'),
        listDocs: (collection, {int pageSize = 200}) async =>
            throw Exception('network'),
      );
      expect(_compose(record, names), 'Boom Chapter');
    });
  });
}
