import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/utils/money.dart';

/// P3-06. The case that motivated this: every `_formatPrice` copy inserted
/// exactly one separator, so anything over a million rendered wrong.
void main() {
  group('Money.plain', () {
    test('inserts a separator every three digits, not just once', () {
      // The old implementation returned '1234,567' here.
      expect(Money.plain(1234567), '1,234,567');
      expect(Money.plain(1234567890), '1,234,567,890');
    });

    test('leaves values below a thousand alone', () {
      expect(Money.plain(0), '0');
      expect(Money.plain(1), '1');
      expect(Money.plain(999), '999');
    });

    test('handles the thousands boundary', () {
      expect(Money.plain(1000), '1,000');
      expect(Money.plain(1001), '1,001');
      expect(Money.plain(999999), '999,999');
    });

    test('rounds rather than truncating', () {
      expect(Money.plain(1499.6), '1,500');
      expect(Money.plain(1499.4), '1,499');
    });

    test('treats null as zero so a missing amount never renders as "null"', () {
      expect(Money.plain(null), '0');
    });

    test('keeps the sign outside the digits', () {
      expect(Money.plain(-1234567), '-1,234,567');
    });
  });

  group('Money.format', () {
    test('prefixes the currency symbol', () {
      expect(Money.format(250), r'J$250');
      expect(Money.format(1234567), r'J$1,234,567');
    });

    test('uses the J\$ prefix, spelled out for Jamaican dollars', () {
      // Client request (checklist DR-13 / DB-1): every money value reads "J$"
      // so it is unambiguous against USD. Pinned here in all three apps so a
      // stray revert to a bare "$" shows up in CI, not on a checkout screen.
      expect(Money.format(250).startsWith(r'J$'), isTrue);
      expect(Money.symbol, r'J$');
    });
  });

  group('Money.deliveryFee', () {
    test('says Free rather than J\$0', () {
      // "J$0" reads like a missing value; "Free" is the actual offer.
      expect(Money.deliveryFee(0), 'Free');
    });

    test('formats a real fee', () {
      expect(Money.deliveryFee(250), r'J$250');
    });
  });
}
