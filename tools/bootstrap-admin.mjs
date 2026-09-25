#!/usr/bin/env node
/* Grants the FIRST admin (P2-04).
 *
 * setAdminClaim is itself admin-guarded, so there is no admin to authorise the
 * first call. This script breaks that cycle using the Admin SDK directly, and
 * is the only supported way to do so.
 *
 *   NODE_PATH=functions/node_modules \
 *   GOOGLE_APPLICATION_CREDENTIALS=key.json \
 *   node tools/bootstrap-admin.mjs --project shipeast-1a1f6 --email you@example.com
 *
 * Run it once. Every subsequent admin is granted through the callable, which
 * leaves an audit trail in the function logs; this script leaves none.
 */

const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
}

if (!args.project || !args.email) {
  console.error('Usage: node tools/bootstrap-admin.mjs --project <id> --email <address>');
  process.exit(2);
}

const { default: admin } = await import('firebase-admin');
admin.initializeApp({ projectId: args.project });

const email = String(args.email).trim().toLowerCase();

let user;
try {
  user = await admin.auth().getUserByEmail(email);
} catch {
  console.error(
    `No account exists for ${email} in ${args.project}.\n` +
    'Create it in the Firebase console (or let them sign up) before granting admin.'
  );
  process.exit(1);
}

if (user.customClaims?.admin === true) {
  console.log(`${email} is already an admin. Nothing to do.`);
  process.exit(0);
}

await admin.auth().setCustomUserClaims(user.uid, { admin: true });

console.log(`
Granted admin to ${email} (${user.uid}) on ${args.project}.

They must sign out and back in — the claim only reaches the client on the next
ID-token refresh, which can take up to an hour otherwise.

Grant every further admin through the setAdminClaim callable, not this script:
it is audit-logged, and this is not.
`);
