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

   Note on labels: LABEL below is operator-facing and intentionally differs
   from the Dart `OrderStatus.label`, which is customer-facing. An admin wants
   the state name ("Confirmed"); a customer wants to know what is happening to
   their food ("Driver Assigned"). Same states, different audiences.        */

export const PENDING = 'pending';
export const CONFIRMED = 'confirmed';
export const PICKED_UP = 'picked_up';
export const IN_TRANSIT = 'in_transit';
export const DELIVERED = 'delivered';
export const CANCELLED = 'cancelled';

/** Every canonical status. 'accepted' is absent — no app ever wrote it. */
export const ALL = [PENDING, CONFIRMED, PICKED_UP, IN_TRANSIT, DELIVERED, CANCELLED];

/** Non-terminal: still someone's responsibility. */
export const ACTIVE = [PENDING, CONFIRMED, PICKED_UP, IN_TRANSIT];

/** States in which a driver holds the order. */
export const DRIVER_HELD = [CONFIRMED, PICKED_UP, IN_TRANSIT];

export const TERMINAL = [DELIVERED, CANCELLED];

/** Legal forward transitions. Mirrored in the Dart copies and firestore.rules. */
export const TRANSITIONS = {
  [PENDING]: [CONFIRMED, CANCELLED],
  [CONFIRMED]: [PICKED_UP, CANCELLED],
  [PICKED_UP]: [IN_TRANSIT, CANCELLED],
  [IN_TRANSIT]: [DELIVERED, CANCELLED],
  [DELIVERED]: [],
  [CANCELLED]: []
};

/** Operator-facing labels (see note above). */
export const LABEL = {
  [PENDING]: 'Pending',
  [CONFIRMED]: 'Confirmed',
  [PICKED_UP]: 'Picked Up',
  [IN_TRANSIT]: 'In Transit',
  [DELIVERED]: 'Delivered',
  [CANCELLED]: 'Cancelled'
};

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
