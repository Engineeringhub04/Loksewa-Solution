import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/exam_service.dart';

ExamSet _set({
  DateTime? startTime,
  bool isLocked = false,
  bool isPublished = true,
  String sectionId = 'mcq-tests',
  int durationMinutes = 60,
  int passPercent = 50,
}) {
  return ExamSet(
    id: 's1',
    courseId: 'c1',
    subcourseId: 'sc1',
    courseIds: const ['c1'],
    subcourseIds: const ['sc1'],
    provinceId: 'all',
    sectionId: sectionId,
    isPublished: isPublished,
    title: 'Test Exam',
    price: 0,
    currency: 'NPR',
    startTime: startTime,
    totalQuestions: 10,
    durationMinutes: durationMinutes,
    passPercent: passPercent,
    // accessType 'pro' <=> isLocked (ExamSet.isPro is a getter on accessType).
    accessType: isLocked ? 'pro' : 'free',
    difficulty: 'medium',
    contentType: 'mcq',
    pdfUrl: '',
    questions: const [],
  );
}

void main() {
  group('resolveExamCardState', () {
    final now = DateTime(2026, 10, 2, 12, 0);

    ExamCardState state(
      ExamSet set, {
      bool hasAttempted = false,
      bool isPurchased = false,
      bool hasPendingPurchase = false,
    }) =>
        resolveExamCardState(
          set: set,
          now: now,
          hasAttempted: hasAttempted,
          isPurchased: isPurchased,
          hasPendingPurchase: hasPendingPurchase,
        );

    test('no start time and not attempted is ready', () {
      expect(state(_set(startTime: null)), ExamCardState.ready);
    });

    test('no start time and attempted is rejoin', () {
      expect(state(_set(startTime: null), hasAttempted: true),
          ExamCardState.rejoin);
    });

    test('pro set is locked when not purchased', () {
      expect(state(_set(startTime: null, isLocked: true)),
          ExamCardState.locked);
    });

    test('pro set is pending when a purchase is awaiting approval', () {
      expect(
          state(_set(startTime: null, isLocked: true),
              hasPendingPurchase: true),
          ExamCardState.pending);
    });

    test('pro set is open (ready) once purchased', () {
      expect(state(_set(startTime: null, isLocked: true), isPurchased: true),
          ExamCardState.ready);
    });

    test('far-future start is hidden (outside 10-min reveal lead)', () {
      expect(state(_set(startTime: now.add(const Duration(hours: 2)))),
          ExamCardState.hidden);
    });

    test('start within reveal lead shows countdown', () {
      expect(state(_set(startTime: now.add(const Duration(minutes: 5)))),
          ExamCardState.countdown);
    });

    test('started set without attempt is ready', () {
      // 5 min ago with a 0-min duration => live window already over.
      expect(
          state(_set(
              startTime: now.subtract(const Duration(minutes: 5)),
              durationMinutes: 0)),
          ExamCardState.ready);
    });

    test('started set with attempt is rejoin', () {
      expect(
          state(
              _set(
                  startTime: now.subtract(const Duration(minutes: 5)),
                  durationMinutes: 0),
              hasAttempted: true),
          ExamCardState.rejoin);
    });

    test('set inside its live window is live', () {
      expect(state(_set(startTime: now.subtract(const Duration(minutes: 5)))),
          ExamCardState.live);
    });

    test('live window ends at startTime + durationMinutes', () {
      final set = _set(startTime: now.subtract(const Duration(minutes: 61)));
      expect(state(set), ExamCardState.ready);
      expect(liveWindowEnd(set),
          now.subtract(const Duration(minutes: 1)));
    });

    test('null startTime has no live window', () {
      expect(liveWindowEnd(_set(startTime: null)), isNull);
    });
  });

  group('resultsUnlockAt', () {
    final now = DateTime(2026, 10, 2, 12, 0);

    test('null start time means always unlocked', () {
      final set = _set(startTime: null);
      expect(areResultsUnlocked(set, now), isTrue);
      expect(resultsUnlockAt(set, now), now);
    });

    test('results lock until start + duration', () {
      final set = _set(
          startTime: now.subtract(const Duration(minutes: 30)),
          durationMinutes: 60);
      expect(areResultsUnlocked(set, now), isFalse);
      expect(resultsUnlockAt(set, now),
          now.subtract(const Duration(minutes: 30)).add(const Duration(minutes: 60)));
    });

    test('results unlock after the window closes', () {
      final set = _set(
          startTime: now.subtract(const Duration(minutes: 90)),
          durationMinutes: 60);
      expect(areResultsUnlocked(set, now), isTrue);
    });
  });

  group('exam rules field matching (NOTE-6)', () {
    ExamRuleDoc doc(Map<String, dynamic> m) => ExamRuleDoc.fromMap(m);

    Map<String, dynamic> card(String title) => {
          'icon': 'shield',
          'title': title,
          'description': '$title description',
        };

    test('normalizeExamRuleScope: array wins, legacy folds in', () {
      expect(normalizeExamRuleScope(['a', ' b ', ''], 'legacy'), ['a', 'b']);
      expect(normalizeExamRuleScope(null, 'one'), ['one']);
      expect(normalizeExamRuleScope(null, ''), isEmpty);
      expect(normalizeExamRuleScope(null, null), isEmpty);
      expect(normalizeExamRuleScope(const [], 'ignored'), isEmpty);
    });

    test('All-scope doc matches any set context', () {
      final d = doc({
        'id': 'default',
        'courseIds': <String>[],
        'subcourseIds': <String>[],
        'provinceIds': <String>[],
        'sectionIds': <String>[],
        'contentTypes': <String>[],
        'rules': [card('Global')],
      });
      final winner = pickExamRuleDoc(
        [d],
        courseId: 'cX',
        subcourseId: 'scX',
        provinceId: 'pX',
        sectionId: 'sX',
        contentType: 'pdf',
      );
      expect(winner?.id, 'default');
      expect(winner?.rules.single.title, 'Global');
    });

    test('type-only docs split objective vs theory sets', () {
      final objective = doc({
        'id': 'objective',
        'contentTypes': ['mcq'],
        'rules': [card('Objective rules')],
      });
      final theory = doc({
        'id': 'theory',
        'contentTypes': ['pdf'],
        'rules': [card('Theory rules')],
      });
      final fallback = doc({
        'id': 'default',
        'rules': [card('Global')],
      });
      final docs = [theory, fallback, objective];
      expect(
        pickExamRuleDoc(docs, contentType: 'mcq')?.rules.single.title,
        'Objective rules',
      );
      expect(
        pickExamRuleDoc(docs, contentType: 'pdf')?.rules.single.title,
        'Theory rules',
      );
    });

    test('narrower scope beats a type-only doc', () {
      final typeOnly = doc({
        'id': 'objective',
        'contentTypes': ['mcq'],
        'rules': [card('Objective rules')],
      });
      final subcourseScoped = doc({
        'id': 'sc1-rules',
        'subcourseIds': ['sc1'],
        'rules': [card('Subcourse rules')],
      });
      final winner = pickExamRuleDoc(
        [typeOnly, subcourseScoped],
        subcourseId: 'sc1',
        contentType: 'mcq',
      );
      expect(winner?.id, 'sc1-rules');
    });

    test('legacy single-string scope docs still match', () {
      final legacy = doc({
        'id': 'legacy',
        'courseId': 'c1',
        'contentType': 'mcq',
        'rules': [card('Legacy rules')],
      });
      expect(legacy.courseIds, ['c1']);
      expect(legacy.contentTypes, ['mcq']);
      expect(legacy.subcourseIds, isEmpty);
      final winner = pickExamRuleDoc(
        [legacy],
        courseId: 'c1',
        contentType: 'mcq',
      );
      expect(winner?.id, 'legacy');
      // A different course must NOT match the legacy doc.
      expect(pickExamRuleDoc([legacy], courseId: 'c2', contentType: 'mcq'),
          isNull);
    });

    test('equal specificity resolves deterministically by doc id', () {
      final b = doc({
        'id': 'b-doc',
        'sectionIds': ['mcq-tests'],
        'rules': [card('B')],
      });
      final a = doc({
        'id': 'a-doc',
        'sectionIds': ['mcq-tests'],
        'rules': [card('A')],
      });
      expect(pickExamRuleDoc([b, a], sectionId: 'mcq-tests')?.id, 'a-doc');
      expect(pickExamRuleDoc([a, b], sectionId: 'mcq-tests')?.id, 'a-doc');
    });

    test('no matching doc returns null', () {
      final scoped = doc({
        'id': 'other',
        'provinceIds': ['bagmati'],
        'rules': [card('Bagmati only')],
      });
      expect(pickExamRuleDoc([scoped], provinceId: 'koshi'), isNull);
      expect(pickExamRuleDoc(const []), isNull);
    });

    test('legacy doc-as-card shape parses into a single rule', () {
      final d = doc({
        'id': 'default',
        'icon': 'info',
        'title': 'Solo rule',
        'description': 'Stored directly on the doc',
      });
      expect(d.rules, hasLength(1));
      expect(d.rules.single.title, 'Solo rule');
    });

    test('rule cards fall back to EN text outside Nepali mode', () {
      final r = ExamRule.fromMap({
        'icon': 'shield',
        'title': 'English title',
        'description': 'English description',
        'titleNe': 'नेपाली शीर्षक',
        'descriptionNe': 'नेपाली विवरण',
      });
      expect(r.displayTitle(true), 'नेपाली शीर्षक');
      expect(r.displayDescription(true), 'नेपाली विवरण');
      expect(r.displayTitle(false), 'English title');
      expect(r.displayDescription(false), 'English description');
      final enOnly = ExamRule.fromMap({
        'icon': 'shield',
        'title': 'English title',
        'description': 'English description',
      });
      // Nepali mode with no NE text falls back to EN.
      expect(enOnly.displayTitle(true), 'English title');
      expect(enOnly.displayDescription(true), 'English description');
    });
  });

  group('ExamSection.displayDescription (NOTE-5)', () {
    ExamSection section({String description = '', String descriptionNe = ''}) =>
        ExamSection.fromMap({
          'id': 'mcq-tests',
          'nameEn': 'MCQ Tests',
          'description': description,
          'descriptionNe': descriptionNe,
        });

    test('Nepali mode prefers descriptionNe, falls back to EN', () {
      final both = section(description: 'English', descriptionNe: 'नेपाली');
      expect(both.displayDescription(true), 'नेपाली');
      expect(both.displayDescription(false), 'English');
      final enOnly = section(description: 'English');
      expect(enOnly.displayDescription(true), 'English');
    });

    test('English mode falls back to descriptionNe when EN is empty', () {
      final neOnly = section(descriptionNe: 'नेपाली मात्र');
      expect(neOnly.displayDescription(false), 'नेपाली मात्र');
      expect(neOnly.displayDescription(true), 'नेपाली मात्र');
    });
  });

  group('normalizeExamSectionId', () {
    test('legacy aliases map to current ids', () {
      expect(normalizeExamSectionId('mcq'), 'mcq-tests');
      expect(normalizeExamSectionId('theory'), 'theory-desk');
    });

    test('current ids pass through', () {
      expect(normalizeExamSectionId('mcq-tests'), 'mcq-tests');
      expect(normalizeExamSectionId('theory-desk'), 'theory-desk');
      expect(normalizeExamSectionId(''), '');
    });
  });

  group('examSetVisible', () {
    ExamSet set({bool published = true}) => _set(
          startTime: null,
          isPublished: published,
        );

    test('allProvinces skips the province filter (All Board shows everything)',
        () {
      final s = set();
      // The fixture's provinceId is 'all' by default; give it a real one.
      final withProvince = ExamSet(
        id: s.id,
        courseId: s.courseId,
        subcourseId: s.subcourseId,
        courseIds: s.courseIds,
        subcourseIds: s.subcourseIds,
        provinceId: 'koshi',
        sectionId: s.sectionId,
        isPublished: s.isPublished,
        title: s.title,
        price: s.price,
        currency: s.currency,
        startTime: s.startTime,
        totalQuestions: s.totalQuestions,
        durationMinutes: s.durationMinutes,
        passPercent: s.passPercent,
        accessType: s.accessType,
        difficulty: s.difficulty,
        contentType: s.contentType,
        pdfUrl: s.pdfUrl,
        questions: s.questions,
      );
      expect(
          examSetVisible(withProvince, provinceId: allProvinces), isTrue);
      expect(examSetVisible(withProvince, provinceId: 'koshi'), isTrue);
      expect(examSetVisible(withProvince, provinceId: 'madhesh'), isFalse);
    });

    test('unpublished sets are never visible', () {
      expect(examSetVisible(set(published: false)), isFalse);
    });

    test('section narrowing still applies', () {
      final s = set();
      expect(examSetVisible(s, sectionId: 'mcq-tests'), isTrue);
      expect(examSetVisible(s, sectionId: 'theory-desk'), isFalse);
    });
  });

  group('ExamSet.fromMap', () {
    test('normalises legacy section aliases on read', () {
      final set = ExamSet.fromMap({
        'id': 's1',
        'title': 'Legacy',
        'sectionId': 'mcq',
        'subcourseId': 'sc1',
        'isPublished': true,
        'questions': [],
      });
      expect(set.sectionId, 'mcq-tests');
      expect(set.subcourseId, 'sc1');
      expect(set.subcourseIds, ['sc1']);
    });

    test('uses the id key injected by the REST mapper', () {
      final set = ExamSet.fromMap({'id': 'abc123'});
      expect(set.id, 'abc123');
    });
  });
}
