/**
 * Customer account administration (P5-05).
 *
 * The `users` collection had no admin surface at all: an admin could see an
 * order but could not look up who placed it, what else they had ordered, or
 * disable an account that was abusing the service.
 *
 * The read side of that is pure admin-panel work — P2-01 already grants an
 * admin read on `users`. This file exists for the one thing the panel cannot
 * do from the client: actually disabling somebody.
 *
 * ## Why a callable rather than a rules-permitted field write
 *
 * Rules let an admin write `users/{uid}.disabled` and nothing else. On its own
 * that flag is decoration — Firestore rules do not consult it, so a "disabled"
 * customer keeps their session, keeps placing orders, and keeps appearing in
 * the queue. The only thing that genuinely stops them is disabling the Auth
 * account, which revokes the session and refuses new sign-ins, and that is
 * privileged.
 *
 * So the flag and the account move together, here, or the flag lies.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

export interface DisableInput {
  uid: string;
  disabled: boolean;
  reason?: string;
}

export interface NormalisedDisable {
  uid: string;
  disabled: boolean;
  reason: string;
}

/** Longest reason we store. Long enough for a sentence, short enough that the
 *  field cannot be used as free storage. */
export const MAX_REASON_LENGTH = 500;

/**
 * Validate and canonicalise the admin's request.
 *
 * Pure and exported so `customers.test.ts` can pin it without Auth or a
 * database. Throws a plain Error; the callable converts it to an HttpsError.
 */
export function normaliseDisable(input: Partial<DisableInput> | undefined): NormalisedDisable {
  const uid = String(input?.uid ?? '').trim();
  if (!uid) {
    throw new Error('A uid is required.');
  }
  // Auth uids are at most 128 characters. A longer one cannot match an account,
  // and rejecting it here keeps a junk value out of the log line below.
  if (uid.length > 128) {
    throw new Error('That uid is not a valid account identifier.');
  }

  // Deliberately strict rather than truthy: `disabled: 'false'` from a
  // hand-rolled call must not read as true and lock somebody out.
  if (typeof input?.disabled !== 'boolean') {
    throw new Error('`disabled` must be true or false.');
  }

  const reason = String(input?.reason ?? '').trim().slice(0, MAX_REASON_LENGTH);

  // Re-enabling needs no justification; taking access away does. An audit trail
  // that says only "an admin did this" answers none of the questions asked
  // afterwards.
  if (input.disabled && !reason) {
    throw new Error('A reason is required when disabling an account.');
  }

  return { uid, disabled: input.disabled, reason };
}

/**
 * The Firestore fields recorded alongside the Auth change.
 *
 * Split out from the callable so the shape is testable, and so it is obvious
 * that re-enabling *clears* the reason rather than leaving a stale one behind —
 * a re-enabled account carrying "fraudulent orders" in its record is worse than
 * carrying nothing.
 */
export function disableFields(
  d: NormalisedDisable,
  at: FirebaseFirestore.FieldValue
): Record<string, unknown> {
  return d.disabled
    ? { disabled: true, disabledReason: d.reason, disabledAt: at }
    : { disabled: false, disabledReason: null, disabledAt: null };
}

/**
 * Disables or re-enables a customer account.
 *
 * The Auth account is changed first. If Firestore then fails, the account is
 * genuinely disabled and the panel shows a stale flag — noisy, but safe. The
 * other order fails open: the flag would say "disabled" over an account that
 * still works, which is the exact lie this function exists to prevent.
 */
export const setUserDisabled = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  if (request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Only an admin can change an account.');
  }

  let input: NormalisedDisable;
  try {
    input = normaliseDisable(request.data as Partial<DisableInput>);
  } catch (e) {
    throw new HttpsError('invalid-argument', (e as Error).message);
  }

  // An admin who disables their own account loses the panel with no way back
  // in, and the fix requires console access. Cheap to prevent.
  if (input.uid === request.auth.uid) {
    throw new HttpsError('failed-precondition', 'You cannot disable your own account.');
  }

  try {
    await admin.auth().updateUser(input.uid, { disabled: input.disabled });
  } catch (e) {
    const code = (e as { code?: string }).code;
    if (code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'That account no longer exists.');
    }
    throw new HttpsError('internal', 'Could not change the account.');
  }

  // Revoking refresh tokens is what makes a disable take effect *now* rather
  // than whenever the customer's ID token happens to expire — up to an hour of
  // continued ordering otherwise.
  if (input.disabled) {
    try {
      await admin.auth().revokeRefreshTokens(input.uid);
    } catch (e) {
      // The account is already disabled, so this is a delay, not a hole.
      logger.warn('could not revoke refresh tokens', { uid: input.uid, error: String(e) });
    }
  }

  await admin
    .firestore()
    .collection('users')
    .doc(input.uid)
    .set(
      {
        ...disableFields(input, admin.firestore.FieldValue.serverTimestamp()),
        disabledBy: request.auth.uid
      },
      { merge: true }
    );

  logger.info('customer account access changed', {
    uid: input.uid,
    disabled: input.disabled,
    by: request.auth.uid
  });

  return { uid: input.uid, disabled: input.disabled };
});
