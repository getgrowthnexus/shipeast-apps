import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/utils/category.dart';
import 'package:shipeast_customer/utils/dates.dart';
import 'package:shipeast_customer/utils/names.dart';

/// Client checklist (Sep 2026): one date format, Title Case names, and
/// "Groceries" on screen without touching the stored category.
void main() {
  group('SeDate', () {
    final dt = DateTime(2026, 7, 31, 18, 42);

    test('long reads July 31, 2026', () {
      expect(SeDate.long(dt), 'July 31, 2026');
    });

    test('clock is 12-hour with AM/PM', () {
      expect(SeDate.clock(dt), '6:42 PM');
      expect(SeDate.clock(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
      expect(SeDate.clock(DateTime(2026, 1, 1, 12, 0)), '12:00 PM');
    });

    test('longWithTime joins the two', () {
      expect(SeDate.longWithTime(dt), 'July 31, 2026 · 6:42 PM');
    });
  });

  group('SeName.title', () {
    test('capitalises each word', () {
      expect(SeName.title('chris brown'), 'Chris Brown');
      expect(SeName.title('CHRIS BROWN'), 'Chris Brown');
    });

    test('handles hyphens and apostrophes', () {
      expect(SeName.title("mary-jane o'brien"), "Mary-Jane O'Brien");
    });

    test('keeps a deliberately mixed-case word as typed', () {
      expect(SeName.title('andre McDonald'), 'Andre McDonald');
    });

    test('trims and collapses spaces; null and empty are empty', () {
      expect(SeName.title('  kemar   brown '), 'Kemar Brown');
      expect(SeName.title(''), '');
      expect(SeName.title(null), '');
    });
  });

  group('MerchantCategory.label', () {
    test('shows Groceries for the stored Grocery value', () {
      expect(MerchantCategory.label('Grocery'), 'Groceries');
    });

    test('passes every other category through', () {
      expect(MerchantCategory.label('Food'), 'Food');
      expect(MerchantCategory.label('Pharmacy'), 'Pharmacy');
    });
  });
}
