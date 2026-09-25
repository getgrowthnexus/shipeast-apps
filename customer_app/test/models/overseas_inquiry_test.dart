import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/models/overseas_inquiry.dart';

/// The shop-and-deliver screen was a WebView pointed at two placeholder form
/// URLs this project does not own; it contained zero Firestore writes, so even
/// a form that loaded reached nothing. It is now a real request that an admin
/// works from a queue: we shop at a local Jamaican store and deliver to the
/// customer's family — no shipping, no customs.
///
/// What is pinned here is the boundary between the two: which requests are
/// complete enough for an operator to shop against, and what shape the document
/// takes. A request that reaches the panel missing a phone number is a request
/// nobody can answer — which is the defect all over again, one step further
/// along.

/// A draft with everything filled in. Individual tests break one field at a
/// time, so a new required field fails loudly here rather than silently
/// weakening every other case.
OverseasInquiryDraft valid({
  String contactEmail = 'marcia@example.com',
  String contactPhone = '+1 718 555 0134',
  String originCountry = 'Brooklyn, USA',
  String recipientName = 'Delroy Brown',
  String recipientPhone = '876 555 0110',
  String recipientAddress = '14 Bay Street, Morant Bay',
  String recipientParish = 'St. Thomas',
  String itemCategory = 'Groceries & food',
  String itemDescription = '3 tins of ackee, 2 packs of rice',
  String requestedStore = '',
  String budgetRaw = '',
  String notes = '',
}) =>
    OverseasInquiryDraft(
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      originCountry: originCountry,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      recipientAddress: recipientAddress,
      recipientParish: recipientParish,
      itemCategory: itemCategory,
      itemDescription: itemDescription,
      requestedStore: requestedStore,
      budgetRaw: budgetRaw,
      notes: notes,
    );

void main() {
  group('OverseasStatus', () {
    test('an unknown or missing status reads as newly submitted', () {
      // A document with no status is one the server has just accepted.
      expect(OverseasStatus.of(null), OverseasStatus.submitted);
      expect(OverseasStatus.of(''), OverseasStatus.submitted);
      expect(OverseasStatus.of('in_progress'), OverseasStatus.submitted);
      expect(OverseasStatus.of(7), OverseasStatus.submitted);
    });

    test('open and terminal together account for every status', () {
      expect(
        {...OverseasStatus.open, ...OverseasStatus.terminal},
        OverseasStatus.all.toSet(),
      );
      // Nothing may be both — the panel counts the open queue by exclusion.
      expect(
        OverseasStatus.open.toSet().intersection(OverseasStatus.terminal.toSet()),
        isEmpty,
      );
    });

    test('a finished request is not still open', () {
      expect(OverseasStatus.isOpen(OverseasStatus.submitted), isTrue);
      expect(OverseasStatus.isOpen(OverseasStatus.quoteSent), isTrue);
      expect(OverseasStatus.isOpen(OverseasStatus.shopping), isTrue);
      expect(OverseasStatus.isOpen(OverseasStatus.completed), isFalse);
      expect(OverseasStatus.isOpen(OverseasStatus.declined), isFalse);
      expect(OverseasStatus.isOpen(OverseasStatus.cancelled), isFalse);
      expect(OverseasStatus.isOpen(OverseasStatus.expired), isFalse);
    });

    test('SD-4: the nine-stage pipeline plus three outcomes', () {
      expect(OverseasStatus.pipeline, [
        OverseasStatus.submitted,
        OverseasStatus.reviewing,
        OverseasStatus.quoteSent,
        OverseasStatus.awaitingCustomer,
        OverseasStatus.approved,
        OverseasStatus.shopping,
        OverseasStatus.readyForDelivery,
        OverseasStatus.outForDelivery,
        OverseasStatus.completed,
      ]);
      expect(OverseasStatus.outcomes,
          [OverseasStatus.declined, OverseasStatus.cancelled, OverseasStatus.expired]);
      expect(OverseasStatus.all.length, 12);
    });

    test('the pre-SD-4 slugs map onto the nearest new state', () {
      expect(OverseasStatus.of('contacted'), OverseasStatus.reviewing);
      expect(OverseasStatus.of('quoted'), OverseasStatus.quoteSent);
      expect(OverseasStatus.of('closed'), OverseasStatus.completed);
    });

    test('declined / cancelled / expired read as unsuccessful; completed does not', () {
      expect(OverseasStatus.isUnsuccessful(OverseasStatus.declined), isTrue);
      expect(OverseasStatus.isUnsuccessful(OverseasStatus.cancelled), isTrue);
      expect(OverseasStatus.isUnsuccessful(OverseasStatus.expired), isTrue);
      expect(OverseasStatus.isUnsuccessful(OverseasStatus.completed), isFalse);
    });

    test('every status has a customer label and an explanation', () {
      for (final s in OverseasStatus.all) {
        expect(OverseasStatus.label(s), isNotEmpty, reason: s);
        expect(OverseasStatus.explain(s), isNotEmpty, reason: s);
        // The raw slug never reaches a customer.
        expect(OverseasStatus.label(s), isNot(equals(s)), reason: s);
      }
    });
  });

  group('isPlausibleEmail', () {
    test('accepts ordinary addresses', () {
      for (final email in [
        'a@b.co',
        'marcia.brown@gmail.com',
        'marcia+shipeast@gmail.com',
        'MARCIA@EXAMPLE.COM',
        'user_name@sub.domain.org',
        "o'brien@example.com",
      ]) {
        expect(isPlausibleEmail(email), isTrue, reason: email);
      }
    });

    test('rejects addresses that cannot receive mail', () {
      for (final email in [
        '',
        '   ',
        'marcia',
        'marcia@',
        '@example.com',
        'marcia@example',
        'a@b@c.com',
        'marcia example@mail.com',
      ]) {
        expect(isPlausibleEmail(email), isFalse, reason: '"$email"');
      }
    });

    test('trims before judging, and rejects an over-long address', () {
      expect(isPlausibleEmail('  me@example.com  '), isTrue);
      // firestore.rules caps the field at 320 characters; failing here means
      // the customer is told, rather than watching the write fail.
      expect(isPlausibleEmail('${'x' * 320}@example.com'), isFalse);
    });
  });

  group('isPlausiblePhone', () {
    test('ignores the formatting people actually type', () {
      expect(isPlausiblePhone('876-555-0110'), isTrue);
      expect(isPlausiblePhone('(876) 555 0110'), isTrue);
      expect(isPlausiblePhone('+1 718 555 0134'), isTrue);
    });

    test('rejects what nobody can be called on', () {
      expect(isPlausiblePhone(''), isFalse);
      expect(isPlausiblePhone('call me'), isFalse);
      expect(isPlausiblePhone('12345'), isFalse);
      expect(isPlausiblePhone('1' * 16), isFalse);
    });
  });

  group('OverseasInquiryDraft.errors', () {
    test('a complete draft submits', () {
      expect(valid().errors(), isEmpty);
      expect(valid().isValid, isTrue);
    });

    test('every contact field an operator needs is required', () {
      expect(valid(contactEmail: 'nope').errors(), contains('contactEmail'));
      expect(valid(contactPhone: '').errors(), contains('contactPhone'));
      expect(valid(originCountry: '  ').errors(), contains('originCountry'));
    });

    test('the delivery end must be reachable', () {
      expect(valid(recipientName: '').errors(), contains('recipientName'));
      expect(valid(recipientPhone: 'ask him').errors(), contains('recipientPhone'));
      // A town name alone is not somewhere a courier can knock.
      expect(valid(recipientAddress: 'Kingston').errors(),
          contains('recipientAddress'));
      expect(valid(recipientAddress: 'Morant Bay').errors(),
          contains('recipientAddress'));
    });

    test('accepts a rural address with no house number', () {
      // Plenty of Jamaican addresses have none. Requiring a digit would reject
      // a real one, which is the more expensive of the two mistakes.
      expect(valid(recipientAddress: 'Top Road, Cedar Valley').errors(), isEmpty);
    });

    test('parish and category must come from the lists, not free text', () {
      // The admin panel groups the queue by these. "St Thomas" and "st. thomas"
      // as separate destinations is how an operator misses one.
      expect(valid(recipientParish: 'St Thomas').errors(),
          contains('recipientParish'));
      expect(valid(recipientParish: '').errors(), contains('recipientParish'));
      expect(valid(itemCategory: 'Barrel').errors(), contains('itemCategory'));
    });

    test('the shopping list must actually say something', () {
      // The shopper needs to know what to pick off the shelf; "x" does not.
      expect(valid(itemDescription: 'x').errors(), contains('itemDescription'));
      expect(valid(itemDescription: '').errors(), contains('itemDescription'));
    });

    test('budget is optional free text, capped only in length', () {
      expect(valid(budgetRaw: '').errors(), isEmpty);
      expect(valid(budgetRaw: r'J$10,000').errors(), isEmpty);
      expect(valid(budgetRaw: 'up to US\$70').errors(), isEmpty);
      // Only guard is the field cap, so a paragraph pasted here is rejected.
      expect(valid(budgetRaw: 'x' * 121).errors(), contains('budgetRaw'));
    });

    test('reports every problem at once', () {
      // One error per submit turns a form into twenty round trips.
      final errors = const OverseasInquiryDraft().errors();
      expect(errors.length, greaterThan(5));
    });
  });

  group('OverseasInquiryDraft.toFirestore', () {
    test('is always created as new, attributed to the caller', () {
      final map = valid().toFirestore(customerId: 'uid-1', customerName: 'Marcia');
      expect(map['customerId'], 'uid-1');
      expect(map['customerName'], 'Marcia');
      expect(map['status'], OverseasStatus.submitted);
    });

    test('carries no admin fields', () {
      // firestore.rules rejects a create carrying these, so a client that
      // invented them would have its write fail outright. Not sending them is
      // the same rule stated on the near side.
      final map = valid().toFirestore(customerId: 'uid-1', customerName: 'M');
      for (final key in ['adminNote', 'handledBy', 'handledAt', 'quotedAmount']) {
        expect(map.containsKey(key), isFalse, reason: key);
      }
    });

    test('trims what people paste, and stores the budget as typed', () {
      final map = valid(
        contactEmail: '  marcia@example.com ',
        recipientName: ' Delroy Brown  ',
        budgetRaw: r'  J$10,000  ',
      ).toFirestore(customerId: 'uid-1', customerName: 'M');
      expect(map['contactEmail'], 'marcia@example.com');
      expect(map['recipientName'], 'Delroy Brown');
      expect(map['budget'], r'J$10,000');
    });

    test('an omitted budget is null, not an empty string', () {
      // "" would read as a blank on the panel; null reads as "spend what it
      // takes", which is what leaving it empty means.
      final map = valid().toFirestore(customerId: 'uid-1', customerName: 'M');
      expect(map['budget'], isNull);
    });

    test('SD-5: requestedStore is omitted when blank, present when given', () {
      // Omitted rather than null so firestore.rules' get(..., "").size() holds.
      final blank = valid().toFirestore(customerId: 'u', customerName: 'M');
      expect(blank.containsKey('requestedStore'), isFalse);

      final withStore = valid(requestedStore: '  PriceSmart  ')
          .toFirestore(customerId: 'u', customerName: 'M');
      expect(withStore['requestedStore'], 'PriceSmart');
    });

    test('SD-5: an over-long store preference is rejected', () {
      expect(valid(requestedStore: 'x' * 121).errors(),
          contains('requestedStore'));
    });
  });

  group('OverseasInquiry.fromMap', () {
    test('survives a document written before any of these fields existed', () {
      final inquiry = OverseasInquiry.fromMap('abc123def', const {});
      expect(inquiry.status, OverseasStatus.submitted);
      expect(inquiry.itemCategory, '—');
      // serverTimestamp() resolves after the local write, so a just-submitted
      // enquiry genuinely has no date for a moment. It must still render.
      expect(inquiry.createdAt, isNull);
    });

    test('shortens the id the way the rest of the app refers to records', () {
      expect(OverseasInquiry.fromMap('abc123def', const {}).shortId, 'ABC123');
      expect(OverseasInquiry.fromMap('ab12', const {}).shortId, 'AB12');
    });
  });
}
