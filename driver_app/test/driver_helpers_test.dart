import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_driver/driver_constants.dart';
import 'package:shipeast_driver/services/inline_image.dart';

/// Client checklist, driver round (Sep 2026): expired documents flagged,
/// a unique driver ID, and one date format.
void main() {
  group('DocExpiry.of', () {
    final now = DateTime(2026, 9, 28, 15, 30);

    test('no date on file is missing', () {
      expect(DocExpiry.of(null, now: now), DocState.missing);
    });

    test('a date before today has expired', () {
      expect(DocExpiry.of(DateTime(2026, 9, 27), now: now), DocState.expired);
    });

    test('today, and up to 30 days out, is expiring soon', () {
      expect(DocExpiry.of(DateTime(2026, 9, 28), now: now),
          DocState.expiringSoon);
      expect(DocExpiry.of(DateTime(2026, 10, 28), now: now),
          DocState.expiringSoon);
    });

    test('beyond the 30-day window is valid', () {
      expect(DocExpiry.of(DateTime(2026, 10, 29), now: now), DocState.valid);
    });
  });

  group('DriverId.of', () {
    test('is SE-DRV- plus the first six characters, upper-cased', () {
      expect(DriverId.of('7k4m2pbcXYZ'), 'SE-DRV-7K4M2P');
    });

    test('short and empty uids do not throw', () {
      expect(DriverId.of('ab1'), 'SE-DRV-AB1');
      expect(DriverId.of(''), '');
    });
  });

  group('AreaName.short', () {
    test('keeps the last two parts and drops the country', () {
      expect(AreaName.short('12 Queen St, Morant Bay, St. Thomas, Jamaica'),
          'Morant Bay, St. Thomas');
    });

    test('short, empty and missing addresses', () {
      expect(AreaName.short('Morant Bay, St. Thomas'), 'Morant Bay, St. Thomas');
      expect(AreaName.short('Kingston'), 'Kingston');
      expect(AreaName.short(''), '');
      expect(AreaName.short(null), '');
    });
  });

  group('SeDate.long', () {
    test('reads July 31, 2026', () {
      expect(SeDate.long(DateTime(2026, 7, 31)), 'July 31, 2026');
    });
  });

  group('InlineImage.decode', () {
    test('round-trips a data URL and rejects anything else', () {
      expect(InlineImage.decode('data:image/jpeg;base64,AAEC'), [0, 1, 2]);
      expect(InlineImage.decode('https://example.com/a.jpg'), isNull);
      expect(InlineImage.decode('data:image/jpeg;base64,***'), isNull);
      expect(InlineImage.decode(null), isNull);
    });
  });
}
