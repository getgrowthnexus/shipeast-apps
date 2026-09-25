/**
 * Promo discount eligibility (checklist PR-5).
 *
 * "Give me options for who can get the discount" — twelve conditions in the
 * client's own words: all / new / existing / selected customers, selected
 * merchants, selected categories, selected delivery areas, first order only,
 * delivery fee only, order subtotal, Shop & Deliver requests, specific
 * dates/times.
 *
 * The date/time pair is already covered by `startsAt` / `expiresAt` on the
 * promo itself (checklist PR-6, in `promo.ts`) — those are a schedule
 * condition too, just one that already existed before this file. Everything
 * else lives here: WHO can redeem, WHAT the discount applies to, and WHICH
 * kind of request it applies to.
 *
 * `checkEligibility` decides WHO/WHAT/WHICH; `promo.ts`'s `evaluatePromo`
 * still owns the money math (active/expiry/cap/amount) — the two compose
 * rather than duplicate each other. Every condition here is optional and
 * additive: an absent field imposes no restriction, so a promo with no
 * `eligibility` at all behaves exactly as it did before PR-5 (open to
 * everyone, on the subtotal).
 *
 * Deliberately pure: no firebase-admin import, so it is testable without a
 * database. `eligibility.test.ts` is that test. The one piece that genuinely
 * needs a database — how many prior orders a customer has — is gathered by
 * the caller (`redeemPromo.ts`) and handed in as `priorOrderCount`.
 */

export type CustomerScope = 'new' | 'existing' | 'selected';

/** What kind of request this discount can be redeemed against. `shop_deliver`
 *  is a Shop & Deliver quote (SCHEMA.md `overseasInquiries`), not an order. */
export type OrderKind = 'food' | 'package' | 'shop_deliver';

/** What the discount is computed against. Defaults to `subtotal`. */
export type DiscountBase = 'subtotal' | 'deliveryFee';

/** The eligibility rules on a promo code. Every field is optional; an absent
 *  field imposes no restriction on that dimension. Stored at
 *  `promoCodes/{code}.eligibility`. */
export interface PromoEligibility {
  customerScope?: CustomerScope;
  /** Required, and the only field consulted, when `customerScope === 'selected'`. */
  customerIds?: string[];
  /** Order/quote must be with one of these merchants. Empty/absent = any. */
  merchantIds?: string[];
  /** Merchant category must be one of these. Empty/absent = any. */
  categories?: string[];
  /** Delivery address must contain one of these (parish/area names),
   *  case-insensitively — the same "does the address mention it" match the
   *  admin's Orders filter already uses. Empty/absent = any. */
  deliveryAreas?: string[];
  /** Only the customer's very first order/request, of any kind. */
  firstOrderOnly?: boolean;
  discountBase?: DiscountBase;
  /** Which request kinds this code can apply to. Empty/absent = any. */
  orderKinds?: OrderKind[];
}

/** What the caller must supply about the specific order/quote being checked. */
export interface EligibilityContext {
  customerId: string;
  /** Orders/requests this customer placed before this one, of any status. */
  priorOrderCount: number;
  merchantId?: string | null;
  merchantCategory?: string | null;
  deliveryArea?: string | null;
  orderKind: OrderKind;
}

export type IneligibleReason =
  | 'not_new_customer'
  | 'not_existing_customer'
  | 'customer_not_selected'
  | 'merchant_not_eligible'
  | 'category_not_eligible'
  | 'area_not_eligible'
  | 'not_first_order'
  | 'order_kind_not_eligible';

export const INELIGIBLE_MESSAGE: Record<IneligibleReason, string> = {
  not_new_customer: 'This code is for new customers only.',
  not_existing_customer: 'This code is for returning customers only.',
  customer_not_selected: 'This code is not available on your account.',
  merchant_not_eligible: 'This code does not apply to this merchant.',
  category_not_eligible: 'This code does not apply to this category.',
  area_not_eligible: 'This code is not available for your delivery area.',
  not_first_order: 'This code is for your first order only.',
  order_kind_not_eligible: 'This code does not apply to this kind of request.',
};

export interface EligibilityResult {
  eligible: boolean;
  reason?: IneligibleReason;
  message?: string;
}

function norm(s: string): string {
  return s.trim().toLowerCase();
}

/**
 * Checks every condition on `elig` against `ctx`, in the order a customer
 * would find easiest to understand if told why a code didn't apply — who they
 * are, then where the order is going, then what kind of request it is.
 *
 * All specified conditions must pass (AND, not OR) — "VIP customers ordering
 * from selected merchants" narrows on both axes at once, which is what an
 * admin composing several conditions expects.
 */
export function checkEligibility(
  elig: PromoEligibility | null | undefined,
  ctx: EligibilityContext
): EligibilityResult {
  if (!elig) return { eligible: true };

  if (elig.customerScope === 'new' && ctx.priorOrderCount > 0) {
    return fail('not_new_customer');
  }
  if (elig.customerScope === 'existing' && ctx.priorOrderCount <= 0) {
    return fail('not_existing_customer');
  }
  if (elig.customerScope === 'selected') {
    const ids = elig.customerIds ?? [];
    if (!ids.includes(ctx.customerId)) return fail('customer_not_selected');
  }

  if (elig.merchantIds && elig.merchantIds.length > 0) {
    if (!ctx.merchantId || !elig.merchantIds.includes(ctx.merchantId)) {
      return fail('merchant_not_eligible');
    }
  }

  if (elig.categories && elig.categories.length > 0) {
    if (!ctx.merchantCategory || !elig.categories.includes(ctx.merchantCategory)) {
      return fail('category_not_eligible');
    }
  }

  if (elig.deliveryAreas && elig.deliveryAreas.length > 0) {
    const area = norm(ctx.deliveryArea ?? '');
    const matches = area !== '' && elig.deliveryAreas.some((a) => area.includes(norm(a)));
    if (!matches) return fail('area_not_eligible');
  }

  // Distinct from customerScope 'new': that is about the account's history in
  // general, this is specifically "this transaction is the very first one" —
  // an admin could offer a new-customer code for a month but a first-order
  // code that stops applying the moment any order (even a cancelled one) has
  // ever been placed.
  if (elig.firstOrderOnly && ctx.priorOrderCount > 0) {
    return fail('not_first_order');
  }

  if (elig.orderKinds && elig.orderKinds.length > 0) {
    if (!elig.orderKinds.includes(ctx.orderKind)) return fail('order_kind_not_eligible');
  }

  return { eligible: true };
}

function fail(reason: IneligibleReason): EligibilityResult {
  return { eligible: false, reason, message: INELIGIBLE_MESSAGE[reason] };
}

/** Checklist PR-5 "Delivery fee only" / "Order subtotal": what the discount
 *  is computed against, for `evaluatePromo`'s `discountBaseAmount` parameter.
 *  Defaults to the subtotal — today's behaviour for a promo with no
 *  eligibility rules at all. */
export function discountBaseAmount(
  elig: PromoEligibility | null | undefined,
  subtotal: number,
  deliveryFee: number
): number {
  return elig?.discountBase === 'deliveryFee' ? deliveryFee : subtotal;
}
