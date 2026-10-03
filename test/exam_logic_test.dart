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

  group('examRuleCandidateIds', () {
    test('full scope first, then narrower fallbacks', () {
      expect(
        examRuleCandidateIds(
            subcourseId: 'sc1', provinceId: 'p1', sectionId: 'mcq-tests'),
        [
          'sc1__p1__mcq-tests',
          'sc1__mcq-tests',
          'default__mcq-tests',
          'default',
        ],
      );
    });

    test('null province skips province-scoped candidate', () {
      expect(
        examRuleCandidateIds(subcourseId: 'sc1', sectionId: 'mcq-tests'),
        ['sc1__mcq-tests', 'default__mcq-tests', 'default'],
      );
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
