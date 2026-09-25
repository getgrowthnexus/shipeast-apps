import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/models/package_pricing.dart';

/// P5-01. The Packages category used to validate a form, show "Package request
/// submitted! We'll contact you shortly," and write nothing. These tests pin
/// the pricing half of making it real.
///
/// The single most important assertion in this file is the group titled
/// "an unconfigured price list quotes nothing": the feature must refuse to
/// operate rather than invent a number.
void main() {
  Map<String, dynamic> settings([Map<String, dynamic> overrides = const {}]) => {
        'packageBands': [
          {'maxKg': 2, 'price': 600},
          {'maxKg': 5, 'price': 900},
          {'maxKg': 10, 'price': 1400},
          {'maxKg': null, 'price': 2200},
        ],
        'packageOveragePerKg': 100,
        'packingSurcharge': 350,
        'packageMaxWeightKg': 50,
        ...overrides,
      };

  group('an unconfigured price list quotes nothing', () {
    test('a missing settings document yields no pricing', () {
      expect(PackagePricing.fromSettings(null), isNull);
    });

    test('a settings document with no bands yields no pricing', () {
      expect(PackagePricing.fromSettings({'driverCommissionRate': 0.1}), isNull);
    });

    test('an empty band list yields no pricing', () {
      expect(PackagePricing.fromSettings({'packageBands': []}), isNull);
    });

    test('one malformed band rejects the whole table', () {
      // Pricing off a partially-parsed list would quote from a table the admin
      // never approved. Half a price list is not a price list.
      final p = PackagePricing.fromSettings(settings({
        'packageBands': [
          {'maxKg': 2, 'price': 600},
          {'maxKg': 5}, // no price
        ],
      }));
      expect(p, isNull);
    });

    test('two open-ended bands are ambiguous, not merely untidy', () {
      final p = PackagePricing.fromSettings(settings({
        'packageBands': [
          {'maxKg': null, 'price': 600},
          {'maxKg': null, 'price': 900},
        ],
      }));
      expect(p, isNull);
    });

    test('a band with a non-positive bound is rejected', () {
      // maxKg: 0 is unreachable, so every parcel silently falls to the next
      // band and the admin's cheapest tier never applies.
      final p = PackagePricing.fromSettings(settings({
        'packageBands': [
          {'maxKg': 0, 'price': 600},
          {'maxKg': null, 'price': 900},
        ],
      }));
      expect(p, isNull);
    });
  });

  group('band selection', () {
    late PackagePricing p;
    setUp(() => p = PackagePricing.fromSettings(settings())!);

    test('a 1 kg parcel takes the first band', () {
      expect(p.deliveryFeeFor(1), 600);
      expect(p.bandLabel(1), '0–2 kg');
    });

    test('the bound is inclusive — 2 kg is still the first band', () {
      // Exclusive bounds leave a gap exactly on the boundary, which is the
      // weight customers are most likely to type.
      expect(p.deliveryFeeFor(2), 600);
    });

    test('just over the bound moves up a band', () {
      expect(p.deliveryFeeFor(2.1), 900);
      expect(p.bandLabel(2.1), '2–5 kg');
    });

    test('the third band prices at its flat rate', () {
      expect(p.deliveryFeeFor(9.5), 1400);
    });

    test('bands supplied out of order still price correctly', () {
      final shuffled = PackagePricing.fromSettings(settings({
        'packageBands': [
          {'maxKg': 10, 'price': 1400},
          {'maxKg': null, 'price': 2200},
          {'maxKg': 2, 'price': 600},
          {'maxKg': 5, 'price': 900},
        ],
      }))!;
      expect(shuffled.deliveryFeeFor(1), 600);
      expect(shuffled.deliveryFeeFor(7), 1400);
    });
  });

  group('the open-ended band', () {
    late PackagePricing p;
    setUp(() => p = PackagePricing.fromSettings(settings())!);

    test('at the base weight it is the flat rate', () {
      expect(p.deliveryFeeFor(10.0), 1400); // still the bounded band
      expect(p.deliveryFeeFor(10.5), 2200 + 100); // 0.5 kg over → 1 whole kg
    });

    test('overage is charged per whole kilogram, rounded up', () {
      // 12 kg is 2 kg over the last bounded band.
      expect(p.deliveryFeeFor(12), 2200 + 200);
      // 12.2 kg occupies the same space as 13 kg on a bike.
      expect(p.deliveryFeeFor(12.2), 2200 + 300);
    });

    test('its label names the floor, not a fake ceiling', () {
      expect(p.bandLabel(12), 'Over 10 kg');
    });

    test('a zero overage rate leaves the open band flat', () {
      final flat = PackagePricing.fromSettings(
          settings({'packageOveragePerKg': 0}))!;
      expect(flat.deliveryFeeFor(40), 2200);
    });
  });

  group('weights that cannot be priced', () {
    late PackagePricing p;
    setUp(() => p = PackagePricing.fromSettings(settings())!);

    test('zero and negative weights are not a free parcel', () {
      expect(p.deliveryFeeFor(0), isNull);
      expect(p.deliveryFeeFor(-3), isNull);
    });

    test('above the maximum the app declines rather than quoting', () {
      expect(p.deliveryFeeFor(50), isNotNull);
      expect(p.deliveryFeeFor(50.1), isNull);
      expect(p.quote(weightKg: 80, packing: false), isNull);
    });

    test('a table with no open-ended band cannot price a heavy parcel', () {
      final capped = PackagePricing.fromSettings(settings({
        'packageBands': [
          {'maxKg': 2, 'price': 600},
        ],
      }))!;
      expect(capped.deliveryFeeFor(1), 600);
      expect(capped.deliveryFeeFor(9), isNull);
    });
  });

  group('the quote reconciles', () {
    late PackagePricing p;
    setUp(() => p = PackagePricing.fromSettings(settings())!);

    test('packing goes to serviceFee, not into the delivery fee', () {
      // Keeping them apart is what lets the order document say which part of
      // the charge was transport and which was handling.
      final q = p.quote(weightKg: 3, packing: true)!;
      expect(q.deliveryFee, 900);
      expect(q.serviceFee, 350);
      expect(q.subtotal, 0);
    });

    test('no packing means no service fee', () {
      final q = p.quote(weightKg: 3, packing: false)!;
      expect(q.serviceFee, 0);
    });

    test('total satisfies the invariant rules enforce on create', () {
      // subtotal + deliveryFee + serviceFee - discount == total (P2-01).
      // A package order that fails this is rejected by the server, so the
      // customer would see the form succeed and no order would exist —
      // exactly the defect P5-01 exists to remove.
      for (final w in <double>[0.5, 2, 4.9, 10, 23.4, 49]) {
        for (final packing in [true, false]) {
          final q = p.quote(weightKg: w, packing: packing)!;
          expect(q.subtotal + q.deliveryFee + q.serviceFee - 0, q.total,
              reason: 'weight $w, packing $packing');
        }
      }
    });

    test('every quoted figure is a whole number of dollars', () {
      // Rules require int on all four money fields; a double fails the write.
      final fractional = PackagePricing.fromSettings(settings({
        'packageBands': [
          {'maxKg': 2, 'price': 599.5},
          {'maxKg': null, 'price': 2200},
        ],
        'packingSurcharge': 349.4,
      }))!;
      final q = fractional.quote(weightKg: 1, packing: true)!;
      expect(q.deliveryFee, 600);
      expect(q.serviceFee, 349);
      expect(q.total, 949);
    });
  });

  group('parseWeightKg', () {
    test('accepts a plain decimal', () {
      expect(parseWeightKg('2.5'), 2.5);
    });

    test('accepts a comma decimal separator', () {
      expect(parseWeightKg('2,5'), 2.5);
    });

    test('trims surrounding space', () {
      expect(parseWeightKg('  3 '), 3);
    });

    test('rejects junk rather than defaulting to the cheapest band', () {
      for (final input in ['', '   ', 'abc', '-1', '0', 'NaN', '2kg']) {
        expect(parseWeightKg(input), isNull, reason: 'input "$input"');
      }
    });
  });
}
