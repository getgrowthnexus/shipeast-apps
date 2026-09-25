/// Shop-and-deliver requests — the vocabulary shared by the customer app and
/// the admin panel.
///
/// ## What this service actually is
///
/// ShipEast is not a courier and nothing is shipped across a border. A person
/// living abroad asks us to shop for their family **inside Jamaica**: we go to
/// a local supermarket or hardware store, buy what they asked for, and deliver
/// it to their relative's door. No carrier, no customs, no freight — a local
/// errand paid for from overseas.
///
/// ## Why it is a request and not an order
///
/// The total depends on which store we use and what the goods cost on the day,
/// so nothing here can quote a price up front, and a screen that took payment
/// for one would be making a promise the business cannot keep. What it *can*
/// honestly do is take a complete, structured request and put it in front of a
/// human who confirms the total and replies. That is what this is: a request
/// for a quote, with a status the admin moves and the customer can see. The
/// customer is told a person will come back to them, and now a person actually
/// can, because the request lands somewhere with a queue behind it.
///
/// Mirrored by `admin_panel/overseas-status.js`. Edit both, or neither.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a request is in the handling process. Only an admin moves it.
///
/// Client checklist SD-1 / SD-4 / SD-5: the nine-stage pipeline the client
/// specified, plus three outcomes. Mirrors `admin_panel/overseas-status.js` —
/// the slugs and the sets must match; only the *wording* differs (this side is
/// customer-facing, that side is operator-facing).
class OverseasStatus {
  OverseasStatus._();

  static const String submitted = 'new'; // kept as the name the draft writes
  static const String reviewing = 'reviewing';
  static const String quoteSent = 'quote_sent';
  static const String awaitingCustomer = 'awaiting_customer';
  static const String approved = 'approved';
  static const String shopping = 'shopping';
  static const String readyForDelivery = 'ready_for_delivery';
  static const String outForDelivery = 'out_for_delivery';
  static const String completed = 'completed';
  static const String declined = 'declined';
  static const String cancelled = 'cancelled';
  static const String expired = 'expired';

  /// The linear handling pipeline, in order. `completed` is its successful end.
  static const List<String> pipeline = <String>[
    submitted,
    reviewing,
    quoteSent,
    awaitingCustomer,
    approved,
    shopping,
    readyForDelivery,
    outForDelivery,
    completed,
  ];

  static const List<String> outcomes = <String>[declined, cancelled, expired];

  static const List<String> all = <String>[
    submitted,
    reviewing,
    quoteSent,
    awaitingCustomer,
    approved,
    shopping,
    readyForDelivery,
    outForDelivery,
    completed,
    declined,
    cancelled,
    expired,
  ];

  /// Still somebody's responsibility.
  static const List<String> open = <String>[
    submitted,
    reviewing,
    quoteSent,
    awaitingCustomer,
    approved,
    shopping,
    readyForDelivery,
    outForDelivery,
  ];

  /// SD-1: every terminal state, not just `declined`.
  static const List<String> terminal = <String>[
    completed,
    declined,
    cancelled,
    expired,
  ];

  /// The pre-SD-4 vocabulary. Un-migrated documents map onto the nearest new
  /// state so a customer's request still reads sensibly before the migration.
  static const Map<String, String> _legacy = <String, String>{
    'contacted': reviewing,
    'quoted': quoteSent,
    'closed': completed,
  };

  /// Never lets an unrecognised value through to the UI as a raw slug.
  /// A request with no status is one that was just written — `new`.
  static String of(Object? raw) {
    if (raw is String) {
      if (all.contains(raw)) return raw;
      final mapped = _legacy[raw];
      if (mapped != null) return mapped;
    }
    return submitted;
  }

  static bool isOpen(Object? raw) => open.contains(of(raw));
  static bool isTerminal(Object? raw) => terminal.contains(of(raw));

  /// True for a terminal state that is NOT a successful completion — the
  /// customer's list tints these as "did not happen".
  static bool isUnsuccessful(Object? raw) {
    final s = of(raw);
    return s == declined || s == cancelled || s == expired;
  }

  /// Customer-facing wording. Deliberately different from the admin panel's
  /// labels: an operator wants the state name, a customer wants to know what
  /// is happening to their request.
  static String label(Object? raw) {
    switch (of(raw)) {
      case reviewing:
        return 'Under review';
      case quoteSent:
        return 'Quote sent';
      case awaitingCustomer:
        return 'Waiting for your reply';
      case approved:
        return 'Approved';
      case shopping:
        return 'Shopping now';
      case readyForDelivery:
        return 'Ready for delivery';
      case outForDelivery:
        return 'Out for delivery';
      case completed:
        return 'Delivered';
      case declined:
        return 'Not possible';
      case cancelled:
        return 'Cancelled';
      case expired:
        return 'Expired';
      default:
        return 'Received';
    }
  }

  /// One line telling the customer what happens next. A bare status word
  /// leaves them guessing whether they are waiting on us or we on them.
  static String explain(Object? raw) {
    switch (of(raw)) {
      case reviewing:
        return 'Someone from ShipEast is looking at your request.';
      case quoteSent:
        return 'We’ve emailed you the total. Reply to that message to go ahead.';
      case awaitingCustomer:
        return 'We’re holding your request until you confirm the total by email.';
      case approved:
        return 'You’ve confirmed the total — we’ll start shopping shortly.';
      case shopping:
        return 'We’re picking up your items now.';
      case readyForDelivery:
        return 'Your items are packed and waiting for a driver.';
      case outForDelivery:
        return 'A driver is on the way to your family.';
      case completed:
        return 'Delivered. Thank you for using ShipEast.';
      case declined:
        return 'We couldn’t take this one on. Check your email for the reason.';
      case cancelled:
        return 'This request was cancelled.';
      case expired:
        return 'This request expired before it was confirmed. Start a new one if you still need it.';
      default:
        return 'We have your request and will get back to you with the total.';
    }
  }
}

/// The kinds of thing people ask us to buy locally. `other` exists because the
/// list is a shortcut, not a gate — a request we cannot categorise is still a
/// request we want.
class OverseasItemCategory {
  OverseasItemCategory._();

  static const List<String> all = <String>[
    'Groceries & food',
    'Household & cleaning',
    'Hardware & building',
    'Baby & childcare',
    'Pharmacy & health',
    'Electronics',
    'Gifts',
    'Other',
  ];
}

/// The 14 parishes of Jamaica. A free-text destination is the difference
/// between a request an operator can route and one they have to phone about.
class JamaicaParish {
  JamaicaParish._();

  static const List<String> all = <String>[
    'Kingston',
    'St. Andrew',
    'St. Thomas',
    'Portland',
    'St. Mary',
    'St. Ann',
    'Trelawny',
    'St. James',
    'Hanover',
    'Westmoreland',
    'St. Elizabeth',
    'Manchester',
    'Clarendon',
    'St. Catherine',
  ];
}

/// Field length caps. Mirrored in firestore.rules — a client that skips the
/// form cannot write a megabyte of prose into the collection.
class OverseasLimits {
  OverseasLimits._();

  static const int shortField = 120;
  static const int address = 400;
  static const int description = 1000;
  static const int notes = 1000;
  static const int email = 320;
}

/// Accepts anything with a local part, an `@`, a dot-bearing domain and no
/// whitespace. Deliberately permissive: an over-strict pattern's only
/// achievement is rejecting a real customer's real address.
bool isPlausibleEmail(String input) {
  final value = input.trim();
  if (value.isEmpty || value.length > OverseasLimits.email) return false;
  if (value.contains(RegExp(r'\s'))) return false;
  return RegExp(r'^[^@]+@[^@]+\.[^@.]+$').hasMatch(value);
}

/// Digits only, ignoring the formatting people type. Seven is the shortest
/// real Jamaican number; the upper bound leaves room for any country code.
bool isPlausiblePhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 7 && digits.length <= 15;
}

/// A filled-in form, before it becomes a document.
///
/// Kept separate from the widget so validation is a pure function with a test
/// suite rather than a pile of `if` statements inside a build method.
class OverseasInquiryDraft {
  final String contactEmail;
  final String contactPhone;
  final String originCountry;
  final String recipientName;
  final String recipientPhone;
  final String recipientAddress;
  final String recipientParish;
  final String itemCategory;
  final String itemDescription;

  /// Where the customer would like us to shop — "PriceSmart", "any supermarket",
  /// "the pharmacy on Constant Spring Road". Optional and free text (SD-5): it
  /// is a preference for the shopper, not a routing key.
  final String requestedStore;

  /// What the customer is happy to spend, in their own words — "J$10,000",
  /// "US$70", "up to 15k". Free text on purpose: the number is only a
  /// guideline for the shopper, and forcing a single currency on a customer
  /// abroad paying for goods priced locally would reject more than it helps.
  final String budgetRaw;
  final String notes;

  const OverseasInquiryDraft({
    this.contactEmail = '',
    this.contactPhone = '',
    this.originCountry = '',
    this.recipientName = '',
    this.recipientPhone = '',
    this.recipientAddress = '',
    this.recipientParish = '',
    this.itemCategory = '',
    this.itemDescription = '',
    this.requestedStore = '',
    this.budgetRaw = '',
    this.notes = '',
  });

  /// Field key → message, empty when the draft can be submitted.
  ///
  /// Every required field here is one an operator needs before they can pick
  /// up the phone. Nothing is required for tidiness.
  Map<String, String> errors() {
    final e = <String, String>{};

    if (!isPlausibleEmail(contactEmail)) {
      e['contactEmail'] = 'Enter an email address we can reach you at';
    }
    if (!isPlausiblePhone(contactPhone)) {
      e['contactPhone'] = 'Enter a phone number, including the country code';
    }
    if (originCountry.trim().isEmpty) {
      e['originCountry'] = 'Where are you based?';
    }
    if (recipientName.trim().isEmpty) {
      e['recipientName'] = 'Who is receiving this in Jamaica?';
    }
    if (!isPlausiblePhone(recipientPhone)) {
      e['recipientPhone'] = 'A number for the person receiving it';
    }
    // A town alone — "Kingston", "Morant Bay" — is not somewhere a courier can
    // knock. An address names at least two things, so it carries either a
    // number or a comma between street and town. Requiring a number alone
    // would reject the many rural Jamaican addresses that have none, which is
    // the more expensive of the two mistakes; hence either, not both.
    final address = recipientAddress.trim();
    if (address.length < 10 || !address.contains(RegExp(r'[0-9,]'))) {
      e['recipientAddress'] = 'Street and town, e.g. “Top Road, Cedar Valley”';
    }
    if (!JamaicaParish.all.contains(recipientParish)) {
      e['recipientParish'] = 'Choose the parish';
    }
    if (!OverseasItemCategory.all.contains(itemCategory)) {
      e['itemCategory'] = 'Choose what you are buying';
    }
    if (itemDescription.trim().length < 3) {
      // The shopper needs to know exactly what to pick off the shelf.
      e['itemDescription'] = 'List what you’d like us to buy';
    }

    if (itemDescription.trim().length > OverseasLimits.description) {
      e['itemDescription'] = 'Please shorten this a little';
    }
    if (requestedStore.trim().length > OverseasLimits.shortField) {
      e['requestedStore'] = 'Please shorten this a little';
    }
    if (budgetRaw.trim().length > OverseasLimits.shortField) {
      e['budgetRaw'] = 'Please shorten this a little';
    }
    if (notes.trim().length > OverseasLimits.notes) {
      e['notes'] = 'Please shorten this a little';
    }

    return e;
  }

  bool get isValid => errors().isEmpty;

  /// The document body. Admin-only fields (`adminNote`, `handledBy`,
  /// `handledAt`) are absent on purpose: firestore.rules rejects a create that
  /// carries them, so a modified client cannot file a request that already
  /// claims to have been handled.
  Map<String, dynamic> toFirestore({
    required String customerId,
    required String customerName,
  }) {
    final budget = budgetRaw.trim();
    final store = requestedStore.trim();
    return <String, dynamic>{
      'customerId': customerId,
      'customerName': customerName,
      'contactEmail': contactEmail.trim(),
      'contactPhone': contactPhone.trim(),
      'originCountry': originCountry.trim(),
      'recipientName': recipientName.trim(),
      'recipientPhone': recipientPhone.trim(),
      'recipientAddress': recipientAddress.trim(),
      'recipientParish': recipientParish,
      'itemCategory': itemCategory,
      'itemDescription': itemDescription.trim(),
      // Omitted entirely when the customer has no preference — the panel then
      // shows "Any store". firestore.rules size-checks it via get(..., '').
      if (store.isNotEmpty) 'requestedStore': store,
      // Null, not '' — an omitted budget is "spend what it takes", which the
      // panel shows as "—" rather than an empty string that reads as a blank.
      'budget': budget.isEmpty ? null : budget,
      'notes': notes.trim(),
      'status': OverseasStatus.submitted,
    };
  }
}

/// A request read back from Firestore, for the customer's own list.
class OverseasInquiry {
  final String id;
  final String status;
  final String itemCategory;
  final String recipientName;
  final String recipientParish;
  final DateTime? createdAt;

  const OverseasInquiry({
    required this.id,
    required this.status,
    required this.itemCategory,
    required this.recipientName,
    required this.recipientParish,
    required this.createdAt,
  });

  factory OverseasInquiry.fromMap(String id, Map<String, dynamic> data) {
    final created = data['createdAt'];
    return OverseasInquiry(
      id: id,
      status: OverseasStatus.of(data['status']),
      itemCategory: (data['itemCategory'] as String?) ?? '—',
      recipientName: (data['recipientName'] as String?) ?? '—',
      recipientParish: (data['recipientParish'] as String?) ?? '',
      // serverTimestamp() resolves after the local write, so a just-submitted
      // request legitimately has no date for a moment.
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }

  /// Short human handle, matching how orders are referred to elsewhere.
  String get shortId =>
      id.length <= 6 ? id.toUpperCase() : id.substring(0, 6).toUpperCase();
}
