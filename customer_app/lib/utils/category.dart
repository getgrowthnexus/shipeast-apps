/// Merchant category: the value stored on `merchants/{id}.category` versus the
/// word a customer reads.
///
/// The stored values are shared with the admin panel's merchant form and are
/// what every category query matches on, so they do not change when the copy
/// does. The client asked for "Groceries" on screen (checklist, Sep 2026);
/// renaming the stored "Grocery" would have emptied that category for every
/// existing merchant.
library;

class MerchantCategory {
  MerchantCategory._();

  /// The on-screen label for a stored category value.
  static String label(String stored) => switch (stored) {
        'Grocery' => 'Groceries',
        _ => stored,
      };
}
