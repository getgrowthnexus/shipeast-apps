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
///
/// Client checklist (admin round, Sep 2026): "Pending" is split into the
/// client's stages, and every app shows the same label for each:
///
///   Order Placed → Awaiting Merchant → Preparing → Awaiting Driver →
///   Driver Assigned → Picked Up → Out for Delivery → Delivered
///   (or Cancelled / Failed Delivery)
///
/// The stored values of the original six are unchanged — `pending` reads
/// "Order Placed", `confirmed` "Driver Assigned", `in_transit` "Out for
/// Delivery" — so no existing order needs migrating. Orders with no kitchen
/// stage (packages) skip Awaiting Merchant / Preparing. The admin moves orders
/// through the merchant stages by hand until a merchant portal exists; a
/// driver may still claim an order early (see [claimable]) so nothing stalls.
library;

abstract final class OrderStatus {
  /// Order placed; nobody has acted on it yet.
  static const pending = 'pending';

  /// Waiting for the merchant to accept / confirm the order.
  static const awaitingMerchant = 'awaiting_merchant';

  /// The merchant (or a ShipEast shopper) is preparing it.
  static const preparing = 'preparing';

  /// Ready, or needs no preparation, and waiting for a driver.
  static const awaitingDriver = 'awaiting_driver';

  /// A driver has claimed it (or was assigned) and is heading to pick up.
  static const confirmed = 'confirmed';

  /// The driver has the goods.
  static const pickedUp = 'picked_up';

  /// The driver is en route to the customer ("Out for Delivery").
  static const inTransit = 'in_transit';

  /// Terminal, success.
  static const delivered = 'delivered';

  /// Terminal, failure.
  static const cancelled = 'cancelled';

  /// Terminal: the delivery could not be completed.
  static const failedDelivery = 'failed_delivery';

  /// Every canonical status. Note 'accepted' is absent: it was offered by the
  /// admin dropdown but never written by any app, and is removed entirely.
  static const all = [
    pending, awaitingMerchant, preparing, awaitingDriver,
    confirmed, pickedUp, inTransit, delivered, cancelled, failedDelivery,
  ];

  /// Before a driver has it. The admin's broad "Pending" filter.
  static const preDriver = [pending, awaitingMerchant, preparing, awaitingDriver];

  /// States a driver may claim an order from (offer list). Early claims are
  /// allowed on purpose: the kitchen stages are moved by hand for now, and a
  /// forgotten "ready" must not leave food with no driver.
  static const claimable = preDriver;

  /// Non-terminal states: an order here is still someone's responsibility.
  /// Drives the customer's "Active" history tab.
  static const active = [
    pending, awaitingMerchant, preparing, awaitingDriver,
    confirmed, pickedUp, inTransit,
  ];

  /// States in which a driver holds the order.
  ///
  /// The driver's active-order query filters on exactly this set. It previously
  /// listed only [confirmed] and [pickedUp], so an admin moving an order to
  /// in_transit stripped the driver of their live delivery mid-route.
  static const driverHeld = [confirmed, pickedUp, inTransit];

  static const terminal = [delivered, cancelled, failedDelivery];

  /// Legal forward transitions. Mirrored in firestore.rules (P2-01) and in the
  /// admin panel's dropdown (P1-06). All three must agree.
  static const transitions = <String, List<String>>{
    pending: [awaitingMerchant, preparing, awaitingDriver, confirmed, cancelled],
    awaitingMerchant: [preparing, awaitingDriver, confirmed, cancelled],
    preparing: [awaitingDriver, confirmed, cancelled],
    awaitingDriver: [confirmed, cancelled],
    confirmed: [pickedUp, cancelled],
    pickedUp: [inTransit, failedDelivery, cancelled],
    inTransit: [delivered, failedDelivery, cancelled],
    delivered: [],
    cancelled: [],
    failedDelivery: [],
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

  /// Whether a driver may claim an unassigned order in [s].
  static bool isClaimable(String s) => claimable.contains(s);

  static bool isTerminal(String s) => terminal.contains(s);

  /// The one label every app shows (client checklist: the customer app, the
  /// driver app and the admin panel must read the same). Never show a raw
  /// status string in UI — that is how "picked_up" reached a customer.
  static String label(String s) => switch (s) {
        pending => 'Order Placed',
        awaitingMerchant => 'Awaiting Merchant',
        preparing => 'Preparing',
        awaitingDriver => 'Awaiting Driver',
        confirmed => 'Driver Assigned',
        pickedUp => 'Picked Up',
        inTransit => 'Out for Delivery',
        delivered => 'Delivered',
        cancelled => 'Cancelled',
        failedDelivery => 'Failed Delivery',
        _ => 'Processing',
      };

  /// Zero-based index into the 6-step customer tracker:
  /// Order Placed · Preparing · Driver Assigned · Picked Up ·
  /// Out for Delivery · Delivered.
  ///
  /// Awaiting Merchant is still step 0 (placed, not started); Awaiting Driver
  /// is step 1 done (the food is ready). Returns -1 for [cancelled] and
  /// [failedDelivery], which are not steps on the happy path and must be
  /// rendered as their own terminal state. Callers must handle -1 explicitly:
  /// feeding it to a progress fraction throws.
  static int step(String s) => switch (s) {
        pending => 0,
        awaitingMerchant => 0,
        preparing => 1,
        awaitingDriver => 1,
        confirmed => 2,
        pickedUp => 3,
        inTransit => 4,
        delivered => 5,
        cancelled => -1,
        failedDelivery => -1,
        _ => 0,
      };

  /// Titles of the tracker steps, in [step] order.
  static const stepTitles = [
    'Order Placed', 'Preparing', 'Driver Assigned',
    'Picked Up', 'Out for Delivery', 'Delivered',
  ];

  /// Number of steps in the customer tracker.
  static const stepCount = 6;
}
