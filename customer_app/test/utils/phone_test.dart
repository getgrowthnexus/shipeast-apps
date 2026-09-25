import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/utils/phone.dart';

/// DR-25: one Jamaican phone format app-wide. Mirrors
/// `driver_app/test/money_test.dart`'s SePhone group — if the two disagree, the
/// two apps show the same number differently.
void main() {
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

    test('leaves an unrecognisable number as typed', () {
      expect(SePhone.format('+44 20 7946 0958'), '+44 20 7946 0958');
      expect(SePhone.format(''), '');
      expect(SePhone.format(null), '');
    });
  });

  group('SePhone.dial', () {
    test('produces an E.164 tel: target', () {
      expect(SePhone.dial('876-555-1234'), '+18765551234');
      expect(SePhone.dial('5551234'), '+18765551234');
    });

    test('empty in, empty out', () {
      expect(SePhone.dial(''), '');
      expect(SePhone.dial(null), '');
    });
  });
}
