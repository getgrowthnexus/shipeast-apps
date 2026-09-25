/**
 * Admin claim management (P2-04).
 *
 * firestore.rules identifies admins by the custom claim `admin: true`, not by
 * an email allowlist in client code — an allowlist shipped in a browser bundle
 * is trivially bypassed, and the rules would then be enforcing nothing.
 *
 * This file is what sets that claim.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

/**
 * Grants or revokes admin on another account.
 *
 * Itself admin-guarded: only an existing admin may create another. The first
 * admin is bootstrapped out-of-band — see tools/bootstrap-admin.mjs — because
 * there is no admin to authorise the first call.
 */
export const setAdminClaim = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  if (request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Only an admin can grant admin.');
  }

  const email = String(request.data?.email ?? '').trim().toLowerCase();
  const grant = request.data?.admin === true;

  if (!email) {
    throw new HttpsError('invalid-argument', 'An email is required.');
  }

  // Refusing self-revocation prevents the last admin locking everyone out of
  // the panel, which would need another out-of-band bootstrap to undo.
  if (!grant && email === String(request.auth.token.email ?? '').toLowerCase()) {
    throw new HttpsError(
      'failed-precondition',
      'You cannot revoke your own admin access.'
    );
  }

  let user: admin.auth.UserRecord;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch {
    throw new HttpsError('not-found', `No account exists for ${email}.`);
  }

  await admin.auth().setCustomUserClaims(user.uid, grant ? { admin: true } : {});

  // The claim reaches the client on the next ID-token refresh (up to an hour),
  // or immediately if the client calls getIdToken(true). Revocation is
  // therefore NOT instant — say so rather than implying it is.
  logger.info('admin claim updated', {
    target: user.uid,
    email,
    grant,
    by: request.auth.uid
  });

  return {
    uid: user.uid,
    email,
    admin: grant,
    note: 'Takes effect on the target\'s next token refresh (up to 1 hour).'
  };
});
