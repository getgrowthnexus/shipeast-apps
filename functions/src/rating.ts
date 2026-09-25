/**
 * Rating submission and roll-up (P3-05).
 *
 * The customer app has always *collected* a merchant rating on the order — and
 * then thrown it away. Nothing ever computed a merchant average, so the admin
 * panel showed a permanent 5.0 for every merchant. The per-star histogram on
 * the driver panel was in the same position: correctly rendering an honest
 * empty state, because nothing wrote the data it needed.
 *
 * This is server-side rather than a client transaction because P2-01 makes the
 * aggregate fields server-only. A driver who can write their own
 * `averageRating` can give themselves five stars, and a customer who can write
 * a merchant document can rewrite the menu. So the roll-up moves here — this
 * is a correctness dependency of the rules, not only hardening.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as OrderStatus from './orderStatus';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

/** Rounds to one decimal so stored averages match what is displayed. */
export function averageOf(totalStars: number, count: number): number {
  if (!count) return 0;
  return Math.round((totalStars / count) * 10) / 10;
}

function validStar(value: unknown): number | null {
  const n = Math.round(Number(value));
  return Number.isFinite(n) && n >= 1 && n <= 5 ? n : null;
}

/**
 * Increments the aggregate rating fields on a driver or merchant document.
 *
 * `ratingCounts` is the per-star histogram the admin's driver panel already
 * renders; it simply starts working once this populates it.
 */
function rollUp(
  tx: FirebaseFirestore.Transaction,
  ref: FirebaseFirestore.DocumentReference,
  snap: FirebaseFirestore.DocumentSnapshot,
  stars: number
): void {
  const data = snap.data() ?? {};
  const totalRatings = (Number(data.totalRatings) || 0) + stars;
  const ratingCount = (Number(data.ratingCount) || 0) + 1;

  tx.set(
    ref,
    {
      totalRatings,
      ratingCount,
      averageRating: averageOf(totalRatings, ratingCount),
      ratingCounts: {
        ...(data.ratingCounts ?? {}),
        [String(stars)]: (Number(data.ratingCounts?.[String(stars)]) || 0) + 1,
      },
    },
    { merge: true }
  );
}

export const submitRating = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }

  const uid = request.auth.uid;
  const orderId = String(request.data?.orderId ?? '').trim();
  if (!orderId) {
    throw new HttpsError('invalid-argument', 'An orderId is required.');
  }

  const driverStars = validStar(request.data?.driverRating);
  const merchantStars = validStar(request.data?.merchantRating);
  if (driverStars == null && merchantStars == null) {
    throw new HttpsError('invalid-argument', 'A rating of 1–5 is required.');
  }

  const comment = String(request.data?.comment ?? '').slice(0, 1000);
  const tags = Array.isArray(request.data?.tags)
    ? request.data.tags.slice(0, 10).map((t: unknown) => String(t).slice(0, 40))
    : [];

  const db = admin.firestore();
  const orderRef = db.collection('orders').doc(orderId);

  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'That order no longer exists.');
    }
    const order = orderSnap.data()!;

    if (order.customerId !== uid) {
      throw new HttpsError('permission-denied', 'That is not your order.');
    }
    if (order.status !== OrderStatus.DELIVERED) {
      throw new HttpsError(
        'failed-precondition',
        'You can only rate a delivered order.'
      );
    }
    // Rating twice would double-count into every aggregate below.
    if (order.rated === true) {
      throw new HttpsError('already-exists', 'You have already rated this order.');
    }

    const driverId = String(order.driverId ?? '');
    const merchantId = String(order.merchantId ?? '');

    // All reads must precede all writes in a Firestore transaction.
    const driverRef = driverId ? db.collection('drivers').doc(driverId) : null;
    const merchantRef = merchantId ? db.collection('merchants').doc(merchantId) : null;
    const driverSnap = driverRef ? await tx.get(driverRef) : null;
    const merchantSnap = merchantRef ? await tx.get(merchantRef) : null;

    tx.update(orderRef, {
      rated: true,
      driverRating: driverStars,
      merchantRating: merchantStars,
      comment,
      tags,
      ratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (driverStars != null && driverRef && driverSnap?.exists) {
      rollUp(tx, driverRef, driverSnap, driverStars);
    }
    // The half that never existed: the merchant rating was collected and
    // discarded, which is why every merchant showed a permanent 5.0.
    if (merchantStars != null && merchantRef && merchantSnap?.exists) {
      rollUp(tx, merchantRef, merchantSnap, merchantStars);
    }
  });

  logger.info('rating submitted', { orderId, uid, driverStars, merchantStars });
  return { ok: true };
});
