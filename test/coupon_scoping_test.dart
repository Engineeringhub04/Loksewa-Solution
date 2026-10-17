// Unit tests for the new coupon scoping fields (validateCouponData is pure).
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/coupon_service.dart';

Map<String, dynamic> _baseCoupon() => {
      'isActive': true,
      'discountType': 'percent',
      'discountValue': 10,
      'maxUses': 0,
      'usedCount': 0,
    };

void main() {
  group('CouponService.validateCouponData — legacy compat', () {
    test('old coupon without new fields validates via legacy logic', () {
      final r = CouponService.validateCouponData(
        {..._baseCoupon(), 'appliesToBillingCycle': 'all'},
        'monthly',
        1000,
      );
      expect(r.valid, isTrue);
      expect(r.discountedAmount, 900);
    });

    test('legacy appliesToBillingCycle still blocks mismatched cycle', () {
      final r = CouponService.validateCouponData(
        {..._baseCoupon(), 'appliesToBillingCycle': 'monthly'},
        'yearly',
        1000,
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('selected plan'));
    });

    test('inactive coupon rejected', () {
      final r = CouponService.validateCouponData(
        {..._baseCoupon(), 'isActive': false},
        'monthly',
        1000,
      );
      expect(r.valid, isFalse);
    });
  });

  group('applicableTo', () {
    test('blocks purchase type not in applicableTo', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['subscription'],
        },
        'exam',
        1000,
        purchaseType: 'subject',
        contentId: 's1',
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('cannot be used for this purchase'));
    });

    test('allows purchase type in applicableTo', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['subject', 'chapter'],
        },
        'exam',
        1000,
        purchaseType: 'subject',
        contentId: 's1',
      );
      expect(r.valid, isTrue);
    });

    test('no purchaseType passed skips applicability check', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['exam'],
        },
        'monthly',
        1000,
      );
      expect(r.valid, isTrue);
    });
  });

  group('userIds scope', () {
    test('blocks user not in userIds', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'userIds': ['uid-a', 'uid-b'],
        },
        'monthly',
        1000,
        purchaseType: 'subscription',
        uid: 'uid-z',
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('not available for your account'));
    });

    test('allows user in userIds', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'userIds': ['uid-a'],
        },
        'monthly',
        1000,
        purchaseType: 'subscription',
        uid: 'uid-a',
      );
      expect(r.valid, isTrue);
    });

    test('empty userIds allows everyone', () {
      final r = CouponService.validateCouponData(
        {..._baseCoupon(), 'userIds': []},
        'monthly',
        1000,
        purchaseType: 'subscription',
        uid: 'anyone',
      );
      expect(r.valid, isTrue);
    });
  });

  group('content scope', () {
    test('subjectIds blocks non-listed subject', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['subject'],
          'subjectIds': ['s1', 's2'],
        },
        'exam',
        1000,
        purchaseType: 'subject',
        contentId: 's9',
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('this subject'));
    });

    test('subjectIds allows listed subject', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['subject'],
          'subjectIds': ['s1'],
        },
        'exam',
        1000,
        purchaseType: 'subject',
        contentId: 's1',
        courseId: 'c1',
        subcourseId: 'sc1',
      );
      expect(r.valid, isTrue);
    });

    test('courseId mismatch blocks', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['subject'],
          'courseId': 'c1',
        },
        'exam',
        1000,
        purchaseType: 'subject',
        contentId: 's1',
        courseId: 'c2',
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('this course'));
    });

    test('subcourseId mismatch blocks', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['subject'],
          'subcourseId': 'sc1',
        },
        'exam',
        1000,
        purchaseType: 'subject',
        contentId: 's1',
        courseId: 'c1',
        subcourseId: 'sc2',
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('sub-course'));
    });

    test('chapterIds blocks non-listed chapter', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['chapter'],
          'chapterIds': ['ch1'],
        },
        'exam',
        1000,
        purchaseType: 'chapter',
        contentId: 'ch9',
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('this chapter'));
    });

    test('examModelIds blocks non-listed exam', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['exam'],
          'examModelIds': ['e1'],
        },
        'exam',
        1000,
        purchaseType: 'exam',
        contentId: 'e9',
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('this exam'));
    });

    test('empty scope arrays mean all content', () {
      final r = CouponService.validateCouponData(
        {
          ..._baseCoupon(),
          'applicableTo': ['subject', 'chapter', 'exam'],
          'subjectIds': [],
          'chapterIds': [],
          'examModelIds': [],
        },
        'exam',
        1000,
        purchaseType: 'chapter',
        contentId: 'anything',
      );
      expect(r.valid, isTrue);
    });
  });

  group('datetime with time', () {
    test('validUntil with time is respected', () {
      final past = DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      final r = CouponService.validateCouponData(
        {..._baseCoupon(), 'validUntil': past},
        'monthly',
        1000,
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('expired'));
    });

    test('validFrom in future blocks', () {
      final future =
          DateTime.now().add(const Duration(hours: 1)).toIso8601String();
      final r = CouponService.validateCouponData(
        {..._baseCoupon(), 'validFrom': future},
        'monthly',
        1000,
      );
      expect(r.valid, isFalse);
      expect(r.reason, contains('not active yet'));
    });
  });
}
