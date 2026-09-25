/**
 * Server-side promo redemption (P3-03).
 *
 * The customer app validates a code locally so the discount appears instantly
 * at checkout, but that result is advisory. This function produces the number
 * that is actually written to the order, and it is the only writer of
 * `usedCount` — security rules make that field server-only, which is what
 * turns the usage cap from a suggestion into an enforced limit.
 *
 * The transaction matters. Two customers redeeming the last use of a
 * `maxUses: 1` code at the same moment must not both succeed; a read-then-write
 * outside a transaction lets exactly that happen.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';
import { evaluatePromo, PromoDoc, REJECTION_MESSAGE, PromoRejection } from './promo';
import {
  checkEligibility, discountBaseAmount, PromoEligibility, OrderKind
} from './eligibility';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

/** Maps a stored promo document onto the pure evaluator's input shape. */
function toPromoDoc(data: FirebaseFirestore.DocumentData): PromoDoc {
  const expiresAt = data.expiresAt as admin.firestore.Timestamp | null | undefined;
  const startsAt = data.startsAt as admin.firestore.Timestamp | null | undefined;
  return {
    code: String(data.code ?? ''),
    discountType: data.discountType,
    discountAmount: Number(data.discountAmount),
    minOrderTotal: Number(data.minOrderTotal) || 0,
    maxDiscount: data.maxDiscount == null ? null : Number(data.maxDiscount),
    startsAtMillis: startsAt?.toMillis?.() ?? null,
    expiresAtMillis: expiresAt?.toMillis?.() ?? null,
    maxUses: Number(data.maxUses),
    usedCount: Number(data.usedCount) || 0,
    active: data.active === true,
  };
}

function toEligibility(data: unknown): PromoEligibility | null {
  if (!data || typeof data !== 'object') return null;
  return data as PromoEligibility;
}

/**
 * How many orders this customer placed before now (checklist PR-5's "new" /
 * "existing" / "first order only" conditions). Any status counts — a
 * cancelled order still means the account is not new.
 *
 * A plain count query, not a transaction read: a customer racing their own
 * order history is not a threat model worth transactionalising, unlike the
 * `usedCount` cap two people can genuinely race for.
 */
async function priorOrderCount(customerId: string): Promise<number> {
  const snap = await admin.firestore().collection('orders')
    .where('customerId', '==', customerId)
    .count()
    .get();
  return snap.data().count;
}

/* There is no `previewPromo` callable on purpose. Rules already allow an
   authenticated read of `promoCodes`, so the client previews locally with its
   own copy of the evaluator — no cold start on every keystroke. The preview is
   never trusted; this function is what the order's discount comes from. */

/**
 * Consumes one use of a code and returns the authoritative discount.
 *
 * Called at order placement, not at code entry — a customer who types a code
 * and then abandons checkout must not burn a use.
 *
 * KNOWN RESIDUAL GAP, stated plainly: this makes the *usage cap* real, but a
 * modified client can still write an order claiming a discount it never
 * redeemed here. Rules enforce that the order's arithmetic is self-consistent
 * (P2-01), not that its discount was authorised. Closing that needs order
 * creation itself to move server-side, which is deliberately out of P3-03's
 * scope. Until then the exposure is bounded by the fact that orders are
 * cash-on-delivery and every total is visible to the admin panel.
 */
export const redeemPromo = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }

  const code = String(request.data?.code ?? '').trim().toUpperCase();
  const subtotal = Math.round(Number(request.data?.subtotal));
  const deliveryFee = Math.round(Number(request.data?.deliveryFee) || 0);
  // PR-5 eligibility context. All optional — a caller that sends none of this
  // (an older app build) still gets a correct result against any code with no
  // eligibility rules, which is every promo created before PR-5.
  const merchantId = typeof request.data?.merchantId === 'string' ? request.data.merchantId : null;
  const merchantCategory = typeof request.data?.merchantCategory === 'string' ? request.data.merchantCategory : null;
  const deliveryAddress = typeof request.data?.deliveryAddress === 'string' ? request.data.deliveryAddress : '';
  const orderKind: OrderKind = (['food', 'package', 'shop_deliver'] as const)
    .includes(request.data?.orderKind) ? request.data.orderKind : 'food';

  if (!code) throw new HttpsError('invalid-argument', 'A promo code is required.');
  if (!Number.isFinite(subtotal) || subtotal < 0) {
    throw new HttpsError('invalid-argument', 'A valid subtotal is required.');
  }

  const uid = request.auth.uid;
  const db = admin.firestore();
  const ref = db.collection('promoCodes').doc(code);

  // Read outside the transaction — see priorOrderCount's own comment on why
  // this one need not be transactional.
  const priorOrders = await priorOrderCount(uid);

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data()! : undefined;

    // PR-5: eligibility is checked before the money math, against freshly
    // read state, same as everything else in this transaction. A code with
    // no `eligibility` field (every promo created before PR-5) always passes.
    const eligibility = data ? toEligibility(data.eligibility) : null;
    const check = checkEligibility(eligibility, {
      customerId: uid,
      priorOrderCount: priorOrders,
      merchantId,
      merchantCategory,
      deliveryArea: deliveryAddress,
      orderKind,
    });
    if (!check.eligible) {
      return { ok: false as const, discount: 0, reason: check.reason, message: check.message };
    }

    // Re-evaluated INSIDE the transaction against freshly read state, so the
    // cap holds under concurrency. The client's earlier preview is ignored.
    const result = evaluatePromo(
      data ? toPromoDoc(data) : null,
      subtotal,
      Date.now(),
      discountBaseAmount(eligibility, subtotal, deliveryFee)
    );

    if (!result.ok) return result;

    tx.update(ref, {
      usedCount: admin.firestore.FieldValue.increment(1),
      lastRedeemedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return result;
  });

  if (!outcome.ok) {
    logger.info('promo rejected', { code, reason: outcome.reason, uid });
    throw new HttpsError(
      'failed-precondition',
      outcome.message ?? REJECTION_MESSAGE[outcome.reason as PromoRejection]
    );
  }

  logger.info('promo redeemed', { code, discount: outcome.discount, uid });
  return { code, discount: outcome.discount };
});
