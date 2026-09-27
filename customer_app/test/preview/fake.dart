/// Plausible data for the screenshot instrument.
///
/// Deliberately awkward rather than tidy: a long merchant name that has to
/// ellipsize, a closed shop, a promo badge, a four-figure total. A design that
/// only survives neat data is not finished.
library;

const merchants = <Map<String, dynamic>>[
  {
    'name': 'Island Grill Morant Bay',
    'rating': '4.8',
    'deliveryTime': '25–35 min',
    'deliveryFee': 350,
    'isOpen': true,
    'promo': '20% OFF',
  },
  {
    'name': 'Juici Patties',
    'rating': '4.6',
    'deliveryTime': '15–25 min',
    'deliveryFee': 0,
    'isOpen': true,
    'promo': null,
  },
  {
    'name': 'The Blue Mountain Coffee House & Bakery',
    'rating': '4.9',
    'deliveryTime': '40–55 min',
    'deliveryFee': 500,
    'isOpen': false,
    'promo': null,
  },
];

const cartItems = <Map<String, dynamic>>[
  {'name': 'Curry Goat with Rice & Peas', 'price': 1450, 'qty': 2},
  {'name': 'Festival (2 pcs)', 'price': 300, 'qty': 1},
  {'name': 'Ting', 'price': 250, 'qty': 3},
];

const orders = <Map<String, dynamic>>[
  {
    'id': 'SE-4821',
    'merchant': 'Island Grill Morant Bay',
    'status': 'in_transit',
    'total': 3450,
    'items': 4,
    'when': 'Today, 6:42 PM',
  },
  {
    'id': 'SE-4790',
    'merchant': 'Juici Patties',
    'status': 'delivered',
    'total': 1200,
    'items': 2,
    'when': 'Yesterday, 1:15 PM',
  },
  {
    'id': 'SE-4788',
    'merchant': 'Fontana Pharmacy',
    'status': 'cancelled',
    'total': 890,
    'items': 1,
    'when': '28 Jul, 11:03 AM',
  },
];

const notifications = <Map<String, dynamic>>[
  {
    'title': 'Your order is on the way',
    'body': 'Marcus picked up your order from Island Grill and is heading over.',
    'when': '2 min ago',
    'unread': true,
    'kind': 'order',
  },
  {
    'title': 'Order delivered',
    'body': 'SE-4790 was delivered. Tap to rate your driver.',
    'when': 'Yesterday',
    'unread': false,
    'kind': 'delivered',
  },
  {
    'title': '20% off at Island Grill',
    'body': 'This weekend only, on orders over J\$2,000.',
    'when': '3 days ago',
    'unread': false,
    'kind': 'promo',
  },
];
