/* Promo code evaluation (P3-03).
 *
 * This is the AUTHORITATIVE discount calculation. The customer app has a copy
 * for instant checkout feedback, but that copy is never trusted: the order's
 * discount comes from `redeemPromo`, which calls this.
 *
 * Every rule here exists because it was absent. Before P3-03 every promo code
 * discounted exactly J$0 (the customer read `discount`, the admin wrote
 * `discountAmount`), never expired (the admin wrote `validUntil` as a string,
 * the customer read `expiresAt` as a Timestamp), and ignored its usage cap
 * (`usedCount` was never incremented).
 *
 * Deliberately pure: no firebase-admin import, so it is testable without a
 * database or credentials. `promo.test.ts` is that test.
 */

/** The canonical stored shape (SCHEMA.md `promoCodes/{CODE}`). */
export interface PromoDoc {
  code: string;
  discountType: 'percent' | 'fixed';
  discountAmount: number;
  minOrderTotal: number;
  /** Caps a percentage discount. `null` means uncapped. */
  maxDiscount: number | null;
  /** Milliseconds since epoch, or `null` for "starts immediately" (checklist PR-6). */
  startsAtMillis: number | null;
  /** Milliseconds since epoch, or `null` for "never expires". */
  expiresAtMillis: number | null;
  maxUses: number;
  usedCount: number;
  active: boolean;
}

export type PromoRejection =
  | 'not_found'
  | 'inactive'
  | 'not_yet_started'
  | 'expired'
  | 'exhausted'
  | 'below_minimum'
  | 'malformed';

export interface PromoResult {
  ok: boolean;
  /** Integer JMD. Always 0 when `ok` is false. */
  discount: number;
  reason?: PromoRejection;
  /** Operator-facing detail; safe to show the customer. */
  message?: string;
}

/** Human-readable reason, shown at checkout. */
export const REJECTION_MESSAGE: Record<PromoRejection, string> = {
  not_found: 'That promo code does not exist.',
  inactive: 'That promo code is no longer available.',
  not_yet_started: 'That promo code is not active yet.',
  expired: 'That promo code has expired.',
  exhausted: 'That promo code has reached its usage limit.',
  below_minimum: 'Your order is below the minimum for that promo code.',
  malformed: 'That promo code is misconfigured. Please contact support.',
};

function reject(reason: PromoRejection): PromoResult {
  return { ok: false, discount: 0, reason, message: REJECTION_MESSAGE[reason] };
}

/**
 * Validates a promo against an order and returns the discount to apply.
 *
 * `subtotal` is the pre-discount goods total in integer JMD, and is always
 * what the minimum-order check runs against — "spend at least J$2,000" means
 * the order, not whichever part of it the discount happens to come off.
 *
 * `discountBaseAmount` (checklist PR-5 "Delivery fee only" / "Order subtotal")
 * is what the discount is actually computed against and cannot exceed. Most
 * promos discount the subtotal, so it defaults to `subtotal` — pass the
 * delivery fee instead for a delivery-only code. Discounting the service fee
 * was never the intent either way, and doing so would make the driver's
 * commission depend on the customer's coupon.
 *
 * Validation order matches SCHEMA.md:
 *   active → startsAt → expiresAt → usedCount < maxUses → subtotal >= minOrderTotal
 */
export function evaluatePromo(
  promo: PromoDoc | null,
  subtotal: number,
  nowMillis: number,
  discountBaseAmount?: number
): PromoResult {
  if (!promo) return reject('not_found');

  if (!Number.isFinite(subtotal) || subtotal < 0) return reject('malformed');
  const base = discountBaseAmount ?? subtotal;
  if (!Number.isFinite(base) || base < 0) return reject('malformed');

  const amount = Number(promo.discountAmount);
  if (!Number.isFinite(amount) || amount < 0) return reject('malformed');
  if (promo.discountType !== 'percent' && promo.discountType !== 'fixed') {
    return reject('malformed');
  }

  if (promo.active !== true) return reject('inactive');

  // Checklist PR-6. A code with a future start is live in the collection but
  // not yet redeemable — the admin scheduled it ahead of a campaign.
  if (promo.startsAtMillis != null && promo.startsAtMillis > nowMillis) {
    return reject('not_yet_started');
  }

  if (promo.expiresAtMillis != null && promo.expiresAtMillis <= nowMillis) {
    return reject('expired');
  }

  const maxUses = Number(promo.maxUses);
  const usedCount = Number(promo.usedCount) || 0;
  if (Number.isFinite(maxUses) && maxUses > 0 && usedCount >= maxUses) {
    return reject('exhausted');
  }

  const minimum = Number(promo.minOrderTotal) || 0;
  if (subtotal < minimum) return reject('below_minimum');

  let discount: number;
  if (promo.discountType === 'percent') {
    // A percentage over 100 would produce a negative total. Clamp rather than
    // reject: the admin's intent for '150% off' is unambiguous, and refusing a
    // live code at checkout punishes the customer for the admin's typo.
    const pct = Math.min(amount, 100);
    discount = Math.round((base * pct) / 100);

    /* The cap is the whole point of `maxDiscount`. A 100% code with no cap is
       an unbounded liability, and nothing prevents an admin creating one by
       typing an extra zero. */
    if (promo.maxDiscount != null && Number.isFinite(Number(promo.maxDiscount))) {
      discount = Math.min(discount, Math.max(0, Math.round(Number(promo.maxDiscount))));
    }
  } else {
    discount = Math.round(amount);
  }

  // A discount can never exceed what is being discounted.
  discount = Math.max(0, Math.min(discount, base));

  return { ok: true, discount };
}
