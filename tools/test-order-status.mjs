#!/usr/bin/env node
/* Tests for the admin panel's order lifecycle module (P1-06).
   The Dart copies have flutter_test; this is the JS equivalent.

   `saveOrderChanges` itself cannot be tested here — app.js imports the Firebase
   SDK from gstatic, which does not resolve under node. What IS tested is the
   decision logic it delegates to, which is where the damage was. */

import * as OS from '../admin_panel/order-status.js';

let pass = 0;
const failures = [];

function check(name, fn) {
  try {
    fn();
    pass++;
  } catch (e) {
    failures.push(`${name}: ${e.message}`);
  }
}
const eq = (a, b, m = '') => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A !== B) throw new Error(`${m} expected ${B}, got ${A}`);
};
const ok = (v, m) => { if (!v) throw new Error(m || 'expected true'); };
const no = (v, m) => { if (v) throw new Error(m || 'expected false'); };

// ── The dropdown ───────────────────────────────────────────────────────────

check('dropdown offers current status plus legal successors only', () => {
  eq(OS.selectableFrom(OS.PENDING), [OS.PENDING, OS.CONFIRMED, OS.CANCELLED]);
  eq(OS.selectableFrom(OS.CONFIRMED), [OS.CONFIRMED, OS.PICKED_UP, OS.CANCELLED]);
  eq(OS.selectableFrom(OS.PICKED_UP), [OS.PICKED_UP, OS.IN_TRANSIT, OS.CANCELLED]);
  eq(OS.selectableFrom(OS.IN_TRANSIT), [OS.IN_TRANSIT, OS.DELIVERED, OS.CANCELLED]);
});

check('terminal orders offer no onward move', () => {
  eq(OS.selectableFrom(OS.DELIVERED), [OS.DELIVERED]);
  eq(OS.selectableFrom(OS.CANCELLED), [OS.CANCELLED]);
});

check('no canonical status can move to the retired accepted status', () => {
  // Note this asks about accepted as a *destination*. A legacy order already
  // sitting in 'accepted' still displays its own status — see the next check.
  for (const s of OS.ALL) {
    no(OS.selectableFrom(s).includes('accepted'), `selectableFrom(${s})`);
    no(OS.canTransition(s, 'accepted'), `${s} -> accepted`);
  }
});

check('a legacy status is shown but offers no successors', () => {
  // An 'accepted' row still in production must render, without inviting the
  // admin to guess a move out of a state the lifecycle does not define.
  eq(OS.selectableFrom('accepted'), ['accepted']);
});

check('the admin can never skip the transit step', () => {
  // This is what made the customer's "On the Way" step reachable at all.
  no(OS.selectableFrom(OS.PICKED_UP).includes(OS.DELIVERED));
});

check('in_transit is a real selectable state, not a trap', () => {
  // It used to be offered AND to strip the driver of the order, because it
  // fell outside their active-order query. It is now a held state.
  ok(OS.selectableFrom(OS.PICKED_UP).includes(OS.IN_TRANSIT));
  ok(OS.isDriverHeld(OS.IN_TRANSIT));
});

// ── Transitions ────────────────────────────────────────────────────────────

check('canTransition rejects backwards and terminal moves', () => {
  no(OS.canTransition(OS.DELIVERED, OS.PENDING));
  no(OS.canTransition(OS.CANCELLED, OS.PENDING));
  no(OS.canTransition(OS.IN_TRANSIT, OS.PICKED_UP));
  no(OS.canTransition(OS.CONFIRMED, OS.PENDING));
});

check('canTransition rejects unknown statuses in either position', () => {
  no(OS.canTransition('accepted', OS.CONFIRMED));
  no(OS.canTransition(OS.PENDING, 'accepted'));
  no(OS.canTransition('', ''));
});

check('no status transitions to itself', () => {
  for (const s of OS.ALL) no(OS.canTransition(s, s), s);
});

check('cancellation is reachable from every non-terminal state', () => {
  for (const s of OS.ACTIVE) ok(OS.canTransition(s, OS.CANCELLED), s);
});

// ── Assignment ─────────────────────────────────────────────────────────────

check('assigning to a pending order must advance it to confirmed', () => {
  // The black hole: leaving it pending satisfies neither driver query — the
  // available pool needs driverId == null, the active stream needs a held
  // status — so the order is invisible to every driver at once.
  no(OS.isDriverHeld(OS.PENDING), 'pending must not be driver-held');
  ok(OS.isDriverHeld(OS.CONFIRMED), 'confirmed must be driver-held');
  ok(OS.canTransition(OS.PENDING, OS.CONFIRMED));
});

check('unassigning must return the order to pending for the pool', () => {
  for (const s of OS.DRIVER_HELD) ok(OS.isDriverHeld(s), s);
  no(OS.isDriverHeld(OS.PENDING));
});

check('driver-held and terminal never overlap', () => {
  for (const s of OS.DRIVER_HELD) no(OS.isTerminal(s), s);
});

check('vocabulary is exactly six statuses with no duplicates', () => {
  eq(OS.ALL.length, 6);
  eq(new Set(OS.ALL).size, 6);
  for (const s of OS.ALL) ok(OS.LABEL[s], `no label for ${s}`);
});

// ── Report ─────────────────────────────────────────────────────────────────

if (failures.length) {
  console.error(`\n${failures.length} failure(s):\n`);
  for (const f of failures) console.error('::error::' + f);
  process.exit(1);
}
console.log(`order-status.js: ${pass}/${pass} checks passed`);
