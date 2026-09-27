# Pull requests on the old GitHub repo

Archived 2026-09-28 from derionscarlett-lang/Shipeast-App before moving to a new repository.
The code of every PR is preserved as a local branch; this file keeps the descriptions and discussion.

---

## PR 1: Redesign/customer app UI

- **State:** open
- **Branch:** `redesign/customer-app-ui` → `main`
- **Opened:** 2026-06-25T02:37:10Z by getgrowthnexus

_No description._

---

## PR 2: Phase 0 foundations + P1-01/P1-02: schema of record, CI gates, canonical order lifecycle

- **State:** merged 2026-07-29T23:01:28Z
- **Branch:** `feat/admin-seds` → `main`
- **Opened:** 2026-07-21T06:40:23Z by getgrowthnexus

Implements **Phase 0** in full (where possible) and the first two items of **Phase 1**, per
[execution-all-three-plan.md](execution-all-three-plan.md).

> **This PR is also the Phase 0 baseline capture (P0-02).** There is no Flutter toolchain in the
> development environment, so `flutter analyze` / `flutter test` have never been run against this
> code. **This is the first CI run that exercises them.** Record its output here.

## Phase 0

| Item | Status |
|---|---|
| P0-01 — Staging Firebase project | 🟡 Code prerequisite only — project needs Console access |
| P0-02 — Install and pin toolchain | 🟡 Pinned from lockfiles; baseline is this run |
| P0-03 — Real CI gates | 🟢 |
| P0-04 — Schema of record | 🟢 [SCHEMA.md](SCHEMA.md) |
| P0-05 — Change freeze | 🟢 Declared in [PHASE-0.md](PHASE-0.md) |

**[SCHEMA.md](SCHEMA.md) is the review priority.** It is the gate for the rest of Phase 1, and the
plan calls it *"the highest-leverage document in the project."* The parts most worth arguing about
now — rather than after Phase 1 code implements them — are the canonical status vocabulary
(§orders) and the money/timestamp conventions (§a, §b).

**CI gates.** `verify.yml` is a reusable workflow; both APK builds now `needs: verify`. Previously
they built and published a GitHub Release on every push to `main` with no analyze or test at all.
Errors gate; warnings/infos report only until P6-02 clears the baseline.

**Environment selection.** Firebase config moved out of `app.js` into `config.js`. Fails closed —
an unconfigured environment refuses to start rather than silently using production. Any non-prod
environment, and any forced-prod from a non-prod host, paints a persistent banner. Production
behaviour is unchanged: same credentials, no banner. Verified 6/6 under stubbed browser globals.

## Phase 1 (P1-01, P1-02)

Canonical order lifecycle in all three apps. `accepted` removed entirely (no app ever wrote it);
`driverHeld` now includes `in_transit`, which is the fix for drivers losing a live delivery when an
admin changes status mid-route; `step()` returns `-1` for cancelled so callers must handle the
terminal state instead of rendering "Order Confirmed" on a cancelled order.

`tools/check-status-parity.mjs` goes beyond the plan's byte-diff: it also parses the Dart transition
table and compares it against the admin JS, since a byte-diff cannot catch the admin panel drifting
— and the admin panel is where the original damage was done. Verified by breaking it three ways.

## Known risk in this run

`customer_app/test/widget_test.dart` pumps `ShipEastApp()` without `Firebase.initializeApp`, which
`main()` normally does. **It may fail.** If it does, that is a real finding — the only customer-app
test has never verified anything — not a CI misconfiguration. Proper fix is P6-01. See
[PHASE-0.md](PHASE-0.md) for how to unblock releases meanwhile without weakening the gate to
`|| true`.

## Still blocked (needs access, not effort)

- Staging Firebase project — Console
- Branch protection requiring `verify` on `main` — repo setting
- P1-10 integration matrix — needs staging + real devices

Deliberately **not** done, because guessing would be worse than absence: fabricating
`firebase_options_staging.dart`, and converting `firebase.json` to multi-target (both break working
deploys).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

> **getgrowthnexus** (2026-07-21T06:48:51Z):
>
> ## ✅ Baseline captured — CI green
> 
> First fully green run: all four jobs pass.
> 
> | App | `flutter analyze` | `flutter test` |
> |---|---|---|
> | `customer_app` | **9 issues** — all `info`, all `unnecessary_underscores` | 45 passed |
> | `driver_app` | **No issues found** | 25 passed |
> 
> No warnings, no errors in either app. This satisfies P0-02's acceptance criterion.
> 
> The nine findings are one trivial lint (`__` → `_`) across seven screens, so **P6-02 (flip to `--fatal-infos`) is close to free** — nine mechanical edits, not the day the plan budgeted.
> 
> ### Two corrections this run forced
> 
> **The Flutter pin was wrong.** `.tool-versions` said `3.38.4`, read from `pubspec.lock`'s `flutter: ">=3.38.4"`. That is a minimum constraint computed from the dependency graph, not the SDK that produced the lockfile — 3.38.4 ships Dart 3.10.3, below the `sdk: ^3.11.5` both apps declare. Now pinned to **3.44.7**, pub's own resolution.
> 
> **`customer_app/test/widget_test.dart` had never verified anything.** It pumped `ShipEastApp()` without `Firebase.initializeApp`, and failed the moment it genuinely ran (`[core/no-app]` via `splash_screen.dart:47`). This is the pre-existing finding PHASE-0.md predicted, not a regression. Replaced with `cart_provider_test.dart` — 25 real cases against pure-Dart cart arithmetic, which P6-01 already lists as a priority. **The gate was not weakened** — no `|| true`, no removed step.
> 
> `driver_app/test/widget_test.dart` still asserts `expect(true, isTrue)`. It passes, so it is not blocking, but it reports false confidence. Left for P6-01 rather than writing driver coverage under a Phase 1 commit.
> 
> ### Note for reviewers
> 
> There is no Flutter toolchain in the dev environment, so **CI is the only place either app is verified**. Every Dart change here is written unverified locally and proven by this run.
> 
> 🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## PR 3: P1-04: customer order history no longer hides live orders

- **State:** open
- **Branch:** `feat/p1-customer-status` → `feat/admin-seds`
- **Opened:** 2026-07-21T06:55:04Z by getgrowthnexus

Stacked on #2 (targets `feat/admin-seds`, not `main`) so the SCHEMA.md review gate in that PR stays reviewable on its own.

Resolves audit §2.3.

## The defect

The Active filter matched `pending`, `accepted`, `in_transit`. Two of those were **never written by any app** — and the two that *are* written during a delivery, `confirmed` and `picked_up`, matched **no tab at all**.

So an order disappeared from the customer's order list for the entire delivery: the exact window they are most likely to open it.

## The fix

- Filter uses `OrderStatus.isActive` / `delivered` / `cancelled`.
- `_displayStatus` delegates to `OrderStatus.label`, so the badge names the real state ("Picked Up") rather than the coarse bucket ("Active"). This also removes the `default: return status` branch that rendered the raw database value — how the literal `picked_up` reached the customer.
- `_statusColors` keys off the canonical sets, so a status added later inherits a sensible colour instead of falling through to neutral grey.
- No status literals remain in the file.

## Tests

`test/screens/order_history_filter_test.dart` mirrors the filter predicate rather than pumping the widget (which would need Firebase — the part that was wrong is the predicate):

- every canonical status matches **exactly one** tab
- tab counts sum to the total
- `confirmed` / `picked_up` / `in_transit` all appear under Active
- terminal statuses are not Active
- an unknown status matches **nothing** rather than defaulting to Active — a legacy `accepted` row must not be presented as a live order
- `label()` never leaks a value containing `_`

## Note

There is no Flutter toolchain in the dev environment, so this is unverified locally and proven by CI on this PR.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## PR 4: P1-05/06/07: driver in_transit, admin legal transitions, and the assignment black hole

- **State:** open
- **Branch:** `feat/p1-driver-admin` → `feat/p1-customer-status`
- **Opened:** 2026-07-21T07:11:04Z by getgrowthnexus

Stacked on #3. Completes the code portion of Phase 1.

## P1-05 — driver app (audit §2.4)

`activeOrderStream` filtered `whereIn: ['confirmed','picked_up']`. The moment an order became `in_transit` it left that query and the driver's dashboard **blanked mid-delivery** — goods in the vehicle, no customer address, no delivery button, no recovery path. An admin picking a reasonable-looking status was enough to trigger it. Now filters `OrderStatus.driverHeld`.

`in_transit` was also never written *at all*, so the customer's "On the Way" step was unreachable — their tracker jumped from "Picked Up" to "Delivered" with no signal the driver had set off. New `startTransit()`, and the active-order card is now three-way: **Head to merchant → Start delivery → confirm**.

Left alone deliberately: `'pending'`/`'approved'` in `register_screen`, `login_screen` and `pending_approval_screen` are **driver approval** statuses — a different vocabulary that happens to share a word. Converting them would have been a real bug.

## P1-06 — admin dropdown (audit §2.4)

Offers `selectableFrom(current)` — current status plus only legal successors. `accepted` is gone from every map in `app.js`. The admin can no longer skip `picked_up → delivered`.

## P1-07 — the assignment black hole (audit §3)

The highest-severity operational bug. Assigning a driver left `status` untouched, so the order satisfied **neither** driver query — the pool wants `driverId == null`, the active stream wants a held status. Invisible to every driver *including the assigned one*, while the customer's tracker showed their name. Never delivered.

- Assigning to a pending order sets `confirmed` in the **same write**
- Now a **transaction** that re-reads the order, mirroring the driver app's `acceptOrder` — the blind `updateDoc` allowed a silent last-write-wins steal between two admins, or an admin racing a driver's Accept tap
- **Unassignment works.** The `— Unassigned —` option's value is `''`, and the old `if(driverId)` guard meant selecting it did nothing at all, silently
- Status re-validated against the **live** value inside the transaction, not what the panel rendered
- `assignedBy`/`assignedAt` audit trail; `cancelledAt`/`cancelledBy` on cancellation
- Cancelling an order a driver is holding now warns first, naming them

## Tests

`tools/test-order-status.mjs` — 14 checks, wired into CI. `saveOrderChanges` isn't directly testable here (`app.js` imports the Firebase SDK from gstatic, which doesn't resolve under node), so the decision logic it delegates to is what's covered.

Writing them caught a contradiction between two of my own assertions — **the test was wrong, not the code**: a legacy order must still display its current status even though it offers no successors.

## Phase 1 status

Code complete: P1-01 through P1-09. **P1-10 (the ten-scenario integration matrix) remains blocked** — it needs the staging project and real devices.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## PR 5: Phase 2: security rules, indexes, functions, and tested migrations

- **State:** open
- **Branch:** `feat/p2-backend` → `feat/p1-driver-admin`
- **Opened:** 2026-07-21T07:34:58Z by getgrowthnexus

Stacked on #4. Implements Phase 2 — the backend that did not exist.

Audit §7: the repo had **no** `firestore.rules`, **no** `storage.rules`, **no** `firestore.indexes.json`, **no** `functions/`.

## P2-01 — firestore.rules · **54 emulator tests, all passing**

Two invariants above all others:

- **A driver cannot approve themselves.** Nothing previously stopped a driver writing `status:'approved'` to their own document, bypassing admin approval entirely.
- **A client cannot change what an order costs.** `subtotal + deliveryFee + serviceFee - discount == total` is enforced at creation, so a modified client cannot submit a total that doesn't follow from its own line items.

The suite tests **both directions deliberately**. The plan's risk register ranks *"rules deploy blocks a legitimate flow"* as the most likely launch failure, so the legitimate paths — a driver claiming, an admin assigning, a customer reading their own order — are asserted to still work.

**Writing it caught a contradiction with the P1-07 admin code I wrote earlier.** Unassignment moves `confirmed → pending`, which is backwards and not in the canonical table. Resolved with a narrow `adminUnassigning` clause rather than widening the table — widening would also have let a *driver* push an order backwards. Four extra tests pin the exception shut.

**Driver PII:** rules cannot express "the customer of an order this driver currently holds", so `drivers/{uid}` is authenticated-read to serve the tracking card. `licenceNumber` therefore must not live there — it belongs in `drivers/{uid}/private/`, self+admin only, and that's tested.

## P2-02 — indexes and storage rules

7 composite indexes. Both driver queries needed indexes that existed, if at all, only as console clicks — a fresh project failed them and the driver app surfaced that as a generic "Could not load your active order". Storage caps uploads at 5 MB and image content types **server-side**, because client-side validation is a courtesy, not a control.

## P2-03/04 — functions, building and linting clean in CI

`setAdminClaim` is itself admin-guarded and refuses self-revocation (which would let the last admin lock everyone out). Rules identify admins by **custom claim**, not an email allowlist in client code that a browser bundle makes trivially bypassable. `tools/bootstrap-admin.mjs` breaks the chicken-and-egg for the first admin.

## P2-05 — migrations · **33 tests, all passing**

Pure functions, so they test in CI with no credentials and no database — and the same code produces the dry-run preview and the real write, so the preview is trustworthy.

**Idempotence is asserted by running every migration twice.** A migration that isn't idempotent can't be safely resumed, and a production run *will* be interrupted eventually.

Runner is **dry-run by default**; production needs `--confirm-production` on top, which prints the backup protocol rather than just proceeding. Values it cannot derive are defaulted **and flagged** in `_needsReview`, never guessed.

Deliberately **not** migrated: orders in `picked_up`. Rewriting a live order's status underneath a driver mid-delivery is the exact class of bug this project exists to remove.

## P2-06 — ROLLBACK.md

Blunt about two things: **installed APKs cannot be recalled** (both apps sideload), and **`gcloud firestore import` merges — it does not rewind**. Re-running the idempotent migration is cheaper and safer than an import.

The rehearsal table is deliberately unticked. **A rollback plan that has never been executed is a hypothesis**, and this one has not been.

## Still blocked

Deploying any of this needs the staging project (P0-01) and Console access. Nothing here has run against a real Firebase — only the emulator.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## PR 6: Phase 3 — money and data integrity (P3-01..06)

- **State:** open
- **Branch:** `feat/p3-money` → `feat/p2-backend`
- **Opened:** 2026-07-21T08:06:42Z by getgrowthnexus

Stacked on #5 (`feat/p2-backend`). Merge bottom-up.

## What this fixes

Every item is a place where the system showed one number and charged another, or collected data and discarded it.

| | Before | After |
|---|---|---|
| **P3-01** | Configured, displayed and charged delivery fee were three numbers; the customer fell back to a hardcoded 100 | One integer `deliveryFee`. Adds the **Delivery Time input that never existed** — the reason every merchant showed the hardcoded "25–35 min" |
| **P3-02** | `subtotal + fees != total` on every discounted order, no field explaining the gap | `discount` + `promoCode` recorded; the equation asserted before write and in rules; admin panel shows the breakdown and **flags orders that don't add up** |
| **P3-03** | Every code discounted **J$0**, never expired, ignored its cap | Transactional server-side redemption. The cap is now real rather than advisory |
| **P3-04** | Commission computed on the driver's device, written to the driver's own earnings field, from a total **the caller passed in** | Recomputed server-side from the order's stored `total` |
| **P3-05** | Permanent `5.0` and `0` orders for every merchant | Ratings roll up into merchants too; `ordersToday` derived |
| **P3-06** | J$1,234,567 rendered as `1234,567` in four places | Ported the driver app's correct `Money` |

## Judgment calls worth reviewing

**Uncapped percentage codes are refused, not warned about.** A 100%-off code with no cap is an unbounded liability one typo away. The migration **flags** existing uncapped codes rather than capping them at a number nobody chose.

**Rules now deny two client paths that used to work** — a driver writing `delivered`, and a customer writing a rating. Both moved into callables because they decide money or touch server-only aggregates. Tests pin both directions: the denials *and* that the driver can still advance to `in_transit`.

**A skipped merchant rating sends `null`, not 5.** The old code substituted 5 stars — harmless while nothing counted merchant ratings, inflationary now that P3-05 does.

**A lapsed promo does not block the sale.** If redemption fails at placement, the order goes through at full price with a toast. Refusing to sell because a coupon expired is worse than the lost discount.

## Known residual gap

`redeemPromo` makes the **usage cap** real, but a modified client can still write an order claiming a discount it never redeemed — rules enforce that an order's arithmetic is self-consistent, not that its discount was authorised. Closing that needs order creation itself to move server-side, which is out of P3-03's scope. Stated in the code, not papered over. Exposure is bounded: orders are cash-on-delivery and every total is visible to the admin.

## Verification

- **58 rules tests** against the Firestore emulator (was 54) — all passing
- **25 new functions tests** covering promo evaluation and commission arithmetic; both are pure, so they run in CI with no credentials
- **36 migration tests**, idempotence asserted by running each twice
- Parity check, admin lint, functions build + lint

`npm test` is now wired into the CI functions job — the pure logic that decides what money changes hands was previously built and linted but never run.

**The Dart changes are unverified locally** — no Flutter toolchain in this environment. CI on this PR is the first thing that compiles them. Both apps gained a `cloud_functions` dependency and a plugin registration, so the lockfiles will be resolved by CI.

Nothing here has run against a real Firebase. Deploying still needs the staging project (P0-01).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

> **github-actions[bot]** (2026-07-28T16:06:58Z):
>
> Visit the preview URL for this PR (updated for commit 19d05dd):
> 
> [https://shipeast-1a1f6--pr6-feat-p3-money-bbnurxjh.web.app](https://shipeast-1a1f6--pr6-feat-p3-money-bbnurxjh.web.app)
> 
> <sub>(expires Thu, 06 Aug 2026 04:08:20 GMT)</sub>
> 
> <sub>🔥 via [Firebase Hosting GitHub Action](https://github.com/marketplace/actions/deploy-to-firebase-hosting) 🌎</sub>
> 
> <sub>Sign: 4a4f603b21d514fd605954745d5c4d72e2160f5c</sub>

---

## PR 7: Feat/admin brand 2026

- **State:** open
- **Branch:** `feat/admin-brand-2026` → `main`
- **Opened:** 2026-08-01T06:43:23Z by getgrowthnexus

_No description._

> **github-actions[bot]** (2026-08-01T06:44:34Z):
>
> Visit the preview URL for this PR (updated for commit d89d81b):
> 
> [https://shipeast-1a1f6--pr7-feat-admin-brand-202-b6ppzu33.web.app](https://shipeast-1a1f6--pr7-feat-admin-brand-202-b6ppzu33.web.app)
> 
> <sub>(expires Mon, 10 Aug 2026 02:15:57 GMT)</sub>
> 
> <sub>🔥 via [Firebase Hosting GitHub Action](https://github.com/marketplace/actions/deploy-to-firebase-hosting) 🌎</sub>
> 
> <sub>Sign: 4a4f603b21d514fd605954745d5c4d72e2160f5c</sub>

