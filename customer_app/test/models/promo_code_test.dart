import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/models/promo_code.dart';

/// P3-03. This mirrors `functions/src/promo.test.ts` case for case. The two
/// copies exist because there is no shared package yet (P6-04); if they ever
/// disagree, the customer sees one discount at checkout and is charged
/// another.
void main() {
  final now = DateTime.utc(2026, 7, 21);
  const day = Duration(days: 1);

  Map<String, dynamic> promo([Map<String, dynamic> overrides = const {}]) => {
        'code': 'SAVE200',
        'discountType': 'fixed',
        'discountAmount': 200,
        'minOrderTotal': 0,
        'maxDiscount': null,
        'expiresAt': null,
        'maxUses': 100,
        'usedCount': 0,
        'active': true,
        ...overrides,
      };

  group('the discount actually applies', () {
    test('a J\$200-off code takes off J\$200', () {
      // The acceptance criterion. It used to take off J$0, because the customer
      // read `discount` while the admin wrote `discountAmount`.
      final r = PromoCodes.evaluate(promo(), 1500, now);
      expect(r.isValid, isTrue);
      expect(r.discount, 200);
    });

    test('a percentage code discounts the subtotal', () {
      final r = PromoCodes.evaluate(
          promo({'discountType': 'percent', 'discountAmount': 20}), 1500, now);
      expect(r.discount, 300);
    });

    test('a discount never exceeds the subtotal', () {
      final r = PromoCodes.evaluate(promo({'discountAmount': 5000}), 1500, now);
      expect(r.discount, 1500);
    });
  });

  group('the cap on percentage codes', () {
    test('maxDiscount caps a percentage discount', () {
      final r = PromoCodes.evaluate(
        promo({
          'discountType': 'percent',
          'discountAmount': 50,
          'maxDiscount': 500
        }),
        10000,
        now,
      );
      expect(r.discount, 500);
    });

    test('an uncapped percentage code still applies in full', () {
      final r = PromoCodes.evaluate(
        promo({'discountType': 'percent', 'discountAmount': 50}),
        10000,
        now,
      );
      expect(r.discount, 5000);
    });

    test('a percentage over 100 clamps rather than going negative', () {
      final r = PromoCodes.evaluate(
        promo({'discountType': 'percent', 'discountAmount': 150}),
        1000,
        now,
      );
      expect(r.discount, 1000);
    });
  });

  group('rejections', () {
    test('an unknown code is rejected', () {
      expect(PromoCodes.evaluate(null, 1500, now).reason,
          PromoRejection.notFound);
    });

    test('an inactive code is rejected', () {
      expect(PromoCodes.evaluate(promo({'active': false}), 1500, now).reason,
          PromoRejection.inactive);
    });

    test('an expired code is rejected', () {
      final r = PromoCodes.evaluate(
          promo({'expiresAt': now.subtract(day)}), 1500, now);
      expect(r.reason, PromoRejection.expired);
      expect(r.discount, 0);
    });

    test('a code expiring tomorrow still works', () {
      expect(
          PromoCodes.evaluate(promo({'expiresAt': now.add(day)}), 1500, now)
              .isValid,
          isTrue);
    });

    test('a null expiry means never expires', () {
      expect(PromoCodes.evaluate(promo(), 1500, now).isValid, isTrue);
    });

    test('a code with a future start date is not redeemable yet (PR-6)', () {
      final r = PromoCodes.evaluate(
          promo({'startsAt': now.add(day)}), 1500, now);
      expect(r.reason, PromoRejection.notYetStarted);
      expect(r.discount, 0);
    });

    test('a code whose start has passed works', () {
      expect(
          PromoCodes.evaluate(promo({'startsAt': now.subtract(day)}), 1500, now)
              .isValid,
          isTrue);
    });

    test('an exhausted code is rejected', () {
      final r = PromoCodes.evaluate(
          promo({'maxUses': 5, 'usedCount': 5}), 1500, now);
      expect(r.reason, PromoRejection.exhausted);
    });

    test('the last available use still works', () {
      // Off by one here either burns a use the customer paid for, or gives
      // one away.
      expect(
          PromoCodes.evaluate(promo({'maxUses': 5, 'usedCount': 4}), 1500, now)
              .isValid,
          isTrue);
    });

    test('an order below the minimum is rejected', () {
      final r =
          PromoCodes.evaluate(promo({'minOrderTotal': 2000}), 1500, now);
      expect(r.reason, PromoRejection.belowMinimum);
    });

    test('an order exactly at the minimum is accepted', () {
      expect(
          PromoCodes.evaluate(promo({'minOrderTotal': 1500}), 1500, now)
              .isValid,
          isTrue);
    });

    test("the old 'percentage' spelling is rejected, not silently applied", () {
      // The customer used to compare against 'percentage' while the admin
      // wrote 'percent', so every code fell through to the fixed-amount
      // branch. Treating it as malformed surfaces any unmigrated document
      // instead of quietly mispricing it.
      final r =
          PromoCodes.evaluate(promo({'discountType': 'percentage'}), 1500, now);
      expect(r.reason, PromoRejection.malformed);
    });

    test('PR-5: a delivery-fee-only code discounts the delivery fee, not the subtotal', () {
      // 20% off a J$300 delivery fee, on a J$5,000 order — the discount must
      // be J$60, not J$1,000.
      final r = PromoCodes.evaluate(
        promo({'discountType': 'percent', 'discountAmount': 20, 'maxDiscount': 10000}),
        5000,
        now,
        300,
      );
      expect(r.isValid, isTrue);
      expect(r.discount, 60);
    });

    test('PR-5: the minimum-order check still runs against the real subtotal', () {
      // Even though the discount comes off the delivery fee, "spend at least
      // J$2,000" means the order total, not the fee.
      final r = PromoCodes.evaluate(
        promo({'minOrderTotal': 2000}),
        1500,
        now,
        300,
      );
      expect(r.reason, PromoRejection.belowMinimum);
    });

    test('PR-5: a delivery-fee discount cannot exceed the delivery fee itself', () {
      final r = PromoCodes.evaluate(
        promo({'discountType': 'fixed', 'discountAmount': 9999}),
        5000,
        now,
        300,
      );
      expect(r.isValid, isTrue);
      expect(r.discount, 300);
    });

    test('every rejection carries a zero discount and a readable message', () {
      final cases = [
        promo({'active': false}),
        promo({'expiresAt': now.subtract(day)}),
        promo({'maxUses': 1, 'usedCount': 1}),
        promo({'minOrderTotal': 99999}),
      ];
      for (final c in cases) {
        final r = PromoCodes.evaluate(c, 1500, now);
        expect(r.isValid, isFalse);
        expect(r.discount, 0);
        expect(r.message, isNotNull);
      }
    });
  });
}
