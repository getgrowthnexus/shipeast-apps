# ShipEast — Schema of Record

**Status:** canonical · **Owner:** platform · **Established:** 2026-07-21 (P0-04)
**Firebase project (prod):** `shipeast-1a1f6`
**Resolves:** [all-three-apps-audit.md](all-three-apps-audit.md) §2, §5, §6, §11, §12, §13
**Implemented by:** [execution-all-three-plan.md](execution-all-three-plan.md) Phases 1–3

---

## Why this document exists

Three apps — `customer_app`, `driver_app`, `admin_panel` — share one Firestore database and were
each built against a private assumption about what an order, a driver, a merchant, and a promo code
look like. Those assumptions disagree in eleven places. The audit's root cause finding (§13) is not
any individual mismatch; it is that **no written contract ever existed**, so each app's author
reasonably invented one.

This file is that contract. It is the single source of truth. Where this document and the code
disagree, **the code is wrong** and there is a work item to fix it.

### Rules for changing this document

1. A schema change lands **here first**, in its own PR, before any code implements it.
2. Never silently repurpose a field name. Add the new field, migrate, then remove the old one —
   old app versions stay in the field for a long time (sideloaded APKs may never update).
3. Every field below names **who writes it** and **who reads it**. If a field has no reader, it
   should not exist. If it has no writer, it is a bug — that is exactly how `ordersToday` (always
   `0`) and `deliveryTime` (always the hardcoded fallback) happened.

---

## Global conventions

These apply to every collection and settle recurring inconsistencies found in the audit.

### a) Money — integers, minor-unit-free

All monetary values are **integers in Jamaican dollars**. No decimals, no `$` prefix, no thousands
separator, no currency symbol *in storage*.

```
deliveryFee: 250          ✅
fee: '$250'               ❌ current admin_panel/app.js:841 — resolves audit §6.1
total: 1450.00            ❌ never store a double for money
```

JMD has no circulating subunit in practice for this product, so integers are exact and there is no
floating-point rounding class of bug. Formatting happens **only at render time**, via:

- Flutter: `Money.format` / `Money.plain` (`driver_app/lib/driver_constants.dart`) — to be shared
  with the customer app in P3-06, which currently has two subtly-wrong `_formatPrice` copies.
- Admin: the existing `money()` helper (`admin_panel/app.js:41`).

This also kills the `amount` / `rawTotal` dual-read at `admin_panel/app.js:274-278`, which exists
only to tolerate both a number and a pre-formatted string in the same field.

### b) Timestamps — always `Timestamp`, never strings

Every date/time field is a Firestore `Timestamp`, written with `serverTimestamp()` where it records
"when did this happen". Never an ISO string, never a locale-formatted string.

```
expiresAt: Timestamp                ✅
validUntil: '2026-08-01'            ❌ current admin_panel/app.js:1121 — resolves audit §5
```

Server time, not client time, for anything that orders events. Client clocks are wrong and, on a
driver's phone, adversarially so.

### c) Spelling — British for licence fields

`licencePlate`, `licenceNumber` — **British spelling**, throughout.

This is not an aesthetic choice: both current *writers* (driver self-registration
`register_screen.dart:99-100`, and the admin panel `app.js:676-677`) already use British spelling.
Only the customer *reader* (`order_status_screen.dart:501`) uses American. Fixing one reader is
cheaper and lower-risk than migrating two writers plus every existing document (audit §12).

### d) Derived vs stored — counters that reset are never stored

Any figure that resets on a clock boundary is **computed at read time**, never persisted.

```
todayEarnings   → derive from today's delivered orders     (driver app already does this correctly)
ordersToday     → derive from the loaded orders array      (admin panel does NOT — audit §11)
```

A stored counter named `Today` has no reset mechanism and will be wrong from the first midnight
onward. The driver app hit this exact bug and solved it correctly at
`dashboard_screen.dart:149-161`, with a comment explaining why. The merchant equivalent must follow.

Aggregates that do *not* reset (`totalTrips`, `ratingCount`, `usedCount`) **are** stored, and are
incremented transactionally or server-side.

### e) Booleans — one field, no synonyms

One concept, one field. `merchants` currently carries both `isOpen` and `open`, written to the same
value by `app.js:841`, because the customer app read one and the admin wrote the other. Canonical:
`isOpen`. `open` is deprecated.

### f) Nullability

A field that is "not set yet" is **`null`**, not `''`, not `'—'`, not `0`. The admin panel writes
`'—'` as a placeholder into several driver and merchant fields (`app.js:672-677`, `838-840`); those
are display fallbacks that leaked into storage. Readers must render the fallback, not writers.

### g) Phone numbers — one Jamaican format

Every phone field (`users.phone`, `drivers.phone`, `merchants.phone`, `orders.customerPhone` /
`driverPhone`, `overseasInquiries.recipientPhone`) is stored and displayed as **`1-876-000-0000`**
(client checklist DR-25). Every writer normalises on save through the shared helper — `SePhone.format`
in `driver_app/lib/driver_constants.dart` and `customer_app/lib/utils/phone.dart`, `phoneFmt()` in
`admin_panel/app.js` — and every reader renders through it too, so a legacy number in another shape
still displays consistently. `tel:` links use `SePhone.dial` / `phoneDial` (E.164, e.g. `+18760000000`).
A number that is not a recognisable 7- or 10-digit local number is left as typed rather than mangled
(`overseasInquiries.contactPhone` is often an international number and is expected to pass through).

---

## `orders/{orderId}`

The central document. Written by all three apps; the source of every cross-app defect.

### Status vocabulary — canonical (resolves audit §2)

This is the single most important decision in this document. Today the customer app reads
`accepted` / `in_transit` (which nothing writes), the driver writes `confirmed` / `picked_up`
(which the customer does not understand), and the admin offers all seven unvalidated.

```
pending      order placed, no driver has claimed it
confirmed    a driver has claimed it and is en route to the merchant
picked_up    the driver has the goods
in_transit   the driver is en route to the customer     ← new; currently never written
delivered    terminal, success
cancelled    terminal, failure
```

`accepted` is **removed from the vocabulary entirely**. It was never written by any app.

**Legal transitions.** Enforced in three places, which must agree: `OrderStatus.transitions`
(P1-01), the admin dropdown (P1-06), and `firestore.rules` (P2-01).

```
pending    → confirmed | cancelled
confirmed  → picked_up | cancelled
picked_up  → in_transit | cancelled
in_transit → delivered  | cancelled
delivered  → (terminal — no transitions out)
cancelled  → (terminal — no transitions out)
```

**Administrative reversal — the one exception.** The table above describes the *forward* path a
driver walks. Unassignment is not on it: when an admin clears the driver from a held order, the
order returns to `pending` so it re-enters the available pool (`confirmed`/`picked_up`/`in_transit`
→ `pending`).

This is deliberately **not** added to `transitions`. Widening the table would also permit a *driver*
to push an order backwards, which is exactly what the table exists to prevent. It is instead a
narrow, separately-guarded clause in `firestore.rules` (`adminUnassigning`), admissible only when
the driver is genuinely being cleared and only back to `pending`.

This gap was found by the rules test suite, which caught the rules and the admin panel's
unassignment code (P1-07) contradicting each other.

**Derived sets**, defined once and used everywhere instead of ad-hoc `whereIn` literals:

| Set | Members | Used by |
|---|---|---|
| `active` | `pending`, `confirmed`, `picked_up`, `in_transit` | customer history "Active" tab |
| `driverHeld` | `confirmed`, `picked_up`, `in_transit` | driver `activeOrderStream` — **all three**, not two (audit §2.4) |
| `terminal` | `delivered`, `cancelled` | history, analytics |

Status strings are **never written as literals**. They come from the shared constant (P1-01), and
raw status values are **never rendered to a user** — always through `OrderStatus.label`.

### Fields

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `customerId` | string (Auth UID) | ✅ | customer @ create | customer, driver, admin, rules | Immutable after create. |
| `customerName` | string | ✅ | customer @ create | admin, driver | Denormalised from `users/{uid}.name`. |
| `customerPhone` | string \| null | — | customer @ create | admin, driver | **Currently never written**; admin reads it (`app.js:275`) and always shows `—`. Add in P3-02. |
| `merchantId` | string \| null | ✅ | customer @ create | admin, driver | **`null` on a package order** (P5-01) — there is no merchant, and a placeholder id would put a courier job into some merchant's order count and analytics. |
| `merchantName` | string | ✅ | customer @ create | all | Denormalised. |
| `merchantAddr` | string \| null | — | customer @ create | driver, admin | The pickup address. On a package order this is the **collection address** and is the only thing telling the driver where to go. Note the spelling: the driver app briefly read `merchantAddress`, which resolved to `—` for every order. |
| `items` | array\<OrderItem\> | ✅ | customer @ create | all | See below. Immutable. |
| `subtotal` | int | ✅ | customer @ create | all | Sum of `price × quantity`. Pre-discount. |
| `deliveryFee` | int | ✅ | customer @ create | all | Copied from `merchants/{id}.deliveryFee` at order time. |
| `serviceFee` | int | ✅ | customer @ create | all | |
| `discount` | int | ✅ | customer @ create | all | `0` when no promo. Written since P3-02; the value comes from `redeemPromo`, never from the client's own calculation. |
| `promoCode` | string \| null | ✅ | customer @ create | admin | Audit trail for redemption. Written since P3-02. |
| `total` | int | ✅ | customer @ create | all | **Invariant:** `subtotal + deliveryFee + serviceFee - discount == total`. Asserted client-side before write (P3-02) and recomputed server-side (P2-01). |
| `paymentMethod` | string | ✅ | customer @ create | admin | **Currently a display string, not a slug**: `'Cash on Delivery'` or `'PayPal'` (`payment_screen.dart:575`). PayPal is hardcoded disabled, so only the former is ever written. Should be normalised to `'cod'` / `'paypal'` — that is a migration, not a Phase 1 change, so readers match loosely until then. |
| `deliveryAddress` | string | ✅ | customer @ create | driver, admin | |
| `status` | string | ✅ | customer @ create (`pending`), driver, admin | all | Canonical vocabulary above. |
| `type` | string | ✅ | customer @ create | all | `'food'` \| `'package'`. Written since P5-01; defaults to `'food'` when absent, which every pre-Phase-5 order legitimately is. `'overseas'` is **reserved and refused at create** — that feature is an enquiry an admin prices by hand (`overseasInquiries`), never an order, so an order of that type could only come from a client that invented it. |
| `package` | map \| null | — | customer @ create | driver, admin | Present only when `type == 'package'`. `{itemCategory, pickupAddress, weightKg, weightBand, packingRequired, instructions}`. See below. |
| `driverId` | string \| null | ✅ | driver @ accept, admin @ assign | all, rules | `null` = unclaimed. Explicit `null`, never `''` — `pendingOrdersStream` filters `isNull: true`. |
| `driverName` | string \| null | — | driver @ accept, admin @ assign | customer, admin | Denormalised. |
| `driverPhone` | string \| null | — | driver @ accept, admin @ assign | customer, admin | |
| `rated` | bool | ✅ | customer @ create (`false`), **server @ rate** | customer | Since P3-05 the rating fields below are written only by `submitRating`; rules deny the client path so a rating cannot be recorded without its roll-up. |
| `driverRating` | int (1–5) \| null | — | **server @ rate** | admin | |
| `merchantRating` | int (1–5) \| null | — | **server @ rate** | admin | `null` when the customer skipped the question — never a default. It used to be sent as `5`, harmless while nothing counted it and inflationary now that P3-05 does. |
| `comment` | string \| null | — | **server @ rate** | admin | Truncated to 1000 chars server-side. |
| `tags` | array\<string\> | — | **server @ rate** | admin | Max 10, 40 chars each. |
| `driverCommission` | int | — | **server @ deliver** | driver, admin | What the driver was actually paid (P3-04). Earnings screens sum this rather than recomputing, so a rate change cannot make the displayed total disagree with the payout. |
| `commissionRate` | double | — | **server @ deliver** | admin | The rate applied, recorded so a historical payout stays explicable after the rate changes. |
| `deliveryPhotoUrl` | string \| null | — | driver @ deliver | admin | Proof of delivery. Captured today, **displayed nowhere** — P5-06. |
| `deliveryNote` | string \| null | — | driver @ deliver | admin | Same. |
| `cancelledBy` | string \| null | — | customer / admin @ cancel | admin | `'customer'` \| `'admin'`. |
| `cancellationReason` | string \| null | — | customer / admin @ cancel | customer, driver, admin | |
| `assignedBy` | string \| null | — | admin @ assign | admin | Audit trail (P1-07). |

**Timestamps** — all `Timestamp`, all `serverTimestamp()`:

| Field | Set when |
|---|---|
| `createdAt` | order placed |
| `acceptedAt` | driver claims (status → `confirmed`) |
| `pickedUpAt` | status → `picked_up` |
| `inTransitAt` | status → `in_transit` — **new** |
| `deliveredAt` | status → `delivered` (written by `confirmDelivery`) |
| `ratedAt` | customer submits a rating |
| `cancelledAt` | status → `cancelled` |
| `assignedAt` | admin assigns a driver |
| `updatedAt` | any admin mutation |

Each transition writes its timestamp **in the same write** as the status change, never separately.

### `OrderItem` (element of `items`)

| Field | Type | Notes |
|---|---|---|
| `name` | string | Denormalised from the menu item. |
| `price` | int | Unit price **at time of order**. Never re-read from the menu — menu prices change. |
| `quantity` | int | ≥ 1 |

### `package` (present only when `type == 'package'`)

| Field | Type | Notes |
|---|---|---|
| `itemCategory` | string | What is being sent — `'Documents'`, `'Glassware'`, … Chosen from the Packages grid. |
| `pickupAddress` | string | Duplicated into `merchantAddr` so existing driver and admin readers find it without a special case. |
| `weightKg` | number | As declared by the customer. The band it fell into is priced at order time and never recomputed. |
| `weightBand` | string | Human label of the band applied, e.g. `'2–5 kg'`. Stored so a historical charge stays explicable after the bands change — the same reasoning as `commissionRate`. |
| `packingRequired` | bool | When true, `serviceFee` carries the packing surcharge. |
| `instructions` | string | Free text. May be empty. |

A package order carries `items: []` and `subtotal: 0`: there are no goods, only work.
`deliveryFee` is the weight-band rate and `serviceFee` is the packing surcharge, so the standard
invariant still holds and the order needs no special rule.

### Cancellation

A customer may cancel **only from `pending`**, and may write only
`status`, `cancelledAt`, `cancelledBy`, `cancellationReason` — enforced by `customerCancelling()` in
`firestore.rules`. Adding a field to that write without changing the rule makes the whole write
fail. Once a driver has claimed the order they are already riding to the merchant, so cancelling
from there is an admin action.

**Refunds.** Orders are cash-on-delivery only, so cancelling costs nothing and there is nothing to
return — cancellation is a no-op financially. **When card payments land, `cancelOrder` must issue a
refund**, and this paragraph is the reminder that it does not today.

### Deletion

**Orders are never deleted.** Cancel, never delete. Enforced in rules (P2-01).

---

## `drivers/{uid}`

**Document ID is the Firebase Auth UID.** This is not negotiable — the driver app addresses driver
documents by `uid` in every single access path (`main.dart:70`, `driver_firestore_service.dart:12`,
`19`, `22`, `register_screen.dart:97`).

The admin panel currently violates this with `addDoc(collection(db,'drivers'), obj)`
(`app.js:684`), producing a random-ID document with **no Auth account behind it** — a person who
can never log in, and a permanent ghost row in the admin's driver count (audit §4). Resolved by
P4-05 (`createDriverAccount` Cloud Function); mitigated in the interim by removing the button.

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `name` | string | ✅ | driver @ register, admin | all | |
| `phone` | string | ✅ | driver @ register, admin | customer, admin | |
| `email` | string | ✅ | driver @ register, admin | admin | Mirrors the Auth email. |
| `vehicleType` | string | ✅ | driver @ register, admin | customer, admin | `'Car'` \| `'Motorcycle'` \| `'Bicycle'` \| `'Van'`. |
| `vehicleModel` | string | ✅ | driver @ register, admin | customer | Make and model, e.g. `'Toyota Corolla'`. **Driver registration does not collect this today** — admin does. P1-08 adds it and makes it required: an unidentifiable vehicle is a safety issue. |
| `licencePlate` | string | ✅ | driver @ register, admin | customer, admin | British spelling (§c). Uppercased. |
| ~~`licenceNumber`~~ | — | — | — | — | **Moved to `drivers/{uid}/private/identity` (P4-05).** `drivers/{uid}` is readable by every signed-in user — it has to be, because the customer's tracking card shows the driver's name and vehicle — so a licence number here was readable by every customer who ever placed an order. The admin panel now writes the private copy and reads it back when editing. Legacy documents still carrying it on the parent are covered by the P2-05 migration. |
| `status` | string | ✅ | driver @ register (`pending`), **admin only** thereafter | all, rules | `'pending'` \| `'approved'` \| `'rejected'` \| `'paused'` \| `'suspended'`. Only `'approved'` lets the driver into the app; every other value routes them to the pending/blocked screen and the dashboard listener ejects them if it changes mid-session. **`paused`** (client checklist DV-2) is a soft, reversible stop — a driver on leave, or one the admin wants offline for a shift — cleared straight back to `approved`. **`suspended`** is a hard stop for a conduct or safety issue; reinstating is still just a write back to `approved` but the admin UI treats it as a deliberate decision. Pausing or suspending also forces `isOnline: false`. **Rules forbid a driver writing this field** (self-approval, audit §7.1) — enforced by the `untouched(['status', …])` clause. |
| `isOnline` | bool | ✅ | driver | admin, functions | Availability toggle. |
| `onlineSince` | Timestamp \| null | — | driver | driver, admin | `serverTimestamp()` when the driver toggles online; `FieldValue.delete()` on toggle-off. Drives the driver dashboard's "Online since 2:45 PM" line and the admin driver card's session age. Absent = not currently online (or a legacy session that predates this field). |
| `onDelivery` | bool | — | driver | admin | Derived-ish; admin reads it (`app.js:308`). |
| `fcmToken` | string \| null | — | driver | functions | Written by the driver app. Read by the fan-out functions (P4-04), which **delete it** when FCM reports the token unregistered — an uninstalled app otherwise leaves a corpse that fails every future send. |
| `avatarUrl` | string \| null | — | driver | customer, admin | |
| `totalTrips` | int | ✅ | **server only** (P3-04) | all | Lifetime. Stored (does not reset). |
| `totalRatings` | int | ✅ | server @ rating | — | Sum of stars, for the average. |
| `ratingCount` | int | ✅ | server @ rating | admin | Number of ratings. |
| `averageRating` | double | ✅ | server @ rating | customer, admin | `totalRatings / ratingCount`. |
| `ratingCounts` | map\<'1'..'5', int\> | — | server @ rating | admin | Per-star histogram. **Nothing writes it today**; the admin panel correctly shows an honest empty state (`app.js:735-750`) and will simply start working once P3-05 populates it. |
| `createdAt` | Timestamp | ✅ | driver @ register | admin | |
| `updatedAt` | Timestamp | — | admin | — | |

**Deprecated / do not write:** `rating` (superseded by `averageRating`), `todayEarnings` (violates
§d — derived instead), `vtype`, `vehicle`, `plate`, `dlicence`, `trips`, `ratingBreakdown` (all
legacy aliases the admin panel reads defensively; remove after P2-05 migration).

**Write access.** A driver may write their own profile fields only. `status`, `totalTrips`,
`totalRatings`, `ratingCount`, `averageRating`, `ratingCounts` are **server/admin only**.

---

## `merchants/{merchantId}`

Random document ID. Admin-owned: **the customer app must never write to this collection.** It does
today, via `seedMerchantsIfEmpty()` (audit §13, removed in P1-09).

The `hours` / `deliveryTime` collision is the subtle one here. The admin's "Opening Hours" input and
the customer's `deliveryTime` are **two different things** that were conflated because the admin
panel reads `o.hours||o.deliveryTime` (`app.js:325`). Both are specified below, separately.

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `name` | string | ✅ | admin | all | |
| `category` | string | ✅ | admin | customer, admin | `'Food'` \| `'Grocery'` \| `'Pharmacy'`. |
| `owner` | string \| null | — | admin | admin | |
| `phone` | string \| null | — | admin | admin | |
| `email` | string \| null | — | admin | admin | |
| `address` | string | ✅ | admin | driver, admin | The driver's pickup location. |
| `openingHours` | string | ✅ | admin | customer, admin | **Business hours**, display-only, e.g. `'9am–9pm'`. Renamed from `hours`. |
| `deliveryTime` | string | ✅ | admin | customer | **ETA estimate**, e.g. `'25–35 min'`. **The admin has no input for this today**, which is why every admin-created merchant shows the hardcoded `'25–35 min'` fallback (audit §6.1). P3-01 adds the input. |
| `deliveryFee` | int | ✅ | admin | customer | **Integer JMD** (§a). Replaces `fee: '$250'`. Customer renders "Free" when `0`. Was three different numbers — configured, displayed, and charged (audit §6.1); P3-01 made it one. |
| `isOpen` | bool | ✅ | admin | customer, admin | §e — `open` is deprecated. |
| `imageUrl` | string \| null | — | admin | customer, admin | Cover image. Written by the P4-01 uploader as a Storage download URL under `merchants/{id}/cover_{ts}.jpg` — **timestamped, never a fixed name**, or the CDN serves stale bytes after a replacement. The paste-a-URL field is retained as a secondary option since existing records depend on it. |
| `emoji` | string \| null | — | admin | customer | Display icon. P4-02 added the picker; before it, admin-created merchants fell back to a generic 🍽️ while seeded ones had bespoke icons. |
| `promo` | string \| null | — | admin | customer | Badge text, e.g. `'🔥 Popular'`. No admin input today. |
| `totalRatings` | int | ✅ | server @ rating | — | |
| `ratingCount` | int | ✅ | server @ rating | admin | |
| `averageRating` | double | ✅ | server @ rating | customer, admin | **Nothing computes this today** — every merchant shows a permanent `5.0` (audit §11). The customer already collects `merchantRating` on the order and throws it away; P3-05 rolls it up. |
| `createdAt` | Timestamp | ✅ | admin | admin | |
| `updatedAt` | Timestamp | — | admin | — | |

**Deprecated / do not write:** `fee` (string), `hours` (→ `openingHours`), `open` (→ `isOpen`),
`rating` (→ `averageRating`), `ordersToday` (violates §d — **derived** in the admin from the loaded
orders array; the data is already in memory and needs no query), `image` (→ `imageUrl`).

### `merchants/{merchantId}/menuItems/{itemId}`

| Field | Type | Required | Written by | Read by |
|---|---|---|---|---|
| `name` | string | ✅ | admin | customer |
| `description` | string \| null | — | admin | customer |
| `price` | int | ✅ | admin | customer |
| `category` | string | ✅ | admin | customer |
| `imageUrl` | string \| null | — | admin | customer |
| `available` | bool | ✅ | admin | customer |

`category` is a lowercase slug: `'mains'` \| `'sides'` \| `'drinks'` \| `'desserts'`.
`available` is not written today; absent means available.

---

## `promoCodes/{CODE}`

**Document ID is the uppercased code itself** — this part is already correct on both sides
(`app.js:1119` writes `setDoc(doc(db,'promoCodes',code))`; the customer reads
`doc(code.toUpperCase())`), which is why lookup works and everything else fails.

Every other field in this collection disagrees between writer and reader (audit §5). The net effect
today: every code validates, applies **J$0**, never expires, and ignores its usage cap.

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `code` | string | ✅ | admin | customer, admin | Uppercase; matches the document ID. |
| `discountType` | string | ✅ | admin | customer, functions | `'percent'` \| `'fixed'`. **The customer compares against `'percentage'`** today — never matches (audit §5). |
| `discountAmount` | int | ✅ | admin | customer, functions | Percent points, or JMD. **The customer reads `discount`** today — always `null → 0`, which is the J$0 discount. |
| `minOrderTotal` | int | ✅ | admin | customer, functions | `0` for no minimum. Not enforced today. |
| `maxDiscount` | int \| null | — | admin | customer, functions | **Caps percentage discounts.** A 100% code with no cap is an unbounded liability and nothing prevents an admin creating one by typo. |
| `startsAt` | Timestamp \| null | — | admin | customer, functions | Client checklist PR-6. Scheduled activation: a code with a future `startsAt` is live in the collection but `evaluatePromo` rejects it as `not_yet_started` and the admin table shows it as **Scheduled**. `null` = live immediately. |
| `expiresAt` | Timestamp \| null | ✅ | admin | customer, functions | §b. **The admin writes `validUntil` as a string** today; the customer reads `expiresAt` as a Timestamp — so expiry is never enforced. `null` = never expires. |
| `maxUses` | int | ✅ | admin | customer, functions | |
| `usedCount` | int | ✅ | **server only** (`redeemPromo`) | customer, admin | Incremented transactionally at order placement, so two customers cannot both take the last use of a `maxUses: 1` code. |
| `lastRedeemedAt` | Timestamp \| null | — | **server only** | admin | |
| `active` | bool | ✅ | admin | customer, functions | The one field that already lines up. **Pause** (checklist PR-10) sets this `false` and is reversible with **Resume**. |
| `endedAt` | Timestamp \| null | — | admin | admin | Set by **End Promo** (checklist PR-10) alongside `active: false`. A terminal stop — the admin UI only offers Duplicate / Delete once it is set, never Resume. Distinguishes an ended code from a merely paused one. |
| `createdAt` | Timestamp | ✅ | admin | admin | |
| `eligibility` | map \| absent | — | admin | customer, functions | Client checklist PR-5, "who can get the discount." Every key optional and additive — an absent `eligibility` (every promo created before PR-5) or an absent key within it imposes no restriction, so old codes keep behaving exactly as before. See below for keys. |

**`eligibility` map** (see `functions/src/eligibility.ts` — the schema of record for the shape;
`admin_panel/promo-eligibility.js` and `customer_app/lib/models/promo_eligibility.dart` are
byte-for-byte mirrors of its logic, not just its field names):

| Key | Type | Notes |
|---|---|---|
| `customerScope` | `'new'` \| `'existing'` \| `'selected'` \| absent | Absent = any customer. `'new'`/`'existing'` read against the customer's *entire* order history (any status, any kind), not just this transaction — see `firstOrderOnly` below for the narrower condition. |
| `customerIds` | array\<string\> | Consulted only when `customerScope === 'selected'`. **Empty or absent then admits nobody** — a deliberate fail-closed choice so an admin who picks "Selected customers" but forgets to pick any doesn't accidentally ship an open code. |
| `merchantIds` | array\<string\> | Empty/absent = any merchant. A package order (no merchant) fails a merchant-scoped code. |
| `categories` | array\<string\> | Empty/absent = any category. Matched against the merchant's category. |
| `deliveryAreas` | array\<string\> | Empty/absent = any area. Matched against the delivery address by case-insensitive substring (same "does the address mention it" match the admin Orders filter uses) — an empty address fails an area-scoped code rather than matching by accident. |
| `firstOrderOnly` | bool | Default `false`. Distinct from `customerScope: 'new'`: an admin can run a "new customers" promo for a month, but `firstOrderOnly` stops applying the moment the customer's very first order/request (even a cancelled one) has been placed — both can be set at once. |
| `discountBase` | `'subtotal'` \| `'deliveryFee'` | Default `'subtotal'`. What the discount is computed against. The **minimum-order check always runs against the real subtotal**, regardless of this setting — "spend at least J$2,000" means the order, not whichever part gets discounted. |
| `orderKinds` | array of `'food'` \| `'package'` \| `'shop_deliver'` | Empty/absent = any kind. `'shop_deliver'` lets a code apply to a Shop & Deliver quote (`overseasInquiries`), not just an order. |

**Deprecated / do not write:** `validUntil` (string → `expiresAt`), `discount` (→ `discountAmount`).

**Validation order** (both client-side for instant feedback and server-side for authority):
`active` → `startsAt` → `expiresAt` → `usedCount < maxUses` → `eligibility` (PR-5) →
`subtotal >= minOrderTotal` → compute against `discountBaseAmount`, capped by `maxDiscount`.

Client validation is **never trusted**. Redemption increments `usedCount` transactionally in a
callable function (P3-03), and — as of PR-5 — the eligibility check re-runs server-side inside
that same transaction against freshly read state; the client's preview is advisory only.

---

## `users/{uid}`

**Document ID is the Firebase Auth UID.** Private to its owner; admin gets read-only access
(needed by the Customers page, P5-05).

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `name` | string | ✅ | customer | customer, admin | Denormalised onto orders. |
| `phone` | string | ✅ | customer | customer, admin | |
| `email` | string | ✅ | customer | customer, admin | Mirrors Auth. |
| `avatarUrl` | string \| null | — | customer | customer | |
| `fcmToken` | string \| null | — | customer | functions | Written on **sign-in** and **deleted on sign-out** (P4-03) — a shared or resold phone would otherwise keep delivering one customer's order updates to whoever signs in next. Also deleted by the fan-out functions when FCM reports it unregistered. |
| `fcmTokenUpdatedAt` | Timestamp \| null | — | customer | — | When the token was last refreshed. Diagnostic only. |
| `notificationsReadAt` | Timestamp \| null | — | customer | customer | Drives the unread badge. |
| `disabled` | bool | — | **server** (`setUserDisabled`) | admin | Account suspension (P5-05). Rules permit an admin to write it directly as a backstop, but the panel does not: **this flag is not consulted by rules**, so on its own it stops nobody. The callable disables the Auth account and revokes refresh tokens, then records the flag — the two move together or the flag lies. |
| `tags` | array\<string\> | — | admin | admin, functions | Client checklist CU-4. Operator-assigned segmentation from a fixed catalogue (`CUSTOMER_TAGS` in `admin_panel/app.js`): `diaspora`, `st_thomas`, `business`, `vip`, `frequent_buyer`, `new_customer`. Drives the Customers page badges/stats and (once built) notification audience targeting (NT-2). Admin-writable directly; a customer cannot tag themselves. Absent = untagged. |
| `tagsUpdatedAt` | Timestamp \| null | — | admin | admin | When the tags were last changed. |
| `tagsUpdatedBy` | string \| null | — | admin | admin | Admin uid who last changed the tags. |
| `disabledReason` | string \| null | — | **server** | admin | Required when disabling; **cleared** on re-enable, so a cleared account does not keep carrying an accusation. |
| `disabledAt` | Timestamp \| null | — | **server** | admin | Nulled on re-enable. |
| `disabledBy` | string \| null | — | **server** | admin | Admin UID. Audit trail. |
| `createdAt` | Timestamp | ✅ | customer | admin | |
| `updatedAt` | Timestamp | — | customer | — | |

### `users/{uid}/addresses/{addressId}`

| Field | Type | Required | Notes |
|---|---|---|---|
| `label` | string | ✅ | `'Home'`, `'Work'`, … |
| `text` | string | ✅ | The address itself. |
| `createdAt` | Timestamp | ✅ | Sort key. |

Same access as the parent: owner-only read/write, admin read-only.

---

## `notifications/{id}`

Admin-written broadcast log. Fanned out to devices by `onNotificationCreated` (P4-04). Before that
function existed nothing sent, and the driver app does not read this collection at all, so
selecting "All Drivers" delivered to nobody (audit §9).

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `title` | string | ✅ | admin | customer, functions | |
| `message` | string | ✅ | admin | customer, functions | |
| `target` | string | ✅ | admin | customer, functions | Client checklist NT-2. `'all'` \| `'customers'` \| `'drivers'` \| a specific UID \| **`'tag:<slug>'`** (a CU-4 customer tag) \| **`'ordered'`** \| **`'never_ordered'`** \| **`'inactive'`** (segments derived from order history server-side). Resolved by `parseTarget` / `recipientsForTarget` in `functions/notifications.ts`. |
| `destType` | string \| null | — | admin | customer, functions | Client checklist NT-4. Where a tap on the push lands: `'order'` (→ `destValue` is an order id) \| `'search'` (→ a search term) \| `'screen'` (→ an allow-listed route) \| `'url'` (→ an external http(s) link). Absent = opens the app. Travels in the FCM `data` payload; the customer app's `_openTarget` routes on it. |
| `destValue` | string \| null | — | admin | customer, functions | The value for `destType`. |
| `scheduledFor` | Timestamp \| null | — | admin | functions | Client checklist NT-3. When set to a future time, `onNotificationCreated` does **not** send — `dispatchScheduledNotifications` (runs every 5 min) picks it up once due. `null` = send immediately. |
| `dispatchedAt` | Timestamp \| null | — | functions | admin | Set by the fan-out the moment it sends. Also the scheduler's "already done" marker, so a scheduled push is never sent twice. |
| `sentBy` | string | ✅ | admin | admin | Admin email, audit trail. |
| `createdAt` | Timestamp | ✅ | admin | all | |
| `deliveredCount` | int \| null | — | functions | admin | How many devices actually received it. Closes the loop between "logged" and "sent". Written back by the fan-out. |
| `failedCount` | int \| null | — | functions | admin | Sends FCM rejected (invalid/unregistered tokens). Written back by the fan-out alongside `deliveredCount`. Client checklist NT-6. |
| `openedCount` | int \| null | — | functions | admin | How many recipients tapped the push. Requires the client apps to report an open (via a callable or an analytics event the function aggregates) — **not yet wired**; the admin "Recent Notifications" row renders it only when present. Client checklist NT-6. |

---

## `pushLog/{eventKey}`

**Server-only. No client may read or write it** (firestore.rules denies both; the Admin SDK
bypasses rules).

Firestore triggers are **at-least-once** — a retry after a transient error re-runs the handler with
the same event, and without a guard the customer gets "Your driver is on the way" three times. Each
fan-out claims its event key with `create()`, which fails if the document already exists, making the
check and the claim one atomic operation. A `get`-then-`set` would race two concurrent retries.

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `at` | Timestamp | ✅ | functions | — | When the send was claimed. |

Key formats: `notification_{id}`, `order_created_{orderId}`, `order_status_{orderId}_{status}`,
`driver_status_{uid}_{status}`. Keys are derived from the event, not from a random id — that is what
makes a duplicate delivery collide.

---

## `drivers/{uid}/private/identity`

PII kept off the parent document, which **every signed-in user can read** (P4-05).

| Field | Type | Required | Written by | Read by | Notes |
|---|---|---|---|---|---|
| `licenceNumber` | string | ✅ | driver, admin | driver, admin | British spelling (§c). Was on `drivers/{uid}` until P4-05, where every customer who had placed an order could read it. |
| `documents` | map \| null | — | driver @ register | driver, admin | Client checklist DV-5. Storage download URLs for the credential photos a driver uploads at registration: `{licence: url, vehicle: url}` (more keys may be added). Kept here, **not on the parent**, for the same reason as `licenceNumber` — the parent is world-readable to signed-in users and a licence photo is not. The admin document-review flow reads this doc when opening a pending driver. `null` / absent for a driver who registered before this existed; the review UI says so rather than showing a broken image. Storage path `drivers/{uid}/documents/{key}.jpg` (read: admin or self). |
| `updatedAt` | Timestamp | — | driver, admin | — | |

---

## `overseasInquiries/{inquiryId}`

A request to ship something to family in Jamaica, and the record of how it was handled.

Overseas ordering was a `WebView` pointed at two placeholder form URLs this project does not own,
with **zero** Firestore writes. When both failed — which is what a placeholder URL does — the
customer saw "Connection Error" and their request went nowhere. It was then briefly an email-only
waitlist, which recorded that somebody was interested but not what they wanted to send, so every
entry still needed a phone call before anything could happen. This is the request itself.

**An enquiry is not an order.** No money, no driver, no `orders` lifecycle. An overseas shipment is
priced by carrier, route, dimensional weight and customs classification, none of which is in this
system — so nothing quotes a price here, and the customer is told a person will come back to them.
Read the customer app's `overseas_inquiry.dart` header for why the alternative is dishonest.

Created by the customer; **handled** by the admin. Rules split it exactly there: the customer owns
the request, the admin owns `status`, `adminNote`, `handledBy` and `handledAt`, and neither can
write the other's half. Read access is the author or an admin — the document carries a household's
name, phone number and street address.

| Field | Type | Required | Written by | Notes |
|---|---|---|---|---|
| `customerId` | string | ✅ | customer @ create | Pinned to the caller by rules. |
| `customerName` | string | ✅ | customer @ create | Denormalised from the Auth profile. |
| `contactEmail` | string | ✅ | customer @ create | Max 320. How the quote is sent — the panel links a pre-addressed `mailto:`. |
| `contactPhone` | string | ✅ | customer @ create | Max 120. The sender may be abroad, so a country code is expected. |
| `originCountry` | string | ✅ | customer @ create | Free text, e.g. `'Brooklyn, USA'`. |
| `recipientName` | string | ✅ | customer @ create | Max 120. |
| `recipientPhone` | string | ✅ | customer @ create | Max 120. |
| `recipientAddress` | string | ✅ | customer @ create | Max 400. A parish alone is not somewhere a courier can knock, so the form requires 8+ characters. |
| `recipientParish` | string | ✅ | customer @ create | One of the 14 parishes (`JamaicaParish.all`). A dropdown, not free text: the panel groups the queue by this, and "St Thomas" / "st. thomas" as separate destinations is how an operator misses one. |
| `itemCategory` | string | ✅ | customer @ create | From `OverseasItemCategory.all`. |
| `itemDescription` | string | ✅ | customer @ create | Max 1000. The shopping list, one item per line. The admin panel derives a rough item count from it (`overseas-status.js` → `itemCount`) — an estimate for the operator's glance, not a structured quantity. |
| `requestedStore` | string \| null | — | customer @ create | Client checklist SD-5. Free-text store preference — "PriceSmart", "any supermarket". Max 120. **Omitted entirely when blank** (not written as `null`) so the rules' `get('requestedStore','').size()` check holds; the panel shows "Any store". |
| `estimatedWeightKg` | double\|null | — | customer @ create | Optional — a customer who does not know what the box weighs can still ask. `null`, never `0`: zero is a weight, and would read as an empty box. |
| `notes` | string | — | customer @ create | Max 1000. |
| `status` | string | ✅ | customer @ create, admin @ update | Client checklist SD-4. The nine-stage pipeline `'new'` → `'reviewing'` → `'quote_sent'` → `'awaiting_customer'` → `'approved'` → `'shopping'` → `'ready_for_delivery'` → `'out_for_delivery'` → `'completed'`, plus the outcomes `'declined'` \| `'cancelled'` \| `'expired'`. Always `'new'` at create — rules refuse anything else. SD-1: the panel's "Closed" bucket is every terminal state (`completed`/`declined`/`cancelled`/`expired`), not just declined. Mirrored in `admin_panel/overseas-status.js`, `customer_app/lib/models/overseas_inquiry.dart` (`OverseasStatus`), and `firestore.rules` `overseasStatus()`. The pre-SD-4 slugs (`contacted`/`quoted`/`closed`) are migrated by `tools/migrate` and refused by the rules on a fresh write. |
| `adminNote` | string | — | **admin only** | Internal. Never shown to the customer; the panel says so on the label. Rules refuse it at create. |
| `handledBy` | string | — | **admin only** | Admin uid. |
| `handledAt` | Timestamp | — | **admin only** | |
| `quoteItemsCost` | int \| null | — | **admin only** | Client checklist SD-7. Estimated cost of the goods, integer JMD. |
| `quoteServiceFee` | int \| null | — | **admin only** | Shopping / service fee, integer JMD. |
| `quoteDeliveryFee` | int \| null | — | **admin only** | Delivery fee, integer JMD. |
| `quoteTotal` | int \| null | — | **admin only** | `quoteItemsCost + quoteServiceFee + quoteDeliveryFee`, **derived on save** so the stored total cannot disagree with its parts. |
| `quoteExpiresAt` | Timestamp \| null | — | **admin only** | When the quote lapses. `null` = no expiry set. |
| `quotePaymentStatus` | string | — | **admin only** | `'' \| 'pending' \| 'paid' \| 'refunded' \| 'waived'`. Free-form enough that this is a display slug, not enforced. |
| `quotedBy` | string \| null | — | **admin only** | Admin uid who saved the quote. |
| `quotedAt` | Timestamp \| null | — | **admin only** | When the quote was last saved. |
| `createdAt` | Timestamp | ✅ | customer @ create | `serverTimestamp()`, so it is briefly `null` on the client. Both the app and the panel sort an unresolved enquiry **first** — it is the newest thing there is, and the one most needing attention. |
| `updatedAt` | Timestamp | ✅ | customer @ create, admin @ update | |

### Handling

Every status is reachable from every other. An operator who marks the wrong enquiry `declined` must
be able to put it back; a one-way lifecycle only moves the correction into the Firebase console,
which is the habit the panel exists to end. The panel orders the choices so the likely next step is
first (`overseas-status.js` → `nextStatuses`).

What an admin may **not** do is edit the customer's own account of what they are sending. It is what
the carrier and customs are quoted against, so a wrong description is a new enquiry, not an edit.
Rules enforce this with `changed().hasOnly([...])`.

Enquiries are never deleted, by anyone. One is the only record of what somebody asked us to ship —
including the ones we refused, and the reason given.

The customer sees the status move, in the app, on the same screen they filed it from. That is what
makes moving it worth anything.

---

## `settings/pricing`

Single document, admin-editable, introduced by P5-01 so package pricing is not hardcoded in the
client.

World-readable (the customer app shows the fee before sign-in), admin-write. Edited from the
panel's **Pricing** page — not the Firebase console.

| Field | Type | Notes |
|---|---|---|
| `serviceFee` | int | Flat service fee applied to orders. |
| `driverCommissionRate` | double | Currently `0.10`, hardcoded at `driver_constants.dart:13`. **Server reads this** for the authoritative commission (P3-04); the client copy is display-only. |
| `packageBands` | array\<{maxKg: number \| null, price: int}\> | Weight bands for package delivery (P5-01). Sorted ascending; **exactly one** entry may have `maxKg: null`, the open-ended final band. |
| `packageOveragePerKg` | int | Charged per whole kilogram above the last bounded band. `0` means the open band is flat. |
| `packingSurcharge` | int | Added to `serviceFee` when the customer asks for the parcel to be packed. |
| `packageMaxWeightKg` | number | Heaviest parcel accepted. Above it the app declines rather than quoting. Defaults to `50` when absent. |

**There is no fallback price list anywhere in the codebase.** If `packageBands` is missing or
malformed, `PackagePricing.fromSettings` returns `null` and the customer app refuses to quote or to
take a package request. That is deliberate: a price nobody chose is worse than an unavailable
feature, and it is the same rule the migrations follow (never invent a business value). Contrast
`DEFAULT_COMMISSION_RATE`, which *does* fall back — that value was already shipped, so falling back
preserves existing behaviour rather than inventing new behaviour.

---

## Deprecated fields — migration index

Every field below exists in production data and must be migrated (P2-05) then removed. Readers
tolerate both shapes for **one release cycle** — sideloaded APKs may never update, so a hard cutover
would break clients in the field.

| Collection | Deprecated | Canonical | Migration |
|---|---|---|---|
| `orders` | `status: 'accepted'` | `'confirmed'` | Rewrite value. |
| `orders` | `amount` (string) | `total` (int) | Parse; drop. |
| `orders` | — | `discount: 0`, `promoCode: null` | Backfill. |
| `orders` | — | `type: 'food'` | Backfill. |
| `merchants` | `fee: '$250'` | `deliveryFee: 250` | Parse int; drop `fee`. |
| `merchants` | `hours` | `openingHours` | Rename. |
| `merchants` | — | `deliveryTime` | Backfill a default; **flag for manual admin review** — the real value cannot be derived. |
| `merchants` | `open` | `isOpen` | Consolidate; drop. |
| `merchants` | `rating` | `averageRating` | Seed from `rating`; recompute as ratings arrive. |
| `merchants` | `ordersToday` | *(derived)* | Delete the field. |
| `promoCodes` | `validUntil` (string) | `expiresAt` (Timestamp) | Parse; **log every failure** for manual review; `null` if unparseable. |
| `promoCodes` | `discount` | `discountAmount` | Rename where present. |
| `drivers` | `licensePlate` | `licencePlate` | Rename if any American-spelled docs exist. |
| `drivers` | `rating` | `averageRating` | Seed. |
| `drivers` | `todayEarnings` | *(derived)* | Delete the field. |
| `drivers` | *(random-ID docs)* | UID-keyed | **Do not auto-delete.** Export to CSV for manual reconciliation — some correspond to real people needing an account (P4-05). |
| `overseasInquiries` | `status: 'contacted'` | `'reviewing'` | Rewrite value (SD-4). |
| `overseasInquiries` | `status: 'quoted'` | `'quote_sent'` | Rewrite value. |
| `overseasInquiries` | `status: 'closed'` | `'completed'` | Rewrite value — a bare `closed` most likely means fulfilled; an actual decline was already `declined`. |

---

## Invariants

Assertable properties. The P2-05 verification script checks each; a violation is a bug.

1. `subtotal + deliveryFee + serviceFee - discount == total` on every order.
2. Every `orders.status` is one of the six canonical values.
3. Every `orders.driverId` is either `null` or an existing `drivers/{uid}` document ID.
4. Every `drivers` document ID is a valid Firebase Auth UID.
5. No order transitions out of `delivered` or `cancelled`.
6. `averageRating == totalRatings / ratingCount` wherever `ratingCount > 0`.
7. `usedCount <= maxUses` on every promo code.
8. No monetary field anywhere is a string or a non-integer.
9. Every timestamp field is a `Timestamp`, never a string.
10. No document in `merchants` was written by a client app.
