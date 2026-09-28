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
export const AWAITING_MERCHANT = 'awaiting_merchant';
export const PREPARING = 'preparing';
export const AWAITING_DRIVER = 'awaiting_driver';
export const CONFIRMED = 'confirmed';
export const PICKED_UP = 'picked_up';
export const IN_TRANSIT = 'in_transit';
export const DELIVERED = 'delivered';
export const CANCELLED = 'cancelled';
export const FAILED_DELIVERY = 'failed_delivery';

export type OrderStatusValue =
  | typeof PENDING
  | typeof AWAITING_MERCHANT
  | typeof PREPARING
  | typeof AWAITING_DRIVER
  | typeof CONFIRMED
  | typeof PICKED_UP
  | typeof IN_TRANSIT
  | typeof DELIVERED
  | typeof CANCELLED
  | typeof FAILED_DELIVERY;

/** Every canonical status. 'accepted' is absent — no app ever wrote it. */
export const ALL: readonly string[] = [
  PENDING, AWAITING_MERCHANT, PREPARING, AWAITING_DRIVER,
  CONFIRMED, PICKED_UP, IN_TRANSIT, DELIVERED, CANCELLED, FAILED_DELIVERY
];

/** Non-terminal: still someone's responsibility. */
export const ACTIVE: readonly string[] = [
  PENDING, AWAITING_MERCHANT, PREPARING, AWAITING_DRIVER,
  CONFIRMED, PICKED_UP, IN_TRANSIT
];

/** States in which a driver holds the order. */
export const DRIVER_HELD: readonly string[] = [CONFIRMED, PICKED_UP, IN_TRANSIT];

export const TERMINAL: readonly string[] = [DELIVERED, CANCELLED, FAILED_DELIVERY];

/** Legal forward transitions. Mirrored in firestore.rules. */
export const TRANSITIONS: Readonly<Record<string, readonly string[]>> = {
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

/** Customer-facing label. Never surface a raw status string. */
export const LABEL: Readonly<Record<string, string>> = {
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
