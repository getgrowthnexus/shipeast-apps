/* ═══════════════════════════════════════════════════════════════
   Canonical order lifecycle — admin panel copy.
   Source of truth: SCHEMA.md §orders.status
   ═══════════════════════════════════════════════════════════════

   Mirrors customer_app/lib/models/order_status.dart and
   driver_app/lib/models/order_status.dart. Those two are verified
   byte-identical by CI; this one cannot be (different language), so it is
   verified against them structurally by tools/check-status-parity.mjs, which
   parses the Dart transition table and compares it to the one below.

   Edit all three, or none.

   Labels: the client asked for one set of words in all three apps (admin
   round, Sep 2026), so LABEL below matches the Dart `OrderStatus.label`.
   "Pending" survives only as the panel's broad filter for PRE_DRIVER.

     Order Placed → Awaiting Merchant → Preparing → Awaiting Driver →
     Driver Assigned → Picked Up → Out for Delivery → Delivered
     (or Cancelled / Failed Delivery)                                      */

export const PENDING = 'pending';
export const AWAITING_MERCHANT = 'awaiting_merchant';
export const PREPARING = 'preparing';
export const AWAITING_DRIVER = 'awaiting_driver';
export const CONFIRMED = 'confirmed';
export const PICKED_UP = 'picked_up';
export const IN_TRANSIT = 'in_transit';
export const DELIVERED = 'delivered';
export const CANCELLED = 'cancelled';
export const FAILED_DELIVERY = 'failed_delivery';

/** Every canonical status. 'accepted' is absent — no app ever wrote it. */
export const ALL = [PENDING, AWAITING_MERCHANT, PREPARING, AWAITING_DRIVER,
  CONFIRMED, PICKED_UP, IN_TRANSIT, DELIVERED, CANCELLED, FAILED_DELIVERY];

/** Before a driver has it — the panel's broad "Pending" filter. */
export const PRE_DRIVER = [PENDING, AWAITING_MERCHANT, PREPARING, AWAITING_DRIVER];

/** A driver (or the admin) may assign a driver from any of these. */
export const CLAIMABLE = PRE_DRIVER;

/** Non-terminal: still someone's responsibility. */
export const ACTIVE = [PENDING, AWAITING_MERCHANT, PREPARING, AWAITING_DRIVER,
  CONFIRMED, PICKED_UP, IN_TRANSIT];

/** States in which a driver holds the order. */
export const DRIVER_HELD = [CONFIRMED, PICKED_UP, IN_TRANSIT];

export const TERMINAL = [DELIVERED, CANCELLED, FAILED_DELIVERY];

/** Legal forward transitions. Mirrored in the Dart copies and firestore.rules. */
export const TRANSITIONS = {
  [PENDING]: [AWAITING_MERCHANT, PREPARING, AWAITING_DRIVER, CONFIRMED, CANCELLED],
  [AWAITING_MERCHANT]: [PREPARING, AWAITING_DRIVER, CONFIRMED, CANCELLED],
  [PREPARING]: [AWAITING_DRIVER, CONFIRMED, CANCELLED],
  [AWAITING_DRIVER]: [CONFIRMED, CANCELLED],
  [CONFIRMED]: [PICKED_UP, CANCELLED],
  [PICKED_UP]: [IN_TRANSIT, FAILED_DELIVERY, CANCELLED],
  [IN_TRANSIT]: [DELIVERED, FAILED_DELIVERY, CANCELLED],
  [DELIVERED]: [],
  [CANCELLED]: [],
  [FAILED_DELIVERY]: []
};

/** The one set of labels all three apps show (see note above). */
export const LABEL = {
  [PENDING]: 'Order Placed',
  [AWAITING_MERCHANT]: 'Awaiting Merchant',
  [PREPARING]: 'Preparing',
  [AWAITING_DRIVER]: 'Awaiting Driver',
  [CONFIRMED]: 'Driver Assigned',
  [PICKED_UP]: 'Picked Up',
  [IN_TRANSIT]: 'Out for Delivery',
  [DELIVERED]: 'Delivered',
  [CANCELLED]: 'Cancelled',
  [FAILED_DELIVERY]: 'Failed Delivery'
};

export function isPreDriver(s) {
  return PRE_DRIVER.indexOf(s) !== -1;
}

export function isValid(s) {
  return ALL.indexOf(s) !== -1;
}

export function canTransition(from, to) {
  const next = TRANSITIONS[from];
  return !!next && next.indexOf(to) !== -1;
}

export function isDriverHeld(s) {
  return DRIVER_HELD.indexOf(s) !== -1;
}

export function isTerminal(s) {
  return TERMINAL.indexOf(s) !== -1;
}

/** The statuses an admin may select for an order currently in [current].
 *
 *  The current status is included so the dropdown can render it as selected
 *  without offering an illegal move. Previously the dropdown offered all seven
 *  statuses unconditionally — including 'accepted', which nothing understood,
 *  and 'in_transit', which silently stripped the assigned driver of a live
 *  delivery because it fell outside their active-order query.               */
export function selectableFrom(current) {
  // A legacy or corrupt status (e.g. the retired 'accepted') is still listed
  // first so the dropdown reflects reality, but it offers no successors —
  // there is no legal move out of a state the lifecycle does not define, and
  // guessing one is how bad data spreads.
  return [current].concat(TRANSITIONS[current] || []);
}
