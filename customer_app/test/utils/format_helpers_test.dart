import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/utils/category.dart';
import 'package:shipeast_customer/utils/dates.dart';
import 'package:shipeast_customer/utils/money.dart';
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

  group('Money.inCurrency', () {
    test('US dollars read USD\$31; anything else is J\$', () {
      expect(Money.inCurrency(31, 'USD'), 'USD\$31');
      expect(Money.inCurrency(3100, 'JMD'), 'J\$3,100');
      expect(Money.inCurrency(3100, null), 'J\$3,100');
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
      expect(MerchantCategory.label('Something new'), 'Something new');
    });

    test('home tiles and the More list follow the client checklist', () {
      expect(MerchantCategory.primary.map((c) => c.display),
          ['Food', 'Groceries', 'Packages']);
      expect(MerchantCategory.more.map((c) => c.display), [
        'Pharmacy',
        'Cooking Gas',
        'Hardware',
        'Errands',
        'Gifts/Balloons',
        'Pickup & Delivery',
        'Business Services',
      ]);
    });

    test('every stored value is unique and resolves back to itself', () {
      final values = MerchantCategory.all.map((c) => c.value).toList();
      expect(values.toSet().length, values.length);
      for (final c in MerchantCategory.all) {
        expect(MerchantCategory.of(c.value), same(c));
      }
      expect(MerchantCategory.of('Nope'), isNull);
    });
  });
}
