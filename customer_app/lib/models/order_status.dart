/// Canonical order lifecycle. Source of truth: SCHEMA.md §orders.status
///
/// This file is duplicated in customer_app and driver_app and verified
/// byte-identical by CI (.github/workflows/verify.yml). Edit both, or neither.
///
/// The duplication is deliberate and temporary. These are two separate apps
/// with no shared package today; extracting `packages/shipeast_core` is
/// scheduled as P6-04, and doing it now would couple a risky refactor to an
/// urgent correctness fix.
///
/// Before this existed, status strings were literals scattered across a dozen
/// files, and the three apps disagreed about what they meant: the customer app
/// read 'accepted' and 'in_transit' (which nothing wrote), the driver wrote
/// 'confirmed' and 'picked_up' (which the customer did not understand), and
/// the admin panel offered all seven unvalidated. An order in 'confirmed' or
/// 'picked_up' therefore matched no customer history tab and vanished from the
/// customer's order list for the entire delivery.
library;

abstract final class OrderStatus {
  /// Order placed; no driver has claimed it.
  static const pending = 'pending';

  /// A driver has claimed it and is en route to the merchant.
  static const confirmed = 'confirmed';

  /// The driver has the goods.
  static const pickedUp = 'picked_up';

  /// The driver is en route to the customer.
  static const inTransit = 'in_transit';

  /// Terminal, success.
  static const delivered = 'delivered';

  /// Terminal, failure.
  static const cancelled = 'cancelled';

  /// Every canonical status. Note 'accepted' is absent: it was offered by the
  /// admin dropdown but never written by any app, and is removed entirely.
  static const all = [pending, confirmed, pickedUp, inTransit, delivered, cancelled];

  /// Non-terminal states: an order here is still someone's responsibility.
  /// Drives the customer's "Active" history tab.
  static const active = [pending, confirmed, pickedUp, inTransit];

  /// States in which a driver holds the order.
  ///
  /// The driver's active-order query filters on exactly this set. It previously
  /// listed only [confirmed] and [pickedUp], so an admin moving an order to
  /// in_transit stripped the driver of their live delivery mid-route.
  static const driverHeld = [confirmed, pickedUp, inTransit];

  static const terminal = [delivered, cancelled];

  /// Legal forward transitions. Mirrored in firestore.rules (P2-01) and in the
  /// admin panel's dropdown (P1-06). All three must agree.
  static const transitions = <String, List<String>>{
    pending: [confirmed, cancelled],
    confirmed: [pickedUp, cancelled],
    pickedUp: [inTransit, cancelled],
    inTransit: [delivered, cancelled],
    delivered: [],
    cancelled: [],
  };

  /// Whether [from] → [to] is a legal transition.
  ///
  /// Unknown statuses and terminal states return false, so a corrupt or legacy
  /// value cannot be advanced rather than being treated as [pending].
  static bool canTransition(String from, String to) =>
      transitions[from]?.contains(to) ?? false;

  /// Whether [s] is one of the canonical statuses.
  static bool isValid(String s) => all.contains(s);

  /// Whether an order in [s] still needs someone to act on it.
  static bool isActive(String s) => active.contains(s);

  /// Whether a driver currently holds an order in [s].
  static bool isDriverHeld(String s) => driverHeld.contains(s);

  static bool isTerminal(String s) => terminal.contains(s);

  /// Customer-facing label. Never show a raw status string in UI — that is how
  /// the literal text "picked_up" reached the customer's order list.
  static String label(String s) => switch (s) {
        pending => 'Order Placed',
        confirmed => 'Driver Assigned',
        pickedUp => 'Order Picked Up',
        inTransit => 'On the Way',
        delivered => 'Delivered',
        cancelled => 'Cancelled',
        _ => 'Processing',
      };

  /// Zero-based index into the 5-step customer tracker.
  ///
  /// Returns -1 for [cancelled], which is not a step on the happy path and must
  /// be rendered as its own terminal state. Callers must handle -1 explicitly:
  /// feeding it to a progress fraction throws.
  static int step(String s) => switch (s) {
        pending => 0,
        confirmed => 1,
        pickedUp => 2,
        inTransit => 3,
        delivered => 4,
        cancelled => -1,
        _ => 0,
      };

  /// Number of steps in the customer tracker.
  static const stepCount = 5;
}
