/// What kind of job an order is (P5-01).
///
/// SCHEMA.md §orders has specified `type` since Phase 1 and nothing ever wrote
/// it, because only one kind of order could be placed: a food delivery. Now
/// that Packages is real, a driver's queue and the admin's order table both
/// contain two kinds of work that need different handling, and neither could
/// tell them apart.
///
/// THIS FILE IS DUPLICATED, BYTE FOR BYTE, IN BOTH FLUTTER APPS:
///   customer_app/lib/models/order_type.dart
///   driver_app/lib/models/order_type.dart
/// `tools/check-status-parity.mjs` fails the build if they diverge. Edit both,
/// or neither. The duplication goes away with packages/shipeast_core (P6-04).
library;

class OrderType {
  OrderType._();

  /// A delivery from a merchant. The default for every order written before
  /// P5-01, and the value the migration backfills.
  static const food = 'food';

  /// A point-to-point courier job with no merchant and no goods.
  static const package = 'package';

  /// Diaspora ordering. Reserved — the feature is an enquiry that an admin
  /// prices by hand (`overseasInquiries`), not an order, so no order of this
  /// type can be created. It is declared here so that when overseas shipping
  /// does become an order it is not invented twice.
  static const overseas = 'overseas';

  static const all = <String>[food, package, overseas];

  /// The type of [raw], falling back to [food].
  ///
  /// The fallback is not defensive padding: every order placed before P5-01
  /// genuinely has no `type` field and genuinely is a food delivery. An
  /// unrecognised value also lands here rather than rendering a raw slug to a
  /// user, which is the same rule `OrderStatus.label` follows.
  static String of(Object? raw) {
    final value = raw is String ? raw : '';
    return all.contains(value) ? value : food;
  }

  static bool isPackage(Object? raw) => of(raw) == package;

  /// Display label. Raw type values are never rendered to a user.
  static String label(Object? raw) {
    switch (of(raw)) {
      case package:
        return 'Package';
      case overseas:
        return 'Overseas';
      default:
        return 'Food';
    }
  }
}
