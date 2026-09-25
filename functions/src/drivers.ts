/**
 * Admin-initiated driver provisioning (P4-05).
 *
 * Audit §4. The admin panel's "Add Driver" button called `addDoc`, producing a
 * `drivers/{randomId}` document with **no Auth account behind it**. That
 * person could never sign in. When they eventually self-registered they got a
 * second document at `drivers/{theirUid}`, leaving the original as an orphan
 * that still appeared in the roster, still counted in the driver total, and
 * could still be "approved" — approving nobody.
 *
 * The fix is that the account and the document are created together, keyed by
 * the same uid, by a server that is allowed to do both.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

export interface DriverInput {
  email: string;
  name: string;
  phone?: string;
  vehicleType?: string;
  vehicleModel?: string;
  licencePlate?: string;
  licenceNumber?: string;
}

export interface NormalisedDriver {
  email: string;
  name: string;
  phone: string;
  vehicleType: string;
  vehicleModel: string;
  licencePlate: string;
  /** Split out because it is PII — see `splitPrivate` below. */
  licenceNumber: string;
}

const VEHICLE_TYPES = ['Car', 'Motorcycle', 'Van', 'Truck'];

/**
 * Validate and canonicalise the admin's input.
 *
 * Pure and exported so `drivers.test.ts` can pin it without Auth or a
 * database. Throws a plain Error; the callable converts it to an HttpsError.
 */
export function normaliseDriver(input: Partial<DriverInput> | undefined): NormalisedDriver {
  const email = String(input?.email ?? '').trim().toLowerCase();
  const name = String(input?.name ?? '').trim();

  // Deliberately permissive: this is a sanity check against typos, not an
  // attempt to implement RFC 5322. Auth rejects what it will not accept.
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new Error('A valid email address is required — it is how the driver signs in.');
  }
  if (!name) {
    throw new Error('The driver\'s full name is required.');
  }

  const vehicleType = String(input?.vehicleType ?? '').trim();
  return {
    email,
    name,
    phone: String(input?.phone ?? '').trim(),
    // An unrecognised vehicle type falls back rather than failing: the driver
    // can correct it in their profile, and blocking onboarding over a dropdown
    // value helps nobody.
    vehicleType: VEHICLE_TYPES.includes(vehicleType) ? vehicleType : 'Car',
    vehicleModel: String(input?.vehicleModel ?? '').trim(),
    licencePlate: String(input?.licencePlate ?? '').trim().toUpperCase(),
    licenceNumber: String(input?.licenceNumber ?? '').trim()
  };
}

/**
 * Split the profile into the public document and the private one.
 *
 * `drivers/{uid}` is readable by **any signed-in user** — it has to be, because
 * the customer's tracking card shows the name, vehicle and rating of the driver
 * bringing their order, and rules cannot express "the customer of an order this
 * driver currently holds".
 *
 * That makes the parent document the wrong place for a licence number. Every
 * customer who ever placed an order could read every driver's licence. It goes
 * to `drivers/{uid}/private/identity`, which only the driver and an admin can
 * read (firestore.rules §drivers).
 */
export function splitPrivate(d: NormalisedDriver): {
  publicDoc: Record<string, unknown>;
  privateDoc: Record<string, unknown> | null;
} {
  return {
    publicDoc: {
      name: d.name,
      email: d.email,
      phone: d.phone || '—',
      vehicleType: d.vehicleType,
      vehicleModel: d.vehicleModel || '—',
      licencePlate: d.licencePlate || '—',
      // Always pending. An admin-created driver is still an application: the
      // approval decision stays a separate, deliberate act.
      status: 'pending',
      isOnline: false,
      totalTrips: 0,
      ratingCount: 0,
      averageRating: 0,
      todayEarnings: 0,
      createdBy: 'admin'
    },
    privateDoc: d.licenceNumber ? { licenceNumber: d.licenceNumber } : null
  };
}

/**
 * Creates the Auth account and the driver document, and returns an invite link.
 *
 * A password-reset link is the invite: it proves the driver controls the
 * address, and it means no temporary password is ever transmitted or stored.
 * The account is created with a random unguessable password that nobody —
 * including this function's caller — ever sees.
 */
export const createDriverAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  if (request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Only an admin can add a driver.');
  }

  let driver: NormalisedDriver;
  try {
    driver = normaliseDriver(request.data as Partial<DriverInput>);
  } catch (e) {
    throw new HttpsError('invalid-argument', (e as Error).message);
  }

  const db = admin.firestore();
  const auth = admin.auth();

  // An existing account is reused rather than refused. The common case is a
  // driver who self-registered and whose profile the admin is completing;
  // creating a second account would recreate the exact duplication this
  // function exists to end.
  let user: admin.auth.UserRecord;
  let created = false;
  try {
    user = await auth.getUserByEmail(driver.email);
  } catch {
    try {
      user = await auth.createUser({
        email: driver.email,
        displayName: driver.name,
        emailVerified: false,
        // Never seen by anyone. The driver sets their own via the invite link.
        password: `${crypto.randomUUID()}${crypto.randomUUID()}`
      });
      created = true;
    } catch (e) {
      throw new HttpsError('internal',
        `Could not create the account: ${(e as Error).message}`);
    }
  }

  const { publicDoc, privateDoc } = splitPrivate(driver);
  const ref = db.collection('drivers').doc(user.uid);
  const existing = await ref.get();

  if (existing.exists) {
    // Merge, and never reset a status the admin already decided. Overwriting
    // an approved driver back to pending would take a working driver offline.
    const patch: Record<string, unknown> = { ...publicDoc };
    delete patch.status;
    delete patch.totalTrips;
    delete patch.ratingCount;
    delete patch.averageRating;
    delete patch.todayEarnings;
    patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await ref.set(patch, { merge: true });
  } else {
    await ref.set({
      ...publicDoc,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  }

  if (privateDoc) {
    await ref.collection('private').doc('identity').set(
      { ...privateDoc, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
  }

  let inviteLink: string | null = null;
  try {
    inviteLink = await auth.generatePasswordResetLink(driver.email);
  } catch (e) {
    // The account and document exist and are correct; only the convenience of
    // a ready-made link is missing. Report that honestly rather than failing
    // the whole call and leaving the admin unsure what landed.
    logger.warn('invite link generation failed', { email: driver.email, error: String(e) });
  }

  logger.info('driver provisioned', {
    uid: user.uid, email: driver.email, accountCreated: created, by: request.auth.uid
  });

  return {
    uid: user.uid,
    email: driver.email,
    accountCreated: created,
    inviteLink,
    note: created
      ? 'Account created. Send the invite link so they can set a password.'
      : 'An account already existed for this email; the driver profile was updated.'
  };
});
