/**
 * Canonical order lifecycle — functions copy.
 * Source of truth: SCHEMA.md §orders.status
 *
 * Mirrors customer_app/lib/models/order_status.dart,
 * driver_app/lib/models/order_status.dart, and admin_panel/order-status.js.
 * Verified against them by tools/check-status-parity.mjs in CI.
 *
 * Edit all four, or none.
 */

export const PENDING = 'pending';
export const CONFIRMED = 'confirmed';
export const PICKED_UP = 'picked_up';
export const IN_TRANSIT = 'in_transit';
export const DELIVERED = 'delivered';
export const CANCELLED = 'cancelled';

export type OrderStatusValue =
  | typeof PENDING
  | typeof CONFIRMED
  | typeof PICKED_UP
  | typeof IN_TRANSIT
  | typeof DELIVERED
  | typeof CANCELLED;

/** Every canonical status. 'accepted' is absent — no app ever wrote it. */
export const ALL: readonly string[] = [
  PENDING, CONFIRMED, PICKED_UP, IN_TRANSIT, DELIVERED, CANCELLED
];

/** Non-terminal: still someone's responsibility. */
export const ACTIVE: readonly string[] = [PENDING, CONFIRMED, PICKED_UP, IN_TRANSIT];

/** States in which a driver holds the order. */
export const DRIVER_HELD: readonly string[] = [CONFIRMED, PICKED_UP, IN_TRANSIT];

export const TERMINAL: readonly string[] = [DELIVERED, CANCELLED];

/** Legal forward transitions. Mirrored in firestore.rules. */
export const TRANSITIONS: Readonly<Record<string, readonly string[]>> = {
  [PENDING]: [CONFIRMED, CANCELLED],
  [CONFIRMED]: [PICKED_UP, CANCELLED],
  [PICKED_UP]: [IN_TRANSIT, CANCELLED],
  [IN_TRANSIT]: [DELIVERED, CANCELLED],
  [DELIVERED]: [],
  [CANCELLED]: []
};

/** Customer-facing label. Never surface a raw status string. */
export const LABEL: Readonly<Record<string, string>> = {
  [PENDING]: 'Order Placed',
  [CONFIRMED]: 'Driver Assigned',
  [PICKED_UP]: 'Order Picked Up',
  [IN_TRANSIT]: 'On the Way',
  [DELIVERED]: 'Delivered',
  [CANCELLED]: 'Cancelled'
};

export function isValid(s: string): boolean {
  return ALL.includes(s);
}

export function canTransition(from: string, to: string): boolean {
  return (TRANSITIONS[from] ?? []).includes(to);
}

export function isDriverHeld(s: string): boolean {
  return DRIVER_HELD.includes(s);
}

export function isTerminal(s: string): boolean {
  return TERMINAL.includes(s);
}

export function label(s: string): string {
  return LABEL[s] ?? 'Processing';
}
