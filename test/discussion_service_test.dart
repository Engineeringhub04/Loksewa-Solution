import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/discussion_service.dart';

void main() {
  group('normalizeDiscussionUrl', () {
    test('bare www. gets an https:// scheme', () {
      expect(normalizeDiscussionUrl('www.example.com/x'),
          'https://www.example.com/x');
    });
    test('http/https URLs are left alone', () {
      expect(normalizeDiscussionUrl('http://x.com'), 'http://x.com');
      expect(normalizeDiscussionUrl('https://x.com'), 'https://x.com');
    });
    test('trims whitespace', () {
      expect(normalizeDiscussionUrl('  www.a.com  '), 'https://www.a.com');
    });
  });

  group('splitDiscussionLinks', () {
    test('splits https and www links out of body text', () {
      final segs = splitDiscussionLinks(
          'see https://a.com/x and www.b.com for more');
      final links = segs.where((s) => s.isLink).map((s) => s.text).toList();
      expect(links, ['https://a.com/x', 'www.b.com']);
      expect(segs.length, 5);
    });
    test('plain text yields a single non-link segment', () {
      final segs = splitDiscussionLinks('just words');
      expect(segs, [(text: 'just words', isLink: false)]);
    });
    test('matches case-insensitively', () {
      final segs = splitDiscussionLinks('go to HTTPS://A.COM');
      expect(segs.any((s) => s.isLink), isTrue);
    });
  });

  group('filterDiscussions', () {
    final posts = [
      const DiscussionPost(
          id: '1', title: 'Exam Tips', body: 'study hard', authorName: 'Ram'),
      const DiscussionPost(
          id: '2',
          title: 'Hello',
          body: 'world',
          category: 'resources',
          authorName: 'Sita',
          courseName: 'Nursing',
          subcourseName: 'Staff Nurse'),
    ];
    test('empty query returns everything', () {
      expect(filterDiscussions(posts, ''), hasLength(2));
    });
    test('matches title case-insensitively', () {
      expect(filterDiscussions(posts, 'exam tips').map((p) => p.id), ['1']);
    });
    test('matches category, author, course, subcourse', () {
      expect(filterDiscussions(posts, 'resources').map((p) => p.id), ['2']);
      expect(filterDiscussions(posts, 'sita').map((p) => p.id), ['2']);
      expect(filterDiscussions(posts, 'nursing').map((p) => p.id), ['2']);
      expect(filterDiscussions(posts, 'staff nurse').map((p) => p.id), ['2']);
    });
    test('no match yields empty', () {
      expect(filterDiscussions(posts, 'xyz-nope'), isEmpty);
    });
  });

  group('canSubmitDiscussionPost', () {
    test('empty body never submits', () {
      expect(
          canSubmitDiscussionPost(
              body: '  ', isAdmin: false, title: '', editId: null),
          isFalse);
    });
    test('regular user needs only a body', () {
      expect(
          canSubmitDiscussionPost(
              body: 'hello', isAdmin: false, title: '', editId: null),
          isTrue);
    });
    test('admin new post needs a title', () {
      expect(
          canSubmitDiscussionPost(
              body: 'hello', isAdmin: true, title: '', editId: null),
          isFalse);
      expect(
          canSubmitDiscussionPost(
              body: 'hello', isAdmin: true, title: 'T', editId: null),
          isTrue);
    });
    test('admin edit mode relaxes the title requirement', () {
      expect(
          canSubmitDiscussionPost(
              body: 'hello', isAdmin: true, title: '', editId: 'abc'),
          isTrue);
    });
  });

  group('hasUnsavedDiscussionContent', () {
    test('all empty -> false', () {
      expect(
          hasUnsavedDiscussionContent(
              title: '', body: '', imageUrl: '', linkUrl: ''),
          isFalse);
    });
    test('any field filled -> true', () {
      expect(
          hasUnsavedDiscussionContent(
              title: '', body: 'x', imageUrl: '', linkUrl: ''),
          isTrue);
      expect(
          hasUnsavedDiscussionContent(
              title: '', body: '', imageUrl: '', linkUrl: 'www.a.com'),
          isTrue);
    });
  });

  group('date formatters', () {
    final dt = DateTime(2026, 10, 3, 13, 5);
    test('null -> empty', () {
      expect(formatDiscussionFeedDate(null), '');
      expect(formatDiscussionDetailDateTime(null), '');
      expect(formatDiscussionCommentDate(null), '');
    });
    test('feed format is date-only', () {
      expect(formatDiscussionFeedDate(dt), '2026-10-03');
    });
    test('detail format is full date + time', () {
      expect(formatDiscussionDetailDateTime(dt), '2026-10-03 13:05');
    });
    test('comment format is medium date', () {
      expect(formatDiscussionCommentDate(dt), '03 Oct 2026');
    });
  });

  group('categories', () {
    test('round-trips all values', () {
      for (final c in DiscussionCategory.values) {
        expect(
            discussionCategoryFromValue(discussionCategoryValue(c)), c);
      }
    });
    test('unknown value -> null', () {
      expect(discussionCategoryFromValue('bogus'), isNull);
    });
    test('bilingual labels', () {
      expect(discussionCategoryLabel(DiscussionCategory.tips, 'en'), 'Tips');
      expect(discussionCategoryLabel(DiscussionCategory.tips, 'ne'), 'सुझाव');
      expect(
          discussionCategoryLabel(DiscussionCategory.question, 'ne'), 'प्रश्न');
    });
  });

  group('report types', () {
    test('EN and NE labels exist for all types', () {
      for (final t in DiscussionReportType.values) {
        final en = discussionReportTypeLabel(t, 'en');
        final ne = discussionReportTypeLabel(t, 'ne');
        expect(en, isNotEmpty);
        expect(ne, isNotEmpty);
        expect(en, isNot(ne));
      }
    });
  });

  group('DiscussionPost.fromMap', () {
    test('defaults on missing fields', () {
      final p = DiscussionPost.fromMap({'id': 'x'});
      expect(p.title, '');
      expect(p.authorName, 'Anonymous');
      expect(p.authorPhoto, isNull);
      expect(p.likeCount, 0);
      expect(p.isAdmin, isFalse);
      expect(p.createdAt, isNull);
    });
    test('blank strings become null for optional fields', () {
      final p = DiscussionPost.fromMap({
        'id': 'x',
        'authorPhoto': ' ',
        'courseName': '  ',
        'isAdmin': true,
        'likeCount': 5,
        'commentCount': 2,
      });
      expect(p.authorPhoto, isNull);
      expect(p.courseName, isNull);
      expect(p.isAdmin, isTrue);
      expect(p.likeCount, 5);
      expect(p.commentCount, 2);
    });
  });

  group('DiscussionReply.fromMap', () {
    test('carries parentCommentId', () {
      final r = DiscussionReply.fromMap(
          {'id': 'r1', 'body': 'hi', 'authorName': 'A'}, 'c9');
      expect(r.id, 'r1');
      expect(r.parentCommentId, 'c9');
      expect(r.body, 'hi');
    });
  });

  group('guideline defaults', () {
    test('EN and NE defaults exist', () {
      expect(DiscussionService.defaultGuidelineTitle('en'),
          'Community Guidelines');
      expect(DiscussionService.defaultGuidelineTitle('ne'), 'समुदायका नियमहरू');
      expect(DiscussionService.defaultGuidelineBody('en'), contains('respectful'));
      expect(DiscussionService.defaultGuidelineBullets('en'), hasLength(4));
      expect(DiscussionService.defaultGuidelineBullets('ne'), hasLength(4));
    });
  });
}
