/**
 * Server-side delivery finalisation and commission (P3-04).
 *
 * Two things were wrong before this:
 *
 *   1. Commission was computed on the driver's own device and written straight
 *      into the driver's own earnings field. A modified client could pay
 *      itself anything.
 *
 *   2. `confirmDelivery` took `orderTotal` as a PARAMETER FROM THE CALLER
 *      rather than reading it from the order document, so the earnings figure
 *      depended on what the client passed, not on what the order actually
 *      cost. That is a bug even with an honest client — a stale cached total
 *      silently pays the wrong amount.
 *
 * Both are fixed by recomputing from the order's stored `total` using the
 * server's own rate. `DriverPay.commissionOn` stays in the driver app for
 * display only.
 *
 * This is also a correctness dependency, not just hardening: rules (P2-01)
 * make `todayEarnings` and `totalTrips` server-only, so the old client write
 * would now simply fail.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as OrderStatus from './orderStatus';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

/** Used when `settings/pricing` has no rate, matching driver_constants.dart. */
export const DEFAULT_COMMISSION_RATE = 0.1;

/**
 * The driver's cut of an order total, in integer JMD.
 *
 * Exported and pure so `delivery.test.ts` can pin the arithmetic without a
 * database.
 */
export function commissionOn(orderTotal: number, rate: number): number {
  if (!Number.isFinite(orderTotal) || orderTotal <= 0) return 0;
  if (!Number.isFinite(rate) || rate <= 0) return 0;
  // Clamp defensively: a mistyped rate in settings/pricing must not pay out
  // more than the order was worth.
  const safeRate = Math.min(rate, 1);
  return Math.round(orderTotal * safeRate);
}

async function commissionRate(db: FirebaseFirestore.Firestore): Promise<number> {
  try {
    const snap = await db.collection('settings').doc('pricing').get();
    const rate = Number(snap.data()?.driverCommissionRate);
    return Number.isFinite(rate) && rate > 0 ? rate : DEFAULT_COMMISSION_RATE;
  } catch {
    // A missing settings document must not block a delivery.
    return DEFAULT_COMMISSION_RATE;
  }
}

/**
 * Marks an order delivered and credits the driver, atomically.
 *
 * Returns the commission so the driver app can show it immediately rather than
 * waiting for the order snapshot to round-trip.
 */
export const confirmDelivery = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }

  const uid = request.auth.uid;
  const orderId = String(request.data?.orderId ?? '').trim();
  const photoUrl = String(request.data?.photoUrl ?? '').trim();
  const note = String(request.data?.note ?? '').trim();

  if (!orderId) {
    throw new HttpsError('invalid-argument', 'An orderId is required.');
  }

  const db = admin.firestore();
  const rate = await commissionRate(db);
  const orderRef = db.collection('orders').doc(orderId);
  const driverRef = db.collection('drivers').doc(uid);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'That order no longer exists.');
    }
    const order = snap.data()!;

    // Only the driver holding the order may complete it.
    if (order.driverId !== uid) {
      throw new HttpsError('permission-denied', 'That order is not assigned to you.');
    }

    if (order.status === OrderStatus.DELIVERED) {
      // Idempotent: a retried call must not pay twice. Handlers have to be
      // idempotent anyway (see ROLLBACK.md — a rolled-back function still
      // receives events queued by the newer one).
      return { commission: 0, alreadyDelivered: true };
    }

    if (!OrderStatus.canTransition(String(order.status), OrderStatus.DELIVERED)) {
      throw new HttpsError(
        'failed-precondition',
        `An order in "${order.status}" cannot be marked delivered.`
      );
    }

    // THE FIX: the total comes from the order document, never from the caller.
    const total = Number(order.total) || 0;
    const commission = commissionOn(total, rate);

    tx.update(orderRef, {
      status: OrderStatus.DELIVERED,
      deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      driverCommission: commission,
      commissionRate: rate,
      // Clear the live driver position: once delivered the driver app can no
      // longer clear it itself (the update rule forbids writes to a delivered
      // order), so a stale coordinate would otherwise linger on the record.
      driverLoc: admin.firestore.FieldValue.delete(),
      ...(photoUrl ? { deliveryPhotoUrl: photoUrl } : {}),
      ...(note ? { deliveryNote: note } : {}),
    });

    /* Only `totalTrips` is stored — it is a lifetime counter that never resets.
       Earnings are NOT stored: `todayEarnings` had no reset mechanism
       (SCHEMA.md §d), so the driver app derives it from the `driverCommission`
       now recorded on each delivered order. That is why the commission is
       written to the order above rather than accumulated here. */
    tx.set(
      driverRef,
      {
        totalTrips: admin.firestore.FieldValue.increment(1),
        lastDeliveryAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { commission, alreadyDelivered: false };
  });

  logger.info('delivery confirmed', { orderId, uid, commission: result.commission });
  return result;
});
