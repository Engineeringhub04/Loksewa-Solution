// Unit tests for lib/services/subscription_service.dart.
//
// Pure-Dart coverage of the client-side subscription surface: the feature
// catalogue integrity (mirrors PLAN_FEATURE_GROUPS), planFeatureLabel,
// buildFeatureMatrix (included/excluded + extras group), yearlySavePercent,
// and the Firestore map parsers. No network is touched.
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/subscription_service.dart';

SubscriptionPlan _plan({
  String id = 'p1',
  String name = 'Monthly',
  BillingCycle cycle = BillingCycle.monthly,
  num price = 199,
  List<String> features = const [],
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
    isActive: true,
    order: order,
    colorFrom: colorFrom,
    colorTo: colorTo,
  );
}

void main() {
  group('planFeatureGroups catalogue', () {
    test('has the four React catalogue groups in order', () {
      expect(planFeatureGroups.map((g) => g.key).toList(),
          ['learning', 'practice', 'progress', 'community']);
    });

    test('every feature has an id and a Nepali label; ids are unique', () {
      final ids = <String>{};
      var count = 0;
      for (final group in planFeatureGroups) {
        expect(group.titleEn.isNotEmpty, isTrue);
        expect(group.titleNe.isNotEmpty, isTrue);
        for (final feature in group.features) {
          expect(feature.id.isNotEmpty, isTrue);
          expect(feature.ne.isNotEmpty, isTrue);
          expect(ids.add(feature.id), isTrue,
              reason: 'duplicate feature id ${feature.id}');
          count++;
        }
      }
      expect(count, greaterThan(20));
    });
  });

  group('planFeatureLabel', () {
    test('english returns the stored id verbatim', () {
      expect(planFeatureLabel('All subjects, units & chapters', false),
          'All subjects, units & chapters');
    });

    test('nepali returns the catalogue label for known ids', () {
      expect(planFeatureLabel('All subjects, units & chapters', true),
          'सबै विषय, एकाइ र अध्याय');
      expect(planFeatureLabel('Priority support', true), 'प्राथमिकता सहयोग');
    });

    test('nepali falls back to the stored string for unknown ids', () {
      expect(planFeatureLabel('Some admin-typed feature', true),
          'Some admin-typed feature');
    });
  });

  group('buildFeatureMatrix', () {
    test('marks owned features included and the rest excluded', () {
      final groups = buildFeatureMatrix(
          ['All subjects, units & chapters', 'Daily practice questions'],
          false);
      final learning =
          groups.firstWhere((g) => g.key == 'learning');
      expect(learning.rows.first.included, isTrue);
      expect(learning.rows[1].included, isFalse);
      expect(learning.includedCount, 1);
      final practice =
          groups.firstWhere((g) => g.key == 'practice');
      expect(practice.rows.first.included, isTrue);
    });

    test('unknown stored features land in a trailing extras group', () {
      final groups = buildFeatureMatrix(
          ['All subjects, units & chapters', 'Hand-typed bonus'], false);
      expect(groups.length, 5);
      final extras = groups.last;
      expect(extras.key, 'extras');
      expect(extras.rows.length, 1);
      expect(extras.rows.first.label, 'Hand-typed bonus');
      expect(extras.rows.first.included, isTrue);
      expect(extras.includedCount, 1);
    });

    test('no extras group when every stored feature is known', () {
      final groups =
          buildFeatureMatrix(['All subjects, units & chapters'], false);
      expect(groups.length, 4);
    });

    test('nepali labels flow through the matrix', () {
      final groups = buildFeatureMatrix(
          ['All subjects, units & chapters'], true);
      expect(groups.first.rows.first.label, 'सबै विषय, एकाइ र अध्याय');
      expect(groups.first.titleNe, 'अध्ययन तथा सामग्री');
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
      expect(plan.colorFrom, '#0F766E');
      expect(plan.isActive, isTrue);
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
