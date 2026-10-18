// Unit tests for lib/services/subscription_service.dart.
//
// Pure-Dart coverage of the client-side subscription surface:
// PlanCategory/PlanFeature parsing (ordering, malformed-entry skipping),
// buildFeatureMatrix (category order, included flags, Nepali labels,
// customFeatures "Also included" group, empty categories), yearlySavePercent,
// and the Firestore map parsers. No network is touched.
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/subscription_service.dart';

SubscriptionPlan _plan({
  String id = 'p1',
  String name = 'Monthly',
  BillingCycle cycle = BillingCycle.monthly,
  num price = 199,
  List<String> features = const [],
  List<PlanCategory> categories = const [],
  List<String> customFeatures = const [],
  String? colorFrom,
  String? colorTo,
  num order = 0,
}) {
  return SubscriptionPlan(
    id: id,
    name: name,
    billingCycle: cycle,
    price: price,
    currency: 'NPR',
    durationDays: 30,
    features: features,
    categories: categories,
    customFeatures: customFeatures,
    isActive: true,
    order: order,
    colorFrom: colorFrom,
    colorTo: colorTo,
  );
}

PlanCategory _cat(
  String key, {
  String icon = 'library',
  num order = 0,
  List<PlanFeature> features = const [],
}) =>
    PlanCategory(
      key: key,
      titleEn: '$key-en',
      titleNe: '$key-ne',
      icon: icon,
      order: order,
      features: features,
    );

PlanFeature _feat(
  String id, {
  String? en,
  String? ne,
  num order = 0,
  bool included = true,
}) =>
    PlanFeature(
      id: id,
      en: en ?? id,
      ne: ne ?? '',
      order: order,
      included: included,
    );

/// Embedded categories mirroring the Firestore shape the admin writes.
final _categories = [
  _cat('learning', order: 1, features: [
    _feat('f-learn-1',
        en: 'All subjects, units & chapters',
        ne: 'सबै विषय, एकाइ र अध्याय',
        order: 1,
        included: true),
    _feat('f-learn-2',
        en: 'Syllabus & study notes library',
        ne: 'पाठ्यक्रम तथा नोट्स संग्रह',
        order: 2,
        included: false),
  ]),
  _cat('community', order: 2, features: [
    _feat('f-support',
        en: 'Priority support', ne: 'प्राथमिकता सहयोग', included: true),
  ]),
];

void main() {
  group('PlanCategory.fromMap / PlanFeature.fromMap', () {
    test('parses the happy path and orders features', () {
      final cat = PlanCategory.fromMap({
        'key': 'learning',
        'titleEn': 'Learning',
        'titleNe': 'सिकाइ',
        'icon': 'library',
        'order': 3,
        'features': [
          {'id': 'b', 'en': 'B', 'order': 2, 'included': true},
          {'id': 'a', 'en': 'A', 'order': 1, 'included': false},
        ],
      })!;
      expect(cat.key, 'learning');
      expect(cat.titleNe, 'सिकाइ');
      expect(cat.icon, 'library');
      expect(cat.features.map((f) => f.id).toList(), ['a', 'b']);
      expect(cat.features.first.included, isFalse);
      expect(cat.features[1].included, isTrue);
    });

    test('skips malformed categories and features, never crashes', () {
      expect(PlanCategory.fromMap({'titleEn': 'no key'}), isNull);
      expect(PlanCategory.fromMap({'key': ''}), isNull);
      final cat = PlanCategory.fromMap({
        'key': 'k',
        'features': [
          {'en': 'no id'},
          {'id': ''},
          'not-a-map',
          {'id': 'ok', 'en': 'Ok'},
          42,
        ],
      })!;
      expect(cat.features.map((f) => f.id).toList(), ['ok']);
    });

    test('missing fields fall back to safe defaults', () {
      final cat = PlanCategory.fromMap({'key': 'k'})!;
      expect(cat.titleEn, 'k');
      expect(cat.titleNe, '');
      expect(cat.icon, '');
      expect(cat.features, isEmpty);
      final f = PlanFeature.fromMap({'id': 'x'})!;
      expect(f.en, 'x');
      expect(f.ne, '');
      expect(f.included, isTrue);
    });

    test('non-list categories/features become empty', () {
      final cat = PlanCategory.fromMap(
          {'key': 'k', 'features': 'nope'})!;
      expect(cat.features, isEmpty);
    });
  });

  group('buildFeatureMatrix', () {
    test('renders categories in order with included flags', () {
      final groups = buildFeatureMatrix(
        categories: _categories,
        customFeatures: const [],
        isNepali: false,
      );
      expect(groups.map((g) => g.key).toList(), ['learning', 'community']);
      final learning = groups.first;
      expect(learning.rows.first.included, isTrue);
      expect(learning.rows[1].included, isFalse);
      expect(learning.includedCount, 1);
      expect(groups[1].rows.first.included, isTrue);
    });

    test('orders unsorted categories by order', () {
      final groups = buildFeatureMatrix(
        categories: [_categories[1], _categories[0]],
        customFeatures: const [],
        isNepali: false,
      );
      expect(groups.map((g) => g.key).toList(), ['learning', 'community']);
    });

    test('customFeatures land in a trailing Also included group', () {
      final groups = buildFeatureMatrix(
        categories: _categories,
        customFeatures: const ['Hand-typed bonus'],
        isNepali: false,
      );
      expect(groups.length, 3);
      final extras = groups.last;
      expect(extras.key, 'extras');
      expect(extras.titleEn, 'Also included');
      expect(extras.titleNe, 'थप समावेश');
      expect(extras.rows.length, 1);
      expect(extras.rows.first.label, 'Hand-typed bonus');
      expect(extras.rows.first.included, isTrue);
    });

    test('no extras group when customFeatures is empty', () {
      final groups = buildFeatureMatrix(
        categories: _categories,
        customFeatures: const [],
        isNepali: false,
      );
      expect(groups.length, 2);
    });

    test('nepali labels flow through the matrix', () {
      final groups = buildFeatureMatrix(
        categories: _categories,
        customFeatures: const [],
        isNepali: true,
      );
      expect(groups.first.rows.first.label, 'सबै विषय, एकाइ र अध्याय');
      expect(groups.first.titleNe, 'learning-ne');
    });

    test('nepali falls back to english when ne is empty', () {
      final groups = buildFeatureMatrix(
        categories: [
          _cat('k', features: [_feat('x', en: 'English only', ne: '')])
        ],
        customFeatures: const [],
        isNepali: true,
      );
      expect(groups.first.rows.first.label, 'English only');
    });

    test('empty categories and no customs yield an empty matrix', () {
      expect(
          buildFeatureMatrix(
              categories: const [], customFeatures: const [], isNepali: false),
          isEmpty);
    });

    test('customFeatures alone still render the extras group', () {
      final groups = buildFeatureMatrix(
        categories: const [],
        customFeatures: const ['Bonus'],
        isNepali: false,
      );
      expect(groups.length, 1);
      expect(groups.first.key, 'extras');
    });
  });

  group('yearlySavePercent', () {
    test('computes the discount from the live plans', () {
      final plans = [
        _plan(id: 'm', cycle: BillingCycle.monthly, price: 100),
        _plan(id: 'y', cycle: BillingCycle.yearly, price: 1000),
      ];
      // 12*100=1200, (1200-1000)/1200 = 16.67% -> 17
      expect(SubscriptionService.yearlySavePercent(plans), 17);
    });

    test('null when yearly costs as much as twelve months', () {
      final plans = [
        _plan(id: 'm', cycle: BillingCycle.monthly, price: 100),
        _plan(id: 'y', cycle: BillingCycle.yearly, price: 1200),
      ];
      expect(SubscriptionService.yearlySavePercent(plans), isNull);
    });

    test('null when either plan is missing or has no price', () {
      expect(
          SubscriptionService.yearlySavePercent(
              [_plan(cycle: BillingCycle.monthly, price: 100)]),
          isNull);
      expect(
          SubscriptionService.yearlySavePercent([
            _plan(cycle: BillingCycle.monthly, price: 0),
            _plan(cycle: BillingCycle.yearly, price: 1000),
          ]),
          isNull);
    });
  });

  group('status / cycle parsing', () {
    test('unknown values fall back to pending / monthly', () {
      expect(subscriptionStatusFrom('weird'), SubscriptionStatus.pending);
      expect(subscriptionStatusFrom(null), SubscriptionStatus.pending);
      expect(billingCycleFrom('weird'), BillingCycle.monthly);
    });

    test('known values map exactly', () {
      expect(subscriptionStatusFrom('active'), SubscriptionStatus.active);
      expect(
          subscriptionStatusFrom('rejected'), SubscriptionStatus.rejected);
      expect(subscriptionStatusFrom('expired'), SubscriptionStatus.expired);
      expect(billingCycleFrom('free'), BillingCycle.free);
      expect(billingCycleFrom('yearly'), BillingCycle.yearly);
      expect(billingCycleFrom('exam'), BillingCycle.exam);
    });
  });

  group('SubscriptionPlan.fromMap', () {
    test('parses fields and honours isActive', () {
      final plan = SubscriptionPlan.fromMap({
        'id': 'yearly1',
        'name': 'Yearly',
        'billingCycle': 'yearly',
        'price': 1999,
        'currency': 'NPR',
        'durationDays': 365,
        'features': ['Priority support'],
        'isActive': true,
        'order': 2,
        'colorFrom': '#0F766E',
        'colorTo': '#4338CA',
      });
      expect(plan.id, 'yearly1');
      expect(plan.billingCycle, BillingCycle.yearly);
      expect(plan.features, ['Priority support']);
      expect(plan.categories, isEmpty);
      expect(plan.customFeatures, isEmpty);
      expect(plan.colorFrom, '#0F766E');
      expect(plan.isActive, isTrue);
    });

    test('parses embedded categories and customFeatures', () {
      final plan = SubscriptionPlan.fromMap({
        'id': 'm1',
        'name': 'Monthly',
        'categories': [
          {
            'key': 'learning',
            'titleEn': 'Learning',
            'titleNe': 'सिकाइ',
            'icon': 'library',
            'order': 1,
            'features': [
              {'id': 'a', 'en': 'A', 'ne': 'ए', 'order': 1, 'included': true},
              {'id': 'b', 'en': 'B', 'order': 2, 'included': false},
            ],
          },
          {'titleEn': 'no key — skipped'},
        ],
        'customFeatures': ['Bonus', '', 42],
      });
      expect(plan.categories.length, 1);
      final cat = plan.categories.first;
      expect(cat.key, 'learning');
      expect(cat.features.length, 2);
      expect(cat.features.first.en, 'A');
      expect(cat.features.first.ne, 'ए');
      expect(cat.features[1].included, isFalse);
      expect(plan.customFeatures, ['Bonus', '42']);
    });

    test('missing categories/customFeatures become empty, never crash', () {
      final plan = SubscriptionPlan.fromMap(
          {'id': 'x', 'name': 'X', 'categories': 'nope'});
      expect(plan.categories, isEmpty);
      expect(plan.customFeatures, isEmpty);
    });

    test('inactive plans parse as inactive', () {
      final plan = SubscriptionPlan.fromMap(
          {'id': 'x', 'name': 'X', 'isActive': false});
      expect(plan.isActive, isFalse);
    });
  });

  group('SubscriptionRecord.fromMap', () {
    Map<String, dynamic> base() => {
          'id': 'r1',
          'uid': 'u1',
          'planId': 'p1',
          'planName': 'Monthly',
          'billingCycle': 'monthly',
          'amount': 199,
          'currency': 'NPR',
          'method': 'qr',
          'status': 'pending',
          'transactionRef': 'TXN1',
          'screenshotUrl': 'https://x/y.jpg',
          'submittedAt': '2026-10-01T10:00:00.000Z',
        };

    test('parses the happy path', () {
      final record = SubscriptionRecord.fromMap(base());
      expect(record.status, SubscriptionStatus.pending);
      expect(record.transactionRef, 'TXN1');
      expect(record.submittedAt, isNotNull);
      expect(record.method, 'qr');
    });

    test('empty optionals become null; bad dates become null', () {
      final m = base()
        ..['transactionRef'] = ''
        ..['customerMessage'] = ''
        ..['submittedAt'] = 'not-a-date';
      final record = SubscriptionRecord.fromMap(m);
      expect(record.transactionRef, isNull);
      expect(record.customerMessage, isNull);
      expect(record.submittedAt, isNull);
    });
  });

  group('currentActiveRecord', () {
    SubscriptionRecord rec(
      String id,
      SubscriptionStatus status, {
      DateTime? submittedAt,
      DateTime? reviewedAt,
      DateTime? startDate,
    }) =>
        SubscriptionRecord(
          id: id,
          uid: 'u1',
          planId: 'p1',
          planName: id,
          billingCycle: BillingCycle.monthly,
          amount: 199,
          currency: 'NPR',
          method: 'qr',
          status: status,
          transactionRef: null,
          screenshotUrl: '',
          customerMessage: null,
          adminMessage: null,
          submittedAt: submittedAt,
          reviewedAt: reviewedAt,
          rejectionReason: null,
          startDate: startDate,
          expiryDate: null,
          couponCode: null,
          userName: null,
          userEmail: null,
        );

    test('returns null when nothing is active', () {
      final records = [
        rec('a', SubscriptionStatus.pending,
            submittedAt: DateTime(2026, 9, 1)),
        rec('b', SubscriptionStatus.rejected,
            submittedAt: DateTime(2026, 9, 2)),
      ];
      expect(SubscriptionService.currentActiveRecord(records), isNull);
      expect(SubscriptionService.currentActiveRecord([]), isNull);
    });

    test('single active record wins regardless of others', () {
      final records = [
        rec('pending-new', SubscriptionStatus.pending,
            submittedAt: DateTime(2026, 10, 1)),
        rec('active-old', SubscriptionStatus.active,
            submittedAt: DateTime(2026, 8, 1),
            startDate: DateTime(2026, 8, 2)),
      ];
      expect(
          SubscriptionService.currentActiveRecord(records)!.id, 'active-old');
    });

    test('with several actives picks the last-approved, not the last-submitted',
        () {
      // The mirror on users/{uid} is written at approval time, so the
      // last-approved active is the record the profile pill describes.
      final records = [
        rec('monthly', SubscriptionStatus.active,
            submittedAt: DateTime(2026, 10, 1, 12),
            startDate: DateTime(2026, 9, 20)),
        rec('yearly', SubscriptionStatus.active,
            submittedAt: DateTime(2026, 9, 25),
            startDate: DateTime(2026, 9, 30)),
      ];
      expect(
          SubscriptionService.currentActiveRecord(records)!.id, 'yearly');
    });

    test('falls back to reviewedAt then submittedAt when startDate is missing',
        () {
      final records = [
        rec('a', SubscriptionStatus.active,
            submittedAt: DateTime(2026, 10, 1),
            reviewedAt: DateTime(2026, 9, 5)),
        rec('b', SubscriptionStatus.active,
            submittedAt: DateTime(2026, 9, 1),
            reviewedAt: DateTime(2026, 9, 20)),
      ];
      expect(SubscriptionService.currentActiveRecord(records)!.id, 'b');
    });
  });
}
