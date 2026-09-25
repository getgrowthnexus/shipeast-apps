# ShipEast — Execution Plan (Customer · Driver · Admin)

**Companion to:** [all-three-apps-audit.md](all-three-apps-audit.md) — every work item below cites the audit
section it resolves.
**Repo:** `Shipeast-App` · **Branch base:** `main` · **Written:** 2026-07-21
**Firebase project (prod):** `shipeast-1a1f6`

---

## How to read this document

Work is grouped into **seven phases**. Phases are strictly ordered — each depends on the one before.
Within a phase, items marked **∥** can run in parallel; everything else is sequential.

Each work item has a stable ID (`P1-03`), the exact files it touches, the change, its acceptance
criteria, and its dependencies. Use the IDs in commit messages and PR titles so the plan stays
traceable.

**Estimates** are in *ideal engineering days* for one experienced Flutter + Firebase developer.
Multiply by your own factor for meetings, review latency, and context switching. Total: **~47 ideal
days**, realistically **10–13 calendar weeks** for one developer, **6–7 weeks** for two working the
parallel tracks.

### Legend

| Mark | Meaning |
|------|---------|
| **∥** | Parallelisable with siblings in the same phase |
| **⚠️** | Touches live production data — requires the migration protocol in §Phase 2 |
| **🔒** | Cannot be done client-side; needs Cloud Functions |
| **✅** | Has an automated test as part of its acceptance criteria |

---

## Phase 0 — Foundations before any code changes

**Goal:** make it possible to change things safely. Nothing in this repository is currently
verifiable — no toolchain, no staging environment, no test gate, no schema of record. Every later
phase depends on fixing that first.

**Duration:** ~4 days · **Blocks:** everything

---

### P0-01 — Stand up a staging Firebase project ⚠️

**Why:** Phases 1–3 rewrite the shape of live data. Doing that against `shipeast-1a1f6` with no
rehearsal environment risks the production dataset with no way back.

**Steps:**
1. Create Firebase project `shipeast-staging`. Enable Auth (Email/Password), Firestore, Storage.
2. Export production Firestore (`gcloud firestore export`) to a GCS bucket; import into staging.
   This gives realistic data shapes, including the inconsistent legacy documents.
3. Generate `firebase_options.dart` for staging in both apps via `flutterfire configure`.
4. Introduce build-time environment selection so the same source targets either project:
   - Add `customer_app/lib/firebase_options_staging.dart` and the driver equivalent.
   - Select via `--dart-define=SE_ENV=staging|prod` read in `main.dart` before
     `Firebase.initializeApp`.
   - Admin panel: extract the config block from `admin_panel/app.js:11-17` into `config.js`, with
     `config.staging.js` swapped at deploy time by the hosting target.
5. Add a second Firebase Hosting target for the staging admin panel.

**Acceptance:** both APKs and the admin panel can be built against staging, sign in, and read data,
with zero writes reaching production. Verified by watching prod's Firestore usage graph stay flat
during a staging smoke test.

**Estimate:** 1 day

---

### P0-02 — Install and pin the toolchain ∥

**Why:** the audit could not run `flutter analyze`, `flutter test`, or build anything. That gap has
to close before any refactor of this size begins, or every change ships unverified.

**Steps:**
1. Install Flutter stable matching `pubspec.yaml`'s `sdk: ^3.11.5` on the dev machine and confirm
   `flutter doctor` is clean for Android.
2. Commit `.tool-versions` (or `fvm_config.json`) pinning the exact Flutter version, so CI and local
   builds cannot drift.
3. Run `flutter analyze` on both apps and record the baseline. **Do not fix findings yet** — capture
   the count, so P0-03 can enforce "no new warnings" without blocking on pre-existing ones.
4. Run `flutter test` on both apps to confirm the harness works.

**Acceptance:** `flutter analyze` and `flutter test` both execute to completion in `customer_app`
and `driver_app`, and their output is recorded in the PR description as the baseline.

**Estimate:** 0.5 day

---

### P0-03 — Add real CI gates ✅

**Why:** `.github/workflows/build-customer-apk.yml` and its driver twin build APKs on push to `main`
but **never run `flutter analyze` or `flutter test`**. Nothing prevents a broken commit from
producing a published release artifact.

Also note: `driver_app/test/widget_test.dart` is a placeholder that asserts `expect(true, isTrue)` —
it passes unconditionally and tests nothing. It must be replaced, not counted as coverage.

**Steps:**
1. Create `.github/workflows/verify.yml` running on **pull requests** and pushes to `main`:
   - Matrix over `[customer_app, driver_app]`.
   - `flutter pub get` → `flutter analyze --no-fatal-infos` → `flutter test`.
   - Fail the job on any analyzer *error*; warn-only on infos until P6-02 cleans the baseline.
2. Add a `node --check admin_panel/app.js` step plus an ESLint pass (`eslint:recommended`, `env:
   browser, es2022`) so admin syntax errors are caught before deploy.
3. Make the two existing APK workflows `needs: verify`, so no artifact publishes from code that
   does not analyze and test clean.
4. Add branch protection on `main` requiring `verify` to pass.

**Acceptance:** a PR containing a deliberate type error is blocked by CI. A PR containing a
deliberately failing test is blocked by CI. The APK workflows do not run when `verify` fails.

**Estimate:** 0.5 day · **Depends on:** P0-02

---

### P0-04 — Write the schema of record ⚠️

**Why:** the audit's root cause (§13) is that three apps were built against three different mental
models with no written contract. Fixing the eleven mismatches without first writing down the target
shape just re-creates the problem in a new configuration.

**Deliverable:** `SCHEMA.md` at the repo root — the single source of truth every later phase
implements against. It must specify, for each collection, every field's **name, type, who writes it,
who reads it, and whether it is required**.

Collections to specify: `orders`, `orders/{id}` subfields for items, `drivers`, `merchants`,
`merchants/{id}/menuItems`, `promoCodes`, `notifications`, `users`, `users/{uid}/addresses`.

**The decisions this document must lock in** (each resolves a specific audit finding):

**a) Canonical order status (resolves audit §2)** — adopt the driver app's vocabulary, since it is
the one actually written today, and add the two missing states:

```
pending      order placed, no driver claimed
confirmed    driver claimed, en route to merchant
picked_up    driver has the goods
in_transit   driver en route to customer          ← new, currently unwritten
delivered    terminal, success
cancelled    terminal, failure
```

Legal transitions (enforced in rules in P2-01):
```
pending    → confirmed | cancelled
confirmed  → picked_up | cancelled
picked_up  → in_transit | cancelled
in_transit → delivered  | cancelled
delivered  → (terminal)
cancelled  → (terminal)
```

Define this once as a shared constant, not as string literals scattered across screens. See P1-01.

**b) Spelling convention** — British spelling throughout for licence fields (`licencePlate`,
`licenceNumber`), because both current *writers* (driver registration and the admin panel) already
use it and only the customer *reader* is wrong (audit §12). Fixing one reader is cheaper and less
risky than migrating two writers plus existing documents.

**c) Money representation** — all monetary values are **integers in JMD, no decimals, no currency
symbol, no thousands separators**. This kills `fee: '$250'` (audit §6.1) and the
`amount`/`rawTotal` dual-read in `admin_panel/app.js:274-278`. Formatting happens only at render
time, via the existing `Money.format` (`driver_constants.dart`) and admin `money()` helpers.

**d) Timestamps** — all date/time fields are Firestore `Timestamp`, never strings. This kills
`validUntil: '2026-08-01'` (audit §5).

**e) Merchant field names** — the customer app's names win (`deliveryFee`, `deliveryTime`), because
they are read in more places and the admin's `fee`/`hours` are read by nothing. But note the
semantic collision to resolve: the admin's "Opening Hours" input is a *business hours* field, while
the customer's `deliveryTime` is an *ETA estimate*. These are two different things that were
conflated. `SCHEMA.md` must define **both**: `openingHours` (string, display-only) and
`deliveryTime` (string, ETA). The admin form needs a new input for the one it is missing.

**f) Derived vs stored** — state the rule explicitly: counters that reset on a clock boundary
(`ordersToday`, `todayEarnings`) are **derived at read time**, never stored. The driver app already
does this correctly (`dashboard_screen.dart:149-161`); the merchant equivalent does not (audit §11).

**Acceptance:** `SCHEMA.md` is reviewed and merged before any Phase 1 code lands. Every field
currently written by any of the three apps appears in it, either as canonical or as explicitly
deprecated-with-migration-path.

**Estimate:** 1.5 days · **This is the highest-leverage document in the project. Do not rush it.**

---

### P0-05 — Freeze feature work

Announce a change freeze on `main` for the duration of Phases 1–3. Schema migrations and concurrent
feature development on the same files will conflict badly. Bug fixes only, and only with awareness
of the in-flight migration.

**Estimate:** 0 days (process)

---

## Phase 1 — Canonical schema in code

**Goal:** make all three apps speak one language. No behaviour changes beyond correctness; no new
features. This phase is pure alignment, and it resolves the majority of user-visible breakage.

**Duration:** ~7 days · **Depends on:** Phase 0 complete (especially `SCHEMA.md`)

---

### P1-01 — Introduce shared status constants ✅

**Why:** audit §2. Status strings are currently literals scattered across at least a dozen files.
Any fix that leaves them as literals will drift again within a month.

**Files:**
- **New:** `customer_app/lib/models/order_status.dart`
- **New:** `driver_app/lib/models/order_status.dart` (duplicated — see note)
- **New:** `admin_panel/order-status.js`

> **Note on duplication:** these are three separate apps with no shared package today. Creating a
> proper shared Dart package (`packages/shipeast_core`) and adding it as a path dependency to both
> `pubspec.yaml` files is the correct long-term answer and is scheduled as **P6-04**. For Phase 1,
> duplicate the file into both apps with a header comment pointing at `SCHEMA.md` as the source of
> truth, and add a CI check (P1-02) that the two Dart copies are byte-identical. Do not let this
> phase expand into a monorepo restructure.

**Content (Dart):**
```dart
/// Canonical order lifecycle. Source of truth: SCHEMA.md §orders.status
/// This file is duplicated in customer_app and driver_app and verified
/// identical by CI. Edit both, or neither.
abstract final class OrderStatus {
  static const pending    = 'pending';
  static const confirmed  = 'confirmed';
  static const pickedUp   = 'picked_up';
  static const inTransit  = 'in_transit';
  static const delivered  = 'delivered';
  static const cancelled  = 'cancelled';

  /// Non-terminal states: an order here is still someone's responsibility.
  static const active = [pending, confirmed, pickedUp, inTransit];

  /// States in which a driver holds the order.
  static const driverHeld = [confirmed, pickedUp, inTransit];

  static const terminal = [delivered, cancelled];

  /// Legal forward transitions. Mirrored in firestore.rules.
  static const transitions = <String, List<String>>{
    pending:   [confirmed, cancelled],
    confirmed: [pickedUp, cancelled],
    pickedUp:  [inTransit, cancelled],
    inTransit: [delivered, cancelled],
    delivered: [],
    cancelled: [],
  };

  static bool canTransition(String from, String to) =>
      transitions[from]?.contains(to) ?? false;

  /// Customer-facing label. Never show a raw status string in UI.
  static String label(String s) => switch (s) {
    pending    => 'Order Placed',
    confirmed  => 'Driver Assigned',
    pickedUp   => 'Order Picked Up',
    inTransit  => 'On the Way',
    delivered  => 'Delivered',
    cancelled  => 'Cancelled',
    _          => 'Processing',
  };

  /// Zero-based index into the 5-step customer tracker. -1 for cancelled.
  static int step(String s) => switch (s) {
    pending    => 0,
    confirmed  => 1,
    pickedUp   => 2,
    inTransit  => 3,
    delivered  => 4,
    cancelled  => -1,
    _          => 0,
  };
}
```

**Tests (required):** `canTransition` accepts every legal edge and rejects every illegal one
(including all `delivered → *` and `cancelled → *`); `step` and `label` return a sane value for every
canonical status **and** for an unknown string.

**Acceptance:** file exists in both apps, byte-identical, fully unit-tested. No behaviour change yet.

**Estimate:** 0.5 day

---

### P1-02 — CI check: status constants stay in sync ∥

Add to `verify.yml`:
```bash
diff customer_app/lib/models/order_status.dart driver_app/lib/models/order_status.dart \
  || { echo "::error::order_status.dart has diverged between apps"; exit 1; }
```
Retire this check when P6-04 lands the shared package.

**Estimate:** 0.25 day · **Depends on:** P1-01

---

### P1-03 — Customer: fix the live tracking screen ✅

**Why:** audit §2.2 — the tracker freezes on step 0 for the entire delivery.

**File:** `customer_app/lib/screens/order_status_screen.dart`

**Changes:**
1. **Replace `_currentStep`** (lines 33-47) with `OrderStatus.step(status)`. Delete the switch.
2. **Extend the tracker from 4 steps to 5.** `_stepNames` (line 79) and `_stepIcons` (line 86)
   currently have four entries and conflate "Order Confirmed" with "Order Picked Up". New:
   ```dart
   static const _stepNames = ['Order Placed', 'Driver Assigned', 'Picked Up', 'On the Way', 'Delivered'];
   static const _stepIcons = [SeIcons.checkCircle, SeIcons.user, SeIcons.box, SeIcons.bike, SeIcons.home];
   ```
3. **Update `_stepSub`** (line 93) — five cases; the current copy for index 0
   (`'$merchantName accepted your order'`) is wrong even today, since a merchant never accepts
   anything in this system. Correct it to reflect what actually happened.
4. **Update `_buildStepper`** (line 372) — `List.generate(5, …)`, `isLast: i == 4`.
5. **Update `_routeBar`** (line 289) — progress divisor `/ 3` → `/ 4`.
6. **Update `build`** (line 168) — `final delivered = _currentStep == 4;`.
7. **Handle `cancelled` explicitly.** `OrderStatus.step` returns `-1`. Add a dedicated branch that
   renders a distinct terminal state — neutral/danger gradient, "Order Cancelled" heading, the
   cancellation reason if present, and a support CTA. **Do not** fall through to the stepper, and do
   not let `-1` reach `FractionallySizedBox` (a negative `widthFactor` throws).
8. **Fix `_etaLabel`** (line 64) — currently hardcoded `'~40 min'` / `'~25 min'` / `'~15 min'`,
   invented numbers presented to the customer as an estimate. Either derive from the merchant's
   `deliveryTime` and `createdAt`, or remove the ETA pill entirely. **Recommendation: remove it for
   now.** A wrong ETA is worse than no ETA, and the honest-empty-state discipline elsewhere in this
   codebase (audit §16) argues for it. Revisit with the maps work in P5-05.

**Tests (required):** widget test pumping the screen with a mock order at each of the six statuses,
asserting the correct step index is highlighted and the correct label renders. This is the single
most important test in the project — it is the regression that broke the product.

**Acceptance:** driving an order through `pending → confirmed → picked_up → in_transit → delivered`
in staging advances the customer tracker one step per transition, live, without a reload.

**Estimate:** 1 day · **Depends on:** P1-01

---

### P1-04 — Customer: fix order history filtering ✅

**Why:** audit §2.3 — orders vanish from the list mid-delivery.

**File:** `customer_app/lib/screens/order_history_screen.dart`

**Changes:**
1. **Filter** (lines 69-79): `'Active' → OrderStatus.active.contains(status)`,
   `'Completed' → status == OrderStatus.delivered`,
   `'Cancelled' → status == OrderStatus.cancelled`.
2. **`_displayStatus`** (line 81) → delegate to `OrderStatus.label`. Delete the switch, and with it
   the `default: return status` branch that leaks raw `picked_up` strings into the UI.
3. **`_statusColors`** (line 96) → key off `OrderStatus.active` / `delivered` / `cancelled` so new
   statuses inherit sensible colours instead of falling through.

**Tests:** an order in each of the six statuses appears under exactly one tab, and the tab counts sum
to the total.

**Acceptance:** an order in `picked_up` appears under "Active" and never disappears from the list.

**Estimate:** 0.5 day · **Depends on:** P1-01

---

### P1-05 — Driver: adopt canonical statuses and add `in_transit` ✅

**Why:** audit §2.4 — `activeOrderStream`'s `whereIn` is the mechanism by which an admin status
change silently strips a driver of their live delivery.

**Files:** `driver_app/lib/services/driver_firestore_service.dart`,
`driver_app/lib/screens/dashboard_screen.dart`, `pickup_confirmation_screen.dart`,
`delivery_confirmation_screen.dart`, `history_screen.dart`, `earnings_screen.dart`

**Changes:**
1. **`activeOrderStream`** (line 41): `whereIn: OrderStatus.driverHeld` — all three held states, not
   two. This alone fixes the mid-delivery blanking.
2. **`pendingOrdersStream`** (line 29): `isEqualTo: OrderStatus.pending`.
3. **`confirmPickup`** (line 94): write `OrderStatus.pickedUp`, unchanged in value but via constant.
4. **New `startTransit(orderId)`** — writes `in_transit` + `inTransitAt` timestamp. This state has
   never existed; it is what makes the customer's "On the Way" step reachable. Wire it to a new
   button on the pickup-confirmation success path: after confirming pickup, the driver's next action
   is "Start Delivery".
5. **`dashboard_screen.dart:238-246, 523`** — the `status == 'confirmed'` / `'picked_up'` branches
   drive which action card shows. Extend to a three-way: `confirmed` → "Go to Merchant" /
   `picked_up` → "Start Delivery" / `in_transit` → "Confirm Delivery".
6. **`confirmDelivery`** — guard that it only fires from `in_transit` (or `picked_up`, for orders
   created before this change; see P2-05 migration).
7. **`history_screen.dart:50-79, 276`** and **`earnings_screen.dart:41`** — replace literals with
   constants. Behaviour unchanged (`delivered` only), but removes drift risk.

**Tests:** unit test that `driverHeld` covers exactly the states in which a driver-facing action card
must render; widget test of the dashboard's three action states.

**Acceptance:** a driver progresses accept → arrive → pickup → start delivery → deliver, with the
customer tracker advancing in lockstep, and an admin editing the order's status mid-flight does not
blank the driver's screen.

**Estimate:** 1.5 days · **Depends on:** P1-01

---

### P1-06 — Admin: constrain the status dropdown to legal transitions

**Why:** audit §2.4 — the dropdown currently offers all seven statuses unconditionally, including
two (`accepted`, `in_transit`) that no app wrote, one of which broke live deliveries.

**File:** `admin_panel/app.js` — `openOrderPanel` (line 559-564), `saveOrderChanges` (574)

**Changes:**
1. Replace the hardcoded array at line 561 with
   `[o.status, ...OrderStatus.transitions[o.status]]` — the current status plus only its legal
   successors. `accepted` disappears from the vocabulary entirely.
2. Remove `accepted` from `STATUS_TONE` (line 156) and `STATUS_LABEL` (line 159); keep `in_transit`,
   which is now a real state.
3. Add a guard in `saveOrderChanges`: if the selected status is not a legal transition from the
   order's current status, toast an error and abort rather than writing.
4. **Show the driver-side consequence in the UI.** When an admin selects `cancelled` on an order a
   driver is actively holding, the confirm dialog must say so explicitly — "Driver *Marcus* is
   currently delivering this order and will be notified." Use the existing `confirmDialog`.

**Acceptance:** the admin cannot put an order into an illegal state from the UI, and cancelling a
held order warns about the driver first.

**Estimate:** 0.75 day · **Depends on:** P1-01

---

### P1-07 — Admin: fix driver assignment (the black hole) ⚠️

**Why:** audit §3 — the highest-severity operational bug. Manually dispatched orders are invisible
to every driver and are never delivered.

**File:** `admin_panel/app.js` — `saveOrderChanges` (lines 574-593)

**Changes:**
1. **Assigning a driver to a `pending` order must also set `status: 'confirmed'`**, in the same
   write. Without this the order satisfies neither driver query.
2. Convert the blind `updateDoc` into a **transaction** that re-reads the order and refuses if
   another driver has claimed it since the panel last rendered. The driver app already does this
   correctly in `acceptOrder` (`driver_firestore_service.dart:69-91`) — mirror that logic. Two
   admins on two browsers, or an admin racing a driver's Accept tap, currently produce a silent
   last-write-wins steal.
3. Write `assignedBy: auth.currentUser.email` and `assignedAt: serverTimestamp()` for audit trail.
4. **Support unassignment.** The dropdown has a `— Unassigned —` option (line 553) whose value is
   `''`, and the current code's `if(driverId)` guard means **selecting it does nothing at all** —
   silently. Handle it: clear `driverId`/`driverName`/`driverPhone` to `null` and return the order
   to `pending` so it re-enters the available pool.

**Acceptance:** admin assigns a driver → that driver's app shows the order as active within seconds,
with no other action. Admin unassigns → order returns to the available pool and other drivers see
it. Two simultaneous assignments → one succeeds, the other gets a clear "already claimed" toast.

**Estimate:** 1 day · **Depends on:** P1-01, P1-06

---

### P1-08 — Customer: fix driver vehicle fields

**Why:** audit §12 — the customer cannot identify the vehicle arriving at their home.

**Files:** `customer_app/lib/screens/order_status_screen.dart:499-501`,
`driver_app/lib/screens/register_screen.dart`

**Changes:**
1. Customer reads `licencePlate` (British, per `SCHEMA.md` §b) instead of `licensePlate`. Delete the
   `vehicleMake` read — no such field will exist.
2. Add a **Vehicle Make & Model** input to driver registration, writing `vehicleModel`. The admin
   form already has this field (`app.js:664`), so the two registration paths currently disagree —
   this closes that gap too.
3. Make `vehicleModel` and `licencePlate` **required** in driver registration validation. A driver
   without a plate is not identifiable, which is a safety issue, not a data-completeness issue.
4. Backfill existing drivers — see P2-05.

**Acceptance:** the customer's tracking card shows "Toyota Corolla · ABC123" for a newly registered
driver.

**Estimate:** 0.5 day

---

### P1-09 — Remove the client-side seeder ⚠️

**Why:** audit §13 — the customer app writes 15 demo merchants into the live database, and this call
will begin failing silently the moment Phase 2's rules land.

**Files:** `customer_app/lib/screens/home_screen.dart:67`,
`customer_app/lib/services/firestore_service.dart:11-91`

**Changes:**
1. Delete the `seedMerchantsIfEmpty()` call and both seeding methods (~80 lines).
2. Port the seed data to `tools/seed_staging.js` — a Node script using the Admin SDK, run manually
   against **staging only**, writing merchants in the canonical `SCHEMA.md` shape (which also fixes
   the demo data's own `fee`/`deliveryTime` inconsistencies).
3. Audit production for merchants created by the seeder (they are identifiable by their Unsplash
   `imageUrl` and the exact names in `firestore_service.dart:18-34`). Decide per-merchant: keep as
   real data, or delete. Record the decision.

**Acceptance:** the customer app performs zero writes to `merchants` under any circumstance.

**Estimate:** 0.5 day

---

### P1-10 — Phase 1 integration test on staging

Manual end-to-end pass, all three apps, against staging. **This is the gate for Phase 1.**

Scenario matrix (run each; all must pass):
1. Customer places order → appears in admin dashboard and in driver's available pool within 5s.
2. Driver accepts → customer tracker moves to "Driver Assigned"; order leaves other drivers' pools.
3. Driver picks up → customer tracker "Picked Up"; order still in driver's active card.
4. Driver starts transit → customer tracker "On the Way".
5. Driver delivers → customer tracker "Delivered"; rate CTA appears; driver's earnings increment.
6. Order is visible under the correct customer history tab **at every step above**.
7. Admin assigns a driver to a pending order → that driver sees it as active.
8. Admin unassigns → order returns to pool.
9. Admin cancels a held order → driver is warned; customer sees a cancelled terminal state.
10. Two drivers tap Accept simultaneously → exactly one wins, the other sees a clear message.

**Acceptance:** all ten scenarios pass, recorded with screenshots in the phase PR.

**Estimate:** 1 day

---

## Phase 2 — Backend: rules, indexes, functions, migration

**Goal:** the database currently has no committed rules, no indexes, and no server code (audit §7).
Several later fixes are impossible without server code, and everything shipped so far is
unprotected.

**Duration:** ~9 days · **Depends on:** Phase 1 (rules must encode the canonical statuses)

---

### P2-01 — Write `firestore.rules` 🔒 ✅ ⚠️

**Why:** audit §7.1. Today the database is either world-writable or governed by undocumented console
edits. A modified client can rewrite any order's total, read every customer's home address, or
self-approve a driver account.

**File:** **New** `firestore.rules` at repo root, plus `firebase.json` wiring.

**Rules to implement** (each maps to a real, currently-open hole):

| Collection | Rule |
|---|---|
| `users/{uid}` | read/write only `request.auth.uid == uid`. Admins read-only. |
| `users/{uid}/addresses/**` | same as parent. |
| `orders/{id}` — read | `customerId == uid` OR `driverId == uid` OR admin. |
| `orders/{id}` — create | only by the customer, `status == 'pending'`, `driverId == null`, `customerId == uid`. **Server-recompute `total`** (P2-03) or reject client totals outright. |
| `orders/{id}` — update by customer | only `cancelled`, only from `pending`. Nothing else. |
| `orders/{id}` — update by driver | only if `driverId == uid` (or claiming a `pending` order with `driverId == null`), and only along a legal transition from `OrderStatus.transitions`. Cannot touch `total`, `items`, `customerId`. |
| `orders/{id}` — delete | nobody. Cancel, never delete. |
| `drivers/{uid}` — read | self, admin, and the customer of an order this driver is currently delivering (needed by `watchDriver`, `firestore_service.dart:189`). |
| `drivers/{uid}` — write | self, **excluding** `status`, `totalTrips`, `averageRating`, `ratingCount`, `todayEarnings`. **This is critical** — today a driver can write `status: 'approved'` to their own document and bypass admin approval entirely. |
| `drivers/{uid}.status` | admin only. |
| `merchants/**`, `merchants/{id}/menuItems/**` | public read; admin write only. |
| `promoCodes/{code}` | authenticated read; admin write only; `usedCount` server-only (P3-04). |
| `notifications/**` | authenticated read; admin write only. |

**Admin identification:** a custom claim `admin: true`, set by a Cloud Function (P2-04), checked as
`request.auth.token.admin == true`. **Not** an email allowlist in client code, which is trivially
bypassed.

**Tests (required, non-negotiable):** `@firebase/rules-unit-testing` suite in `test/rules/`, run in
CI against the emulator. Minimum cases:
- A driver **cannot** write `status: 'approved'` to their own doc.
- A customer **cannot** modify `total` on their own order after creation.
- A driver **cannot** claim an order already holding another `driverId`.
- A driver **cannot** transition `delivered → pending`.
- A customer **cannot** read another customer's order, address, or profile.
- An unauthenticated client can read `merchants` but not write them.
- An unauthenticated client can read nothing in `orders`.

**Acceptance:** the rules test suite passes in CI, and every case above is covered. Deploy to
staging and re-run P1-10's ten scenarios to confirm rules do not break legitimate flows — **this is
the most common way a rules deploy causes an outage**, so budget for it.

**Estimate:** 2.5 days

---

### P2-02 — Commit `firestore.indexes.json` and `storage.rules` ∥

**Why:** audit §7.2. Two driver queries need composite indexes that exist (if at all) only as
console clicks. A fresh project fails both, surfacing as a misleading "Could not load your active
order" toast.

**Indexes required:**
- `orders`: `status ASC, driverId ASC` (available-orders stream)
- `orders`: `driverId ASC, status ASC` (active-order stream, `whereIn`)
- `orders`: `customerId ASC, createdAt DESC` — **add this and remove the client-side sort** in
  `orderHistoryStream` (`firestore_service.dart:169-179`), which currently pulls every order a
  customer ever placed and sorts in Dart. That is unbounded and will degrade badly.
- `orders`: `driverId ASC, createdAt DESC` — same treatment for
  `driverOrderHistoryStream` (`driver_firestore_service.dart:143-156`).

**Storage rules** (`storage.rules`, new): `users/{uid}/**` self-write; `drivers/{uid}/**` self-write;
`orders/{id}/**` write by the assigned driver only; `merchants/**` admin write, public read. All
paths: public read for images, size cap 5 MB, `contentType` must match `image/*`.

**Acceptance:** deploying to a clean project and running the app produces zero index errors.

**Estimate:** 0.5 day

---

### P2-03 — Bootstrap `functions/` 🔒

**Why:** audit §7.3. Six later items are impossible client-side.

**Steps:** TypeScript Functions package, Node 20, ESLint + Jest, wired into `firebase.json` and CI
(`npm run build` must pass in `verify.yml`). Deploy a trivial healthcheck to prove the pipeline.

**Estimate:** 0.75 day

---

### P2-04 — `setAdminClaim` function 🔒

Callable, itself admin-guarded, with a documented one-time bootstrap (first admin set via a local
Admin SDK script). Required by P2-01's rules.

**Acceptance:** admin panel login works and non-admin accounts are rejected at the rules layer, not
just hidden in the UI.

**Estimate:** 0.5 day · **Depends on:** P2-03

---

### P2-05 — Data migration ⚠️ 🔒

**Why:** every schema decision in Phase 1 leaves legacy documents behind. Without this step, old
orders render as "Processing" forever and old merchants keep their broken fee fields.

**Deliverable:** `tools/migrate/` — idempotent, resumable, dry-run-capable Node scripts. Run against
**staging first**, verified, then production.

| Migration | Action |
|---|---|
| `orders.status: 'accepted'` | → `confirmed` (the dead status, if any exist) |
| `orders` in `picked_up` | leave as-is; drivers can still deliver from it (P1-05.6 allows it) |
| `orders` missing `discount`/`promoCode` | set `discount: 0`, `promoCode: null` |
| `merchants.fee: '$250'` | parse → `deliveryFee: 250` (int); delete `fee` |
| `merchants.hours` | → `openingHours`; set `deliveryTime` to a sensible default and **flag for manual admin review** — the value cannot be derived |
| `merchants.open` | consolidate onto `isOpen`; delete the duplicate (`app.js:841` writes both) |
| `merchants.emoji` | retain; it is customer-app display data with no admin equivalent yet (see P4-02) |
| `promoCodes.discountAmount` | → canonical `discountAmount` + `discountType: 'percent'|'fixed'` normalised |
| `promoCodes.validUntil` (string) | parse → `expiresAt` (Timestamp); null if unparseable, and **log every failure for manual review** |
| `drivers.licensePlate` | → `licencePlate` if any American-spelled docs exist |
| `drivers` missing `vehicleModel` | set `null`; flag for driver to complete at next login |
| **Orphan drivers** (audit §4) | identify docs whose ID is not a valid Auth UID; export to CSV for manual reconciliation. **Do not auto-delete** — some may correspond to real people who need an account created (P4-05). |

**Protocol for the production run:**
1. Full Firestore export immediately before. Verify the export is restorable **by actually
   restoring it into a scratch project** — an untested backup is not a backup.
2. Run with `--dry-run`; review the diff report.
3. Run for real during the lowest-traffic window.
4. Verify with a read-only assertion script.
5. Keep the export for 30 days.

**Acceptance:** post-migration, zero documents in production violate `SCHEMA.md`, verified by an
assertion script that runs clean.

**Estimate:** 2 days

---

### P2-06 — Rollback plan

Document, per phase: how to revert the client (previous APK release + hosting rollback), how to
revert rules (`firebase deploy --only firestore:rules` from the prior tag), and how to restore data
(the P2-05 export). **Rehearse the data restore once on staging.** A rollback plan that has never
been executed is a hypothesis.

**Estimate:** 0.75 day

---

## Phase 3 — Money and data integrity

**Goal:** close the revenue leaks and make admin analytics reflect reality.

**Duration:** ~7 days · **Depends on:** Phase 2

---

### P3-01 — Merchant economics: fee and time ⚠️

**Why:** audit §6.1 — the displayed fee, the charged fee, and the admin-configured fee are three
different numbers.

**Files:** `admin_panel/app.js` (`saveMerchant` 834-856, listener 321-334, `openMerchantModal` 816),
`admin_panel/index.html:456-462`, `customer_app/lib/screens/home_screen.dart:674-682`

**Changes:**
1. Admin writes `deliveryFee` as an **integer** (not `'$'+value`), `deliveryTime` (new input), and
   `openingHours` (the existing "Opening Hours" input, renamed field).
2. **Add the missing "Delivery Time / ETA" input** to the merchant modal — the admin currently has
   no way to set it at all, which is why every merchant shows the hardcoded "25–35 min".
3. Customer reads `deliveryFee` as an int directly. **Delete `_parseDeliveryFee`**
   (`home_screen.dart:148-152`) — regex-scraping a number out of a display string is the root of
   the J$100 phantom charge.
4. Customer renders "Free delivery" when `deliveryFee == 0`, else the formatted amount. Display and
   charge now come from one field.
5. Verify the fee flows correctly through `CartProvider.setMerchant(id, name, fee)`
   (`cart_provider.dart:38`) into checkout and into `placeOrder`.

**Tests:** unit test that a merchant with `deliveryFee: 250` produces an order whose `deliveryFee` is
250 and whose total includes it.

**Acceptance:** admin sets J$250 → customer sees "J$250 delivery" → the order document records 250 →
the total is correct. One number, four places.

**Estimate:** 1.25 days

---

### P3-02 — Order economics: record the discount ⚠️

**Why:** audit §6.2 — orders do not reconcile; `subtotal + fees ≠ total` on any discounted order,
with no field explaining the gap.

**Files:** `customer_app/lib/services/firestore_service.dart:118-162`, `payment_screen.dart:567-609`

**Changes:** add `discount: int` and `promoCode: String?` parameters to `placeOrder`; write both;
keep `total` as the final charged amount but ensure
`subtotal + deliveryFee + serviceFee - discount == total` and **assert it** before writing.
Surface `discount` in the admin order panel (`app.js:547-549`) and in the customer's order detail.

**Acceptance:** every new order reconciles arithmetically. Add a monitoring query that flags any that
do not.

**Estimate:** 0.75 day

---

### P3-03 — Promo codes: one shape, enforced 🔒 ⚠️ ✅

**Why:** audit §5 — every code discounts J$0, never expires, and ignores its usage cap.

**Files:** `admin_panel/app.js` (`createPromo` 1109-1133, listener 336-359),
`customer_app/lib/services/firestore_service.dart:262-274`, `payment_screen.dart:88-125`,
**new** `functions/src/redeemPromo.ts`

**Canonical shape** (per `SCHEMA.md`):
```
{ code, discountType: 'percent'|'fixed', discountAmount: int,
  minOrderTotal: int, maxDiscount: int|null,
  expiresAt: Timestamp|null, maxUses: int, usedCount: int, active: bool }
```

**Changes:**
1. Admin writes exactly this. The date input must produce a `Timestamp`, not a string.
2. Customer reads `discountAmount` (not `discount`) and compares `discountType` against `'percent'`
   (not `'percentage'`). **Both sides were wrong in different ways** — fix both against the schema,
   not against each other.
3. Enforce `expiresAt`, `usedCount < maxUses`, and `minOrderTotal` in `validatePromoCode`.
4. **Cap percentage discounts** with `maxDiscount`. A `100%` code with no cap is an unbounded
   liability, and nothing currently prevents an admin from creating one by typo.
5. 🔒 **Redemption must be server-side.** A callable function validates the code, increments
   `usedCount` transactionally, and returns the authoritative discount. Client-side validation stays
   for instant UI feedback but is **not trusted** — rules make `usedCount` server-only, so the cap
   is real rather than advisory.
6. Admin promo table shows live `usedCount` / `maxUses` with a progress indicator.

**Tests:** expired code rejected; exhausted code rejected; below-minimum order rejected; percentage
capped at `maxDiscount`; concurrent redemption of a code with `maxUses: 1` succeeds exactly once.

**Acceptance:** a J$200-off code applies J$200, stops working at its expiry, and stops working after
its cap — with the admin panel showing accurate usage.

**Estimate:** 1.75 days · **Depends on:** P2-03

---

### P3-04 — Server-side commission and delivery finalisation 🔒

**Why:** audit §6.3 — commission is computed on the driver's device and written straight to their own
earnings field. With `todayEarnings` locked server-only by P2-01, the current client write will
start failing, so this is also a *correctness* dependency, not just hardening.

**Change:** move `confirmDelivery` into a callable function that recomputes commission from the
order's stored `total` using the server's rate, updates order + driver stats atomically, and returns
the result. `DriverPay.commissionOn` stays client-side **for display only**.

Also fixes a latent bug: `confirmDelivery` currently takes `orderTotal` as a **parameter from the
caller** (`driver_firestore_service.dart:109-116`) rather than reading it from the order document —
so the earnings figure depends on what the client passes, not on what the order actually cost.

**Acceptance:** a driver client modified to claim a J$999,999 order cannot inflate their earnings.

**Estimate:** 1 day · **Depends on:** P2-03, P2-01

---

### P3-05 — Derive `ordersToday`; aggregate merchant ratings

**Why:** audit §11 — admin shows `0` orders and `5.0` rating for every merchant, permanently.

**Changes:**
1. **`ordersToday`:** delete the stored field. Derive in `renderMerchants` from the already-loaded
   `orders` array — the data is in memory; no query needed. Follows the rule set in `SCHEMA.md` §f
   and mirrors the driver app's existing correct approach.
2. **Merchant rating:** 🔒 extend the `submitRating` transaction to roll `merchantRating` up into
   `merchants/{id}` (`totalRatings`, `ratingCount`, `averageRating`) exactly as it already does for
   drivers (`firestore_service.dart:293-310`). The customer is already *collecting* this rating and
   throwing it away.
3. **Per-star breakdown:** add `ratingCounts: {1..5}` increments to the same transaction, populating
   the admin's driver panel (`app.js:735-750`), which correctly shows an honest empty state today
   and will simply start working.

**Acceptance:** admin merchant list shows real order counts and real ratings; the driver rating
histogram renders from real data.

**Estimate:** 1.25 days · **Depends on:** P2-03

---

### P3-06 — Money formatting audit ∥

Sweep all three apps for ad-hoc formatting. `customer_app` has `_formatPrice` duplicated in at least
`checkout_screen.dart:83` and `payment_screen.dart:75` — and it is **subtly wrong**: it only inserts
one separator, so J$1,234,567 renders as "1234,567". The driver app already solved this properly in
`Money.plain` (`driver_constants.dart`). Port that to the customer app, delete both `_formatPrice`
copies, and confirm the admin's `money()` handles the same cases.

**Acceptance:** a J$1,234,567 order renders identically and correctly in all three apps.

**Estimate:** 0.75 day

---

## Phase 4 — The requested features

**Goal:** deliver image upload and working push — the two capabilities explicitly asked for that do
not exist at all today.

**Duration:** ~9 days · **Depends on:** Phase 2 (Storage rules, Functions)

---

### P4-01 — Admin image upload: merchants

**Why:** audit §8. The explicit ask. Today `index.html:462` is a text field expecting a pasted URL,
and `app.js` does not import `firebase-storage` at all.

**Files:** `admin_panel/app.js` (imports at line 6-8; `saveMerchant` 834), `index.html:462`,
`styles.css`

**Build:**
1. Import `getStorage, ref, uploadBytesResumable, getDownloadURL, deleteObject`.
2. Replace the URL input with a **dropzone component**: click-to-browse + drag-and-drop, thumbnail
   preview, "Replace"/"Remove" actions, and a determinate progress bar driven by
   `uploadBytesResumable`'s `state_changed` events.
3. **Client-side pre-processing before upload** — this is what separates a working feature from a
   slow one. Draw to `<canvas>`, resize to max 1600×800, re-encode as JPEG q0.82, and reject
   anything still over 5 MB. Merchant photos come from phone cameras; unprocessed, they are 4–8 MB
   each and will make the customer's home screen unusable on Jamaican mobile data.
4. Validate: `image/jpeg|png|webp` only, 5 MB cap, minimum 800×400 with a warning below that.
5. Upload to `merchants/{merchantId}/cover_{timestamp}.jpg`. **Timestamped, not fixed-name** — a
   fixed name means the CDN serves the stale image after replacement, and cache-busting query params
   are a worse fix than a new path.
6. On successful upload, write the download URL to `imageUrl` — **the customer app needs no change**,
   since it already reads `imageUrl` (`home_screen.dart:661`).
7. Delete the previous object on replace, and on merchant delete, so Storage does not accumulate
   orphans. Wire into `deleteMerchant` (`app.js:857`).
8. **Keep the URL field** as a secondary "or paste a URL" option — existing merchants depend on it,
   and removing it would strand them.
9. Handle the new-merchant case: there is no `merchantId` until the document is created. Either
   create the doc first then upload, or upload to a temp path and move. **Recommend: create the
   merchant document first, then enable the upload zone** — simpler, and gives the admin a natural
   two-step flow.
10. Accessibility: keyboard-operable (the dropzone must be a real `<button>`/`<input type=file>`,
    not a `<div>` with a click handler), `aria-live` progress announcements, visible focus ring.
    The admin panel's existing a11y discipline (audit §16) sets this bar.

**Acceptance:** an admin drags a 6 MB phone photo onto the merchant form; it compresses, uploads with
visible progress, previews, saves, and appears in the customer app's merchant list within seconds.
Replacing it removes the old object.

**Estimate:** 2.5 days

---

### P4-02 — Admin image upload: menu items ∥

Same component, applied to the menu-item form (`app.js:930`, built inside `loadMenuItemsTab`).
Path `merchants/{mid}/menuItems/{itemId}_{timestamp}.jpg`. Smaller target (800×600 — these render as
thumbnails in `merchant_menu_screen.dart:397-420`).

Factor the dropzone from P4-01 into a reusable `createUploader(opts)` rather than copy-pasting —
`app.js` is 1,463 lines of plain ES modules and duplicating ~150 lines of upload logic will hurt.

**Also:** add an **emoji picker** to the merchant form. `emoji` is customer-facing display data
(`home_screen.dart:674`) that the admin currently has no way to set, so admin-created merchants fall
back to a generic 🍽️ while seeded ones have bespoke icons.

**Estimate:** 1.25 days · **Depends on:** P4-01

---

### P4-03 — Customer app: initialise FCM 🔒

**Why:** audit §9. `firebase_messaging: ^15.0.0` is declared in `pubspec.yaml:44` and **not one line
of the customer app uses it.** Customers cannot receive a push under any circumstance.

**Files:** `customer_app/lib/main.dart`, `firestore_service.dart`, **new**
`customer_app/lib/services/notification_service.dart`

**Build:** mirror the driver app's working setup (`driver_app/lib/main.dart:41-62`) — background
handler, permission request, token persistence to `users/{uid}.fcmToken`, `onTokenRefresh`,
foreground handler surfacing an in-app `SeToast`, and `onMessageOpenedApp` deep-linking to the
relevant order.

**Critical detail:** request notification permission **contextually** — after the first order is
placed, framed as "get told when your driver is on the way" — not on first launch. iOS gives exactly
one chance at this prompt; spending it on a cold launch to an unknown app produces a permanent
denial for a large share of users.

Also: persist the token on **login**, not just at startup, and **clear it on logout**, or the next
user of that device receives the previous user's order notifications.

**Estimate:** 1.25 days · **Depends on:** P2-03

---

### P4-04 — Notification fan-out functions 🔒

**Why:** audit §9. The driver app dutifully collects `fcmToken` and **nothing has ever sent to it**.
The admin's "Log Notification" button writes a Firestore doc that only the customer app reads, so
selecting "All Drivers" delivers to nobody.

**Build** (`functions/src/notifications.ts`):

| Trigger | Sends to | Message |
|---|---|---|
| `onCreate notifications/{id}` | token set per `target` (`customers`/`drivers`/`all`) | admin broadcast — **fixes the "All Drivers" dead end** |
| `onCreate orders/{id}` | all online, approved drivers | "New order · J$X · 2.3 km" — **this is the one that matters most** |
| `onUpdate orders/{id}` status change | the order's customer | per-status copy from `OrderStatus.label` |
| `onUpdate orders/{id}` → `cancelled` | assigned driver, if any | "Order cancelled by admin" |
| `onUpdate drivers/{uid}` status change | that driver | approved / rejected |

**Why the order-create trigger is the priority:** today a driver only discovers orders while the app
is **foregrounded and toggled online** (`dashboard_screen.dart:205-220`). A driver with the phone in
their pocket misses every order. For a delivery product that is a fundamental gap, not polish.

**Details:** use topics for broadcasts and token multicast for targeted sends; prune invalid tokens
on `messaging/registration-token-not-registered`; batch at 500; make handlers idempotent (Functions
guarantee at-least-once, so a retry must not double-send); include `orderId` in the data payload for
deep-linking.

**Estimate:** 2 days · **Depends on:** P4-03, P2-03

---

### P4-05 — Admin-initiated driver provisioning 🔒

**Why:** audit §4 — `addDoc` creates a random-ID document with no Auth account. That driver can never
log in, and self-registering later creates a duplicate ghost.

**Interim (do this in Phase 1 if possible):** hide the "Add Driver" button and rely on
self-registration + admin approval, which works correctly today.

**Proper fix:** callable `createDriverAccount({email, name, phone, vehicle…})` that creates the Auth
user via Admin SDK, writes `drivers/{uid}` with `status: 'pending'`, and emails a password-reset link
as the onboarding invite. Restore the admin button pointing at it.

**Also:** reconcile the orphan documents exported in P2-05 — for each, either create a matching Auth
account or delete the row.

**Acceptance:** an admin adds a driver by email; that person receives an invite, sets a password,
signs in, and lands on the pending-approval screen with their profile already populated.

**Estimate:** 1.25 days · **Depends on:** P2-03, P2-04

---

## Phase 5 — Product completeness

**Goal:** close the gaps where the product claims to do something it does not.

**Duration:** ~8 days · **Depends on:** Phase 3

---

### P5-01 — Make Packages real ⚠️

**Why:** audit §10 — the most serious *honesty* defect in the codebase. `home_screen.dart:287-298`
validates the form, shows **"Package request submitted! We'll contact you shortly,"** and writes
nothing. No record exists. Nobody will contact them. This is reachable from one of four top-level
home categories.

**Build:** write a real order with `type: 'package'`, the pickup/delivery addresses, weight, packing
flag, and instructions; price it (flat rate by weight band, defined in a new `settings/pricing`
document the admin can edit); route it through the normal `pending → delivered` lifecycle so drivers
and admin handle it with existing machinery. Add a `type` badge to the admin order table and to the
driver's order card so a package job is visually distinct from a food delivery.

**If this cannot be built now, remove the entry point.** Shipping a success toast for an action that
did not happen is worse than shipping a "Coming soon" state — and this codebase already has a
`coming_soon_screen.dart` for exactly that purpose.

**Estimate:** 2.5 days

---

### P5-02 — Make Overseas real, or gate it

`overseas_order_screen.dart` contains **zero** Firestore writes. Same decision as P5-01. Given
overseas shipping involves customs, dimensional weight, and carrier integration, **recommend gating
it behind `coming_soon_screen.dart` with an email-capture** and scheduling it as a separate project.
Do not half-build it.

**Estimate:** 0.5 day (gate) or ~10 days (build — out of scope for this plan)

---

### P5-03 — Customer order cancellation ✅

**Why:** audit §15 — the customer app renders a "Cancelled" tab and a cancelled badge, but **no
customer action can ever produce that state.**

**Build:** a "Cancel Order" action on the tracking screen, visible only while `status == 'pending'`,
behind a confirmation sheet with a reason picker. Writes `cancelled`, `cancelledAt`, `cancelledBy`,
`cancellationReason`. Rules (P2-01) already restrict customers to this exact transition.

Handle the downstream consequences that currently have no path: notify the assigned driver (P4-04);
render the terminal cancelled state correctly (P1-03.7); define refund handling for prepaid orders
(for COD-only today, this is a no-op — **document that explicitly** so it is not forgotten when card
payments land).

**Estimate:** 1.25 days

---

### P5-04 — Live approval revocation ✅

**Why:** audit §14 — an admin who suspends an active driver does not remove them. The driver keeps
receiving and accepting orders until they happen to force-quit. For a safety-triggered suspension
that is a serious control failure.

**Fix:** `DashboardScreen`'s existing driver-document listener (`dashboard_screen.dart:85`) already
streams the document but reads only `isOnline` (line 90). Also read `status`; if it leaves
`approved`, force-navigate to `PendingApprovalScreen` and cancel all order subscriptions. Handle the
in-flight case explicitly: a driver holding an active order at suspension time must be told what to
do with the goods, not silently ejected mid-delivery.

The reverse direction is already correct (`pending_approval_screen.dart:49-54`) — mirror its pattern.

**Estimate:** 0.75 day

---

### P5-05 — Admin: Customers page

The `users` collection has **no admin surface at all** — an admin can see an order but cannot look up
the customer who placed it, their history, or their addresses. Add a Customers page matching the
existing Drivers/Merchants pattern: searchable table, detail side-panel with order history and
lifetime value, and the ability to disable an account.

Note this expands the admin's data access, so P2-01's `users` read rule must permit admin reads —
confirm that landed.

**Estimate:** 2 days

---

### P5-06 — Admin: order detail completeness ∥

The order side panel (`app.js:501-568`) omits data the order document already carries: `discount` and
`promoCode` (after P3-02), `deliveryPhotoUrl` and `deliveryNote` (written by
`driver_firestore_service.dart:121-122` and **never displayed anywhere** — proof of delivery is
captured and invisible), timestamps for each transition, and the cancellation reason. Add all of
them.

**Estimate:** 1 day

---

## Phase 6 — Hardening, verification, launch

**Duration:** ~10 days · **Depends on:** Phases 1–5

---

### P6-01 — Automated test suite ✅

Bring both apps to meaningful coverage. Priority order, by risk:
1. `OrderStatus` transitions (P1-01) — pure logic, highest value per line.
2. Order tracking screen at all six statuses (P1-03) — the regression that broke the product.
3. Order history filtering (P1-04).
4. Promo validation (P3-03) — all rejection paths.
5. Money formatting (P3-06) — boundary values, especially the millions case that is wrong today.
6. Cart arithmetic (`cart_provider.dart`) — currently untested.
7. Rules suite (P2-01) — already required there.
8. Functions unit tests, emulator-based.

**Replace `driver_app/test/widget_test.dart`**, which asserts `expect(true, isTrue)` and tests
nothing while appearing in CI as a passing test. That is worse than having no test, because it
reports false confidence.

**Target:** 60% line coverage on `lib/services`, `lib/providers`, `lib/models`. Do not chase a
coverage number on widget code.

**Estimate:** 3 days

---

### P6-02 — Clear the analyzer baseline ∥

Fix the P0-02 baseline findings, then flip `verify.yml` to `--fatal-infos`. Add `very_good_analysis`
or tighten the existing `flutter_lints` ruleset.

**Estimate:** 1 day

---

### P6-03 — Performance and cost review

- **Unbounded queries.** `orderHistoryStream` and `driverOrderHistoryStream` fetch every order ever,
  forever, and sort client-side. Paginate (`limit(20)` + cursor). Left alone, a driver with 2,000
  deliveries re-downloads all of them on every dashboard open — a real cost and battery problem.
- **`unreadNotificationsCountStream`** (`firestore_service.dart:394-408`) does a **full collection
  read of `notifications` on every user-document change**, via `asyncMap`. Replace with a counter or
  a `where('createdAt', '>', readAt)` query.
- **Admin `orders` listener** caps at 200 (`app.js:265`) — fine for now, but analytics computed from
  a truncated window will silently under-report as volume grows. Move aggregates server-side before
  that bites.
- Image caching: confirm `cached_network_image` is used on every remote image after P4-01/02.
- Cold-start time; frame timings on the merchant list.

**Estimate:** 1.5 days

---

### P6-04 — Extract the shared package

Create `packages/shipeast_core` with the status enum, money formatting, and order/driver/merchant
model classes; add as a path dependency to both apps; retire the P1-02 duplication check. Deferred to
here deliberately — doing it during Phase 1 would have coupled a risky refactor to an urgent fix.

**Estimate:** 1.5 days

---

### P6-05 — Accessibility and visual QA ⚠️

**This is the pass the audit could not perform.** Requires real devices.

- Both apps at 200% font scale (`textScaleFactor`), small (5") and large (6.7") screens — the audit
  flagged several fixed-height containers that are likely to overflow.
- TalkBack/VoiceOver on the customer's order flow and the driver's accept flow.
- Contrast audit against WCAG AA, both light and dark themes. Note `themeMode: ThemeMode.light` is
  hardcoded in `customer_app/lib/main.dart:67` — a `darkTheme` is defined and **can never be
  reached**. Decide: wire up the toggle, or delete the dead theme.
- Admin panel: keyboard-only traversal, screen reader on the tables, 320px-wide mobile.
- Reduced-motion honoured everywhere (the admin already does this well).

**Estimate:** 2 days

---

### P6-06 — Security review

Full pass over rules with an adversarial mindset; verify no secrets beyond the (safe, once rules
exist) Firebase config; confirm Storage rules reject oversized and non-image uploads; penetration-test
the callable functions for missing auth guards; confirm PII handling (customer addresses, driver
licence numbers) is defensible.

**Estimate:** 1 day

---

### P6-07 — Production launch

1. Full backup and verified restore rehearsal.
2. Deploy rules + indexes + functions to prod.
3. Run P2-05 migration (dry-run, review, execute, assert).
4. Deploy the admin panel.
5. Release both APKs.
6. **Re-run the P1-10 ten-scenario matrix against production** with real devices and a real order.
7. Monitor for 48 hours: Crashlytics, Functions errors, rules-denial rate (**a spike here means a
   legitimate flow is blocked** — the single most likely launch failure), Firestore cost.

**Estimate:** 1 day + 2 days monitoring

---

## Critical path and sequencing

```
Phase 0 ──▶ Phase 1 ──▶ Phase 2 ──▶ Phase 3 ──▶ Phase 4 ──▶ Phase 5 ──▶ Phase 6
(4d)        (7d)        (9d)        (7d)        (9d)        (8d)        (10d)
```

**Hard dependencies that cannot be reordered:**
- `SCHEMA.md` (P0-04) precedes every code change. Skipping it re-creates the root cause.
- Canonical statuses (P1-01) precede the rules (P2-01), which encode legal transitions.
- Functions bootstrap (P2-03) precedes every 🔒 item.
- Rules (P2-01) precede server-side commission (P3-04) — the rules make the client write fail, so
  they must land together or in that order.
- Migration (P2-05) must follow every schema decision in Phases 1 and 3. **If Phase 3 changes a
  field shape after migration runs, migration runs again.** Budget for that.

**Parallelisation (two developers):**
- **Track A (backend):** P0-01 → P2-01 → P2-02 → P2-03 → P2-04 → P3-03 → P3-04 → P4-04 → P4-05
- **Track B (client):** P0-02/03 → P1-03 → P1-04 → P1-05 → P1-08 → P3-01 → P3-06 → P4-01 → P4-02
- Both converge at P1-10 and again at P6-07. P0-04, P1-01, and P2-05 are shared and should be
  written jointly.

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Rules deploy blocks a legitimate flow | **High** | Outage | Emulator test suite (P2-01); re-run P1-10 on staging post-deploy; monitor denial rate; rehearsed rollback |
| Migration corrupts production data | Medium | **Severe** | Dry-run; **restore-verified** backup; staging rehearsal; idempotent scripts; assertion pass |
| Old APKs stay in the field after schema change | **High** | Data inconsistency | Both directions of the migration must tolerate old and new clients for one release cycle. **Do not treat the migration as atomic with the client release** — users update on their own schedule, and sideloaded APKs (which is how this ships today) may never update at all. Consider a forced-upgrade check. |
| Orphan driver reconciliation loses a real person | Medium | High | Never auto-delete; export to CSV; manual review (P2-05) |
| Phase 3 changes a field after P2-05 ran | Medium | Medium | Sequence P3-01/02/03 schema decisions **into** `SCHEMA.md` during Phase 0, not during Phase 3 |
| iOS push permission spent on a cold launch | Medium | High | Contextual prompt (P4-03) — one chance per install |
| Scope creep into a monorepo restructure | **High** | Schedule | P6-04 is explicitly deferred; P1-01 duplicates deliberately |

---

## Definition of done

Ship when **all** of these hold:

1. All ten P1-10 scenarios pass on production hardware against production Firebase.
2. `flutter analyze` clean, `flutter test` green, rules suite green, functions tests green — all
   enforced in CI on every PR.
3. Zero production documents violate `SCHEMA.md`, verified by assertion script.
4. An admin can create a merchant **with an uploaded photo**, add menu items **with uploaded
   photos**, set a delivery fee, and see all of it reflected in the customer app within seconds —
   the original ask, end to end.
5. A backgrounded driver receives a push for a new order.
6. A customer receives a push at each status transition.
7. No screen in any app claims an action succeeded that did not write to the database.
8. Rollback rehearsed at least once.
9. 48 hours of clean monitoring post-launch.

---

## What this plan deliberately excludes

Called out so they are decisions rather than oversights:

- **Live driver GPS tracking and maps.** The customer tracking screen honestly declines to fake a map
  today (audit §16). Real tracking needs location permissions, background location, a maps SDK, and
  route ETA — a project in its own right. `_etaLabel` is removed in P1-03 rather than faked.
- **Card/PayPal payments.** `payment_screen.dart:23` hardcodes PayPal as disabled. COD-only is a
  coherent product for this market. Adding card payments brings PCI scope and belongs in its own plan.
- **In-app chat** between customer and driver. `tel:` calling works today (`order_status_screen.dart:448`).
- **Merchant-facing app.** Merchants have no login; the admin manages them. A merchant portal is a
  fourth app.
- **iOS release.** Both apps have iOS runners, but CI builds only Android APKs. iOS requires signing,
  App Store review, and its own push certificates.
- **Multi-language / i18n.** All copy is hardcoded English.
- **Overseas ordering** (P5-02) — gated, not built.

Each is a legitimate future phase. None blocks a correct, honest v1.
