import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_driver/driver_constants.dart';

/// The driver app's `Money` is the original the customer app's copy was ported
/// from (P3-06), yet nothing pinned its behaviour until now. Both apps render
/// the same order — a driver seeing a different figure from the customer on
/// the same delivery is a support call, or a dispute.
///
/// Mirrors `customer_app/test/utils/money_test.dart`. If the two files ever
/// disagree, the two apps disagree.
void main() {
  group('Money.plain', () {
    test('groups every thousands boundary, not just the first', () {
      // The bug this formatter exists to avoid: a single separator, so
      // 1234567 renders as "1234,567".
      expect(Money.plain(1234567), '1,234,567');
      expect(Money.plain(999), '999');
      expect(Money.plain(1000), '1,000');
      expect(Money.plain(1000000), '1,000,000');
    });

    test('rounds to whole units — money is stored as integers', () {
      expect(Money.plain(12345.6), '12,346');
      expect(Money.plain(12345.4), '12,345');
    });

    test('a null amount is zero, not a crash or an empty string', () {
      expect(Money.plain(null), '0');
    });

    test('keeps the sign on a negative amount', () {
      expect(Money.plain(-1234567), '-1,234,567');
    });
  });

  group('Money.format', () {
    test('prefixes the currency symbol', () {
      expect(Money.format(250), r'J$250');
      expect(Money.format(1234567), r'J$1,234,567');
    });

    test('uses the J\$ prefix, spelled out for Jamaican dollars', () {
      // Client request (checklist DR-13 / DB-1): every money value reads "J$".
      // Pinned in both Flutter apps and the admin panel so a revert to a bare
      // "$" in any one of them fails here rather than shipping.
      expect(Money.format(250).startsWith(r'J$'), isTrue);
      expect(Money.symbol, r'J$');
    });
  });

  // DR-25: one Jamaican phone format everywhere. Mirrored in
  // customer_app/test/utils/phone_test.dart — keep the two in step.
  group('SePhone.format', () {
    test('formats a 10-digit local number as 1-876-000-0000', () {
      expect(SePhone.format('8765551234'), '1-876-555-1234');
      expect(SePhone.format('876 555 1234'), '1-876-555-1234');
      expect(SePhone.format('(876) 555-1234'), '1-876-555-1234');
    });

    test('drops a leading country code before formatting', () {
      expect(SePhone.format('18765551234'), '1-876-555-1234');
      expect(SePhone.format('+1 876 555 1234'), '1-876-555-1234');
    });

    test('assumes 876 for a bare 7-digit number', () {
      expect(SePhone.format('5551234'), '1-876-555-1234');
    });

    test('leaves an unrecognisable number as typed rather than mangling it', () {
      expect(SePhone.format('+44 20 7946 0958'), '+44 20 7946 0958');
      expect(SePhone.format('call me'), 'call me');
      expect(SePhone.format(''), '');
      expect(SePhone.format(null), '');
    });
  });

  group('SePhone.dial', () {
    test('produces an E.164 tel: target', () {
      expect(SePhone.dial('876-555-1234'), '+18765551234');
      expect(SePhone.dial('5551234'), '+18765551234');
      expect(SePhone.dial('1-876-555-1234'), '+18765551234');
    });

    test('empty in, empty out', () {
      expect(SePhone.dial(''), '');
      expect(SePhone.dial(null), '');
    });
  });
}
