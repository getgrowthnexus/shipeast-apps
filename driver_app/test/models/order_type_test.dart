import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_driver/models/order_type.dart';

/// P5-01. `order_type.dart` is duplicated byte-for-byte into the driver app and
/// `tools/check-status-parity.mjs` fails the build if the copies diverge, so
/// these assertions cover both apps.
void main() {
  group('OrderType.of', () {
    test('passes through the three known types', () {
      expect(OrderType.of('food'), OrderType.food);
      expect(OrderType.of('package'), OrderType.package);
      expect(OrderType.of('overseas'), OrderType.overseas);
    });

    test('an order with no type is a food delivery', () {
      // Not defensive padding: every order written before P5-01 genuinely has
      // no `type` field and genuinely is a food delivery. The migration
      // backfills the same value.
      expect(OrderType.of(null), OrderType.food);
      expect(OrderType.of(''), OrderType.food);
    });

    test('an unrecognised value never reaches a user as a raw slug', () {
      // The same rule OrderStatus.label follows.
      expect(OrderType.of('freight'), OrderType.food);
      expect(OrderType.of('FOOD'), OrderType.food);
      expect(OrderType.of(42), OrderType.food);
      expect(OrderType.of({'type': 'package'}), OrderType.food);
    });
  });

  group('OrderType.isPackage', () {
    test('is true only for a package', () {
      expect(OrderType.isPackage('package'), isTrue);
      expect(OrderType.isPackage('food'), isFalse);
      expect(OrderType.isPackage('overseas'), isFalse);
      expect(OrderType.isPackage(null), isFalse);
    });

    test('a near-miss is not a package', () {
      // A package job routes differently in both apps — no merchant, an
      // address to collect from, no menu to check. Treating 'Package' or
      // 'packages' as one would send a driver to a shop that does not exist.
      expect(OrderType.isPackage('Package'), isFalse);
      expect(OrderType.isPackage('packages'), isFalse);
    });
  });

  group('OrderType.label', () {
    test('every known type has a human label', () {
      expect(OrderType.label('food'), 'Food');
      expect(OrderType.label('package'), 'Package');
      expect(OrderType.label('overseas'), 'Overseas');
    });

    test('an unknown type falls back rather than rendering the slug', () {
      expect(OrderType.label('freight'), 'Food');
      expect(OrderType.label(null), 'Food');
    });
  });
}
