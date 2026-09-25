# ShipEast — Three-App Integration Audit
**Customer App · Driver App · Admin Panel**
Date: 2026-07-21 · Branch: `feat/admin-seds` · Auditor: static cross-app code review

---

## 0. Scope, method, and honesty statement

**What was audited:** every Dart screen and service in `customer_app/lib` (10,284 LOC) and
`driver_app/lib` (7,743 LOC), and the whole `admin_panel` (index.html / styles.css / app.js,
2,706 LOC). The focus was the *contract between the three apps* — the Firestore documents each
one writes and each one reads — because that is where "admin does X and it shows up in the
customer/driver app in realtime" either works or silently fails.

**What was NOT done, and why:**

- **No visual/runtime verification.** There is no Flutter or Dart toolchain installed in this
  environment (`flutter: command not found`). I could not build, run, screenshot, or
  `flutter analyze` either mobile app. Every UI claim in this document is inferred from widget
  code, not observed on a device.
- **No admin panel runtime check.** `admin_panel` is static HTML/JS, but it needs live Firebase
  Auth credentials against project `shipeast-1a1f6` to render anything past the login screen.
- **No Firestore inspection.** I have no credentials for the live project, so I could not confirm
  which of the field-name mismatches below have already been papered over by hand-edited
  production data.

Everything flagged as a **defect** is grounded in a specific file and line. Where I am inferring
runtime behaviour rather than reading it directly, I say so.

**Headline finding:** the three apps do not share a schema. They share a *database*. Each app was
built against its own private assumption about what an order, a driver, a merchant, and a promo
code look like, and those assumptions disagree in at least eleven places. The result is a system
that looks complete screen-by-screen but breaks at nearly every hand-off between apps. This is not
production-ready, and the gap is not cosmetic — it is data-contract-level.

---

## 1. Severity summary

| # | Defect | Severity | Blast radius |
|---|--------|----------|--------------|
| 1 | Order status vocabulary is incompatible across all three apps | **P0 — Blocker** | Customer tracking, order history, driver hand-off |
| 2 | Admin-assigned orders enter a black hole no driver can see | **P0 — Blocker** | Every manually dispatched order |
| 3 | Admin "Add Driver" creates an orphan doc with no auth account | **P0 — Blocker** | Driver onboarding via admin |
| 4 | Promo codes written by admin are unreadable by the customer app | **P0 — Blocker** | All promotions, revenue |
| 5 | Merchant delivery fee + hours set in admin are ignored by customer app | **P0 — Money** | Every order total |
| 6 | No Firestore security rules or Cloud Functions committed | **P0 — Security** | Entire backend |
| 7 | No image upload anywhere in admin — URL text field only | **P1 — Requested feature missing** | Merchant/menu media |
| 8 | Push notifications are non-functional end-to-end | **P1** | All "realtime" alerts |
| 9 | Packages / overseas flows are non-functional mockups | **P1** | Two advertised product lines |
| 10 | Merchant `ordersToday` and promo `usedCount` never increment | **P1** | Admin analytics integrity |
| 11 | Customer driver-card reads three field names that are never written | **P2** | Driver identity on tracking screen |
| 12 | Customer app auto-seeds 15 demo merchants into production | **P2** | Data pollution |
| 13 | Driver approval revocation does not take effect until app restart | **P2** | Access control |
| 14 | Customer cannot cancel an order; no cancellation path exists | **P2** | Support load |
| 15 | Composite indexes required by driver queries are not committed | **P2** | Cold-start failure |

---

## 2. P0 — The order status vocabulary is incompatible

This is the single most damaging defect in the codebase, and it alone makes the system unfit for
production.

### 2.1 What each app writes

| Event | Writer | Status written |
|-------|--------|----------------|
| Customer places order | `customer_app/lib/services/firestore_service.dart:155` | `pending` |
| Driver accepts | `driver_app/lib/services/driver_firestore_service.dart:88` | `confirmed` |
| Driver confirms pickup | `driver_app/lib/services/driver_firestore_service.dart:96` | `picked_up` |
| Driver confirms delivery | `driver_app/lib/services/driver_firestore_service.dart:119` | `delivered` |

So the **only** statuses that ever exist in production are:
`pending → confirmed → picked_up → delivered`.

### 2.2 What the customer app reads

`customer_app/lib/screens/order_status_screen.dart:33-47`:

```dart
switch (status) {
  case 'pending':     return 0;
  case 'accepted':    return 1;   // never written by anything
  case 'in_transit':  return 2;   // never written by anything
  case 'delivered':   return 3;
  default:            return 0;   // ← 'confirmed' and 'picked_up' land here
}
```

**Consequence:** from the moment a driver accepts an order until the moment it is delivered, the
customer's live tracking screen sits frozen on step 0, "Order Confirmed", with ETA "~40 min". The
driver can accept, drive to the merchant, collect the food, and drive halfway to the customer —
the customer sees nothing move. Then the screen jumps straight from step 0 to step 3.

The screen even advertises "Live status · updates automatically" (line 269). It does not.

### 2.3 What the customer's order history reads

`customer_app/lib/screens/order_history_screen.dart:69-79`:

```dart
if (label == 'Active')    return status == 'pending' || status == 'accepted' || status == 'in_transit';
if (label == 'Completed') return status == 'delivered';
if (label == 'Cancelled') return status == 'cancelled';
```

**Consequence:** an order in `confirmed` or `picked_up` matches *no tab*. It **vanishes entirely
from the customer's order list** during the exact window when it is actively being delivered. The
customer opens "My Orders" mid-delivery and their order is gone. `_displayStatus` (line 81) also
has no case for these, so anywhere the raw value leaks through, the user sees the literal string
`picked_up`.

### 2.4 What the admin panel offers

`admin_panel/app.js:561` gives the admin a dropdown containing **all seven** statuses:

```js
['pending','confirmed','accepted','in_transit','picked_up','delivered','cancelled']
```

Two of these — `accepted` and `in_transit` — exist in no app's write path. But the admin can write
them. And when they do:

`driver_app/lib/services/driver_firestore_service.dart:41`:
```dart
.where('status', whereIn: ['confirmed', 'picked_up'])
```

**Consequence:** an admin who sets a live order to `in_transit` (a perfectly reasonable-looking
action, and arguably the semantically correct one) **instantly removes it from the assigned
driver's active-order stream.** The driver's dashboard clears mid-delivery. They lose the customer
address, the pickup screen, and the delivery-confirmation button, with the food already in their
vehicle. There is no recovery path in the UI.

### 2.5 Required fix

Define one canonical status enum in a shared location and make all three apps use it. Recommended
vocabulary (matching what the driver already writes, since that is the app with the most states):

```
pending → confirmed → picked_up → in_transit → delivered
                                             ↘ cancelled
```

Then:
- Customer `_currentStep` and `_displayStatus` must map all six.
- Customer "Active" filter must include `confirmed` and `picked_up`.
- Driver `activeOrderStream` `whereIn` must include every non-terminal status.
- Admin dropdown must be restricted to the canonical set, and ideally to *legal transitions* from
  the order's current state rather than a free-for-all.

Until this is done, do not ship. Everything else in this document is secondary to it.

---

## 3. P0 — Admin-assigned orders enter a black hole

`admin_panel/app.js:574-593` (`saveOrderChanges`) lets an admin assign a driver. It writes
`driverId`, `driverName`, `driverPhone` — and writes `status` **only if the admin also changed the
status dropdown**.

Trace what happens when an admin assigns a driver and leaves status alone:

1. Order now has `driverId: "abc"`, `status: "pending"`.
2. Driver's *available orders* stream (`driver_firestore_service.dart:26-34`) filters
   `status == 'pending'` **and** `driverId == null`. The order now fails the second condition →
   **no driver sees it in the available pool**, including the assigned one.
3. Driver's *active order* stream filters `status whereIn ['confirmed','picked_up']`. The order is
   still `pending` → **the assigned driver does not see it either.**
4. Customer's tracking screen shows a driver card populated with the assigned driver's name
   (because `driverId` is set) while the driver has no idea the order exists.

**The order is invisible to every driver and will never be delivered.** The admin panel's most
important operational lever — manual dispatch — is broken.

**Fix:** `saveOrderChanges` must set `status: 'confirmed'` atomically whenever it assigns a
`driverId` to a `pending` order. Ideally this runs as a transaction that also refuses to reassign
an order already claimed by another driver.

---

## 4. P0 — Admin "Add Driver" creates an orphan

`admin_panel/app.js:684`:

```js
promise = addDoc(collection(db,'drivers'), obj);   // ← random document ID
```

Meanwhile the driver app addresses driver documents **by Firebase Auth UID** everywhere:

- `driver_app/lib/screens/register_screen.dart:97` — `.collection('drivers').doc(uid).set(...)`
- `driver_app/lib/main.dart:70-73` — `.doc(user.uid).get()`
- `driver_app/lib/services/driver_firestore_service.dart:12,19,22` — all keyed on `uid`

**Consequence:** a driver created from the admin panel gets a document with a random ID and **no
corresponding Firebase Auth account**. That person cannot log in. If they later self-register in
the driver app, they get a *second* document keyed by their real UID, and the admin now sees two
rows for one human — one live, one a permanent ghost that inflates the "Total Drivers" stat
(`app.js:603`) and can be toggled online (`toggleDriverOnline`) with no effect on anything.

Worse, the admin form's `status: active ? 'approved' : 'pending'` and `isOnline: active`
(`app.js:678`) write to the orphan, so an admin "approving" a driver this way approves nobody.

**Fix:** admin-side driver creation must provision a real Auth account. This requires the Firebase
Admin SDK, which cannot run in a browser — it needs a Cloud Function (`createDriver`) callable from
the panel, which creates the Auth user and writes `drivers/{uid}` in one step. See §7 — there are
no Cloud Functions in this repository at all.

**Interim mitigation:** remove the "Add Driver" button entirely and make driver onboarding
self-service-only (register in the app → admin approves). The approve/reject flow
(`app.js:704-718`) is correct and does work against self-registered drivers, because those have
UID-keyed docs.

---

## 5. P0 — Promo codes are write-only

The admin creates promo codes correctly keyed by code (`app.js:1119`, `setDoc(doc(db,'promoCodes',code), …)`),
so document lookup works. Everything else about the contract is wrong.

| Field | Admin writes (`app.js:1119-1122`) | Customer reads (`payment_screen.dart:104-111`, `firestore_service.dart:262-274`) | Result |
|-------|-----------------------------------|------------------------------------|--------|
| Discount value | `discountAmount: 20` | `data['discount']` | `null → 0` — **discount is always J$0** |
| Discount type | `discountType: 'percent'` | compares to `'percentage'` | never matches → falls to fixed-amount branch |
| Expiry | `validUntil: '2026-08-01'` (string) | `expiresAt` (Timestamp) | expiry **never enforced** — codes never expire |
| Active flag | `active: true` | `data['active'] != true` → reject | ✅ this one works |
| Usage cap | `maxUses`, `usedCount: 0` | never read, never incremented | cap **never enforced** |

**Consequence:** every promo code an admin creates validates successfully (because `active` is the
only field that lines up), shows the customer a green success toast reading
*"Promo applied! You saved $0"* (`payment_screen.dart:118`), and applies zero discount. The code
works forever, ignores its expiry date, and ignores its usage cap. `usedCount` displays `0` in the
admin table (`app.js:1101`) permanently, so the admin has no visibility into redemption either.

**Fix:** settle on one shape — recommend `{code, discountType: 'percent'|'fixed', discountAmount:
number, expiresAt: Timestamp, maxUses, usedCount, active}` — and correct both sides. Redemption
must increment `usedCount` transactionally at order placement, and `placeOrder` must record the
applied code and discount on the order document (it currently records neither — see §6.2).

---

## 6. P0 — Money: merchant economics set in admin never reach the customer

### 6.1 Delivery fee and hours are dropped on the floor

The admin merchant form writes (`app.js:838-842`):

```js
{ name, category, owner, phone, email, address,
  hours: '9am–9pm',      // opening hours
  fee: '$250',           // delivery fee, as a string with a $ prefix
  isOpen, open, imageUrl }
```

The customer home screen reads (`home_screen.dart:674-682`):

```dart
'deliveryTime': m['deliveryTime'] ?? '25–35 min',
'deliveryFee':  m['deliveryFee']  ?? 'Free delivery',
'deliveryFeeAmount': _parseDeliveryFee(m['deliveryFee'] as String? ?? ''),
'emoji': m['emoji'] as String? ?? '🍽️',
```

`deliveryTime` and `deliveryFee` are **never written by the admin panel**. The admin's `hours` and
`fee` fields are read by nothing.

**Consequence:** every merchant created through the admin panel appears in the customer app with
the hardcoded fallbacks — "25–35 min" and "Free delivery" — regardless of what the admin typed.
`_parseDeliveryFee('')` returns 100 (`home_screen.dart:148-152`), so the customer is silently
charged J$100 delivery on a merchant the admin configured at J$250, while the UI shows "Free
delivery". **The displayed fee, the charged fee, and the configured fee are three different
numbers.** This is a revenue leak and a consumer-facing misrepresentation.

The `fee: '$' + value` string format (`app.js:841`) is itself a mistake — money should be stored as
a number and formatted at the edge. The admin panel already has a `money()` helper for this.

### 6.2 The order document does not record its own economics

`placeOrder` (`firestore_service.dart:138-160`) writes `subtotal`, `deliveryFee`, `serviceFee`,
`total` — but `total` is passed as `_finalTotal`, i.e. **post-discount** (`payment_screen.dart:586`),
while `subtotal` is pre-discount and the discount itself is never stored. There is no `discount`
or `promoCode` field on the order.

**Consequence:** the order does not reconcile. `subtotal + deliveryFee + serviceFee ≠ total` on any
discounted order, with no field explaining the difference. Admin analytics
(`app.js:1156`, revenue from `rawTotal`) will silently under-report against merchant payouts, and
there is no audit trail for which promo was redeemed on which order. Add `discount` and `promoCode`
to the order document.

### 6.3 Driver commission is computed client-side

`driver_constants.dart:16` — `commissionOn()` runs on the driver's device and the result is written
straight to `drivers/{uid}.todayEarnings` via `FieldValue.increment` (`driver_firestore_service.dart:126`).
With no security rules (§7), a modified client can write any earnings figure it likes. Commission
must be computed server-side in the same Cloud Function that finalises delivery.

---

## 7. P0 — There is no backend

The repository contains **no** `firestore.rules`, **no** `storage.rules`, **no**
`firestore.indexes.json`, and **no** `functions/` directory. The only Firebase config is
`admin_panel/firebase.json`, which configures static hosting and nothing else.

### 7.1 Security rules

Without committed rules, the database is in one of two states, both unacceptable:

- **Test mode** — world-readable and world-writable. Any person who extracts the (public, and
  necessarily public) API key from the shipped APK can read every customer's name, phone, and home
  address, read every driver's licence number, and rewrite any order's status or total.
- **Hand-edited in the console** — undocumented, unreviewed, unversioned, and impossible to
  reproduce in a staging project.

Note that `admin_panel/app.js:12` ships the API key in plaintext. That is normal and safe for
Firebase *only when rules exist*. Here it is not safe.

At minimum the rules must express:
- `users/{uid}` — readable and writable only by `uid`.
- `users/{uid}/addresses/**` — same.
- `orders/{id}` — readable by its `customerId`, its `driverId`, and admins. Customers may create
  but never mutate `status`, `total`, or `driverId`. Drivers may only claim orders that are
  `pending` with a null `driverId`, and may only advance status forward.
- `drivers/{uid}` — self-readable/writable for profile fields; `status` (approval) writable **only**
  by admin. Right now nothing stops a driver from writing `status: 'approved'` to their own
  document and bypassing approval entirely.
- `merchants/**`, `promoCodes/**`, `notifications/**` — public read, admin-only write.
- Admin identification via a custom claim, not an email allowlist in client code.

### 7.2 Missing composite indexes

Two driver queries need composite indexes that are not committed:

- `pendingOrdersStream` — `status ==` + `driverId ==` (`driver_firestore_service.dart:29-30`)
- `activeOrderStream` — `driverId ==` + `status whereIn` (`driver_firestore_service.dart:40-41`)

If these were created by clicking the console error link, they exist in production and nowhere
else. A fresh staging project will fail both queries. The driver's `onError` handlers surface this
as a generic "Could not load your active order" toast, making it look like a network problem.

### 7.3 No Cloud Functions

Several of the fixes in this document are *impossible* without server code: driver account
provisioning (§4), server-side commission (§6.3), promo redemption counting (§5), merchant order
counters (§10), push notification fan-out (§8), and midnight resets. Stand up a `functions/`
package before attempting them.

---

## 8. P1 — The requested image-upload feature does not exist

You asked specifically for upload-picture capability on merchants. It is not implemented anywhere.

- **Merchants:** `admin_panel/index.html:462` is a plain text input whose label reads
  *"Merchant Image URL (recommended 800×400 — Firebase Storage, Imgur, etc.)"* — the admin is
  expected to upload the file somewhere else by hand and paste a URL back in.
- **Menu items:** `app.js:930` is the same pattern — `<input id="mi-img" placeholder="https://…">`.
- `admin_panel/app.js` does not import `firebase-storage` at all (see imports, lines 6-8). The panel
  has no upload capability of any kind.

Both mobile apps *do* have working Storage uploads to copy from — `uploadAvatar`
(`customer_app/.../firestore_service.dart:318`) and `uploadDeliveryPhoto` /
`uploadProfilePhoto` (`driver_app/.../driver_firestore_service.dart:100,131`).

**Fix:** add `getStorage, ref, uploadBytes, getDownloadURL` to the admin imports; replace both URL
fields with a file input plus drag-and-drop zone, live preview, client-side resize/compression, and
a progress bar; upload to `merchants/{merchantId}/cover.jpg` and
`merchants/{merchantId}/menuItems/{itemId}.jpg`; write the resulting download URL to `imageUrl` so
the customer app picks it up with no change. Storage rules must permit admin write and public read.

Keep the URL field as a secondary option — do not remove it, since existing merchant records depend
on it.

---

## 9. P1 — Push notifications are non-functional end-to-end

The admin's Notifications screen is honest about being a log — the button literally reads "Log
Notification" (`app.js:1074`) — but the surrounding product is not wired up.

**Customer side:** `customer_app/pubspec.yaml:44` declares `firebase_messaging: ^15.0.0`, and
**not one line of the customer app imports or uses it.** No permission request, no token
registration, no foreground handler. Customers cannot receive a push notification under any
circumstances. The dependency is dead weight in the bundle.

**Driver side:** properly set up — `driver_app/lib/main.dart:41-62` requests permission, registers
a background handler, and persists `fcmToken` with refresh handling. But **nothing ever sends to
those tokens.** No Cloud Function reads `fcmToken`; no server exists. The token is collected and
never used.

**Admin side:** `sendNotif` (`app.js:1067`) writes a document to `notifications` and stops. Only the
customer app reads that collection (`firestore_service.dart:371-386`), so the message appears as an
in-app list item on the customer's Alerts tab if and only if the app is already open and the user
navigates there. The driver app never reads `notifications` at all — **selecting "All Drivers" or
"Everyone" as the audience delivers to nobody.**

**Consequence for the core promise of the product:** a driver whose phone is in their pocket is not
told a new order arrived. The driver dashboard only discovers orders while the app is foregrounded
and the driver is toggled online (`dashboard_screen.dart:205-220`). A backgrounded driver misses
every order. For a delivery app, this is a fundamental gap, not a polish item.

**Fix:** a Firestore-triggered Cloud Function on `notifications/{id}` that fans out to the right
token set; a second trigger on `orders/{id}` that pushes to online drivers on create and to the
customer on each status transition; and FCM initialisation in the customer app mirroring the
driver's.

---

## 10. P1 — Two advertised product lines are non-functional mockups

**Packages.** `home_screen.dart:287-298` — the "Submit Request" button validates that pickup and
delivery addresses are non-empty, then calls `Navigator.pop` and shows
*"Package request submitted! We'll contact you shortly."* **It writes nothing to Firestore.** No
order is created. The admin never sees it. Nobody will contact the customer, because no record of
their request exists anywhere. The customer has been told their request was received.

This is a user-facing falsehood in a shipped code path, reachable from the home screen's primary
category row (`home_screen.dart:46`, "Packages" is one of four top-level categories).

**Overseas.** `overseas_order_screen.dart` contains no Firestore writes at all (verified by grep for
`collection(`/`add(`/`set(`). Same class of problem.

**Fix:** either write these to an `orders` document with an appropriate `type` field and surface
them in the admin panel, or remove the entry points until they are built. Do not ship a success
toast for an action that did not happen.

---

## 11. P1 — Admin analytics report figures that can never change

**Merchant `ordersToday`** is set to `0` at creation (`app.js:847`) and **incremented by nothing** —
verified by grepping all three codebases; the only other references are the two places that
*display* it (`app.js:803`, `app.js:897`). The admin's merchant table and merchant detail panel
therefore show `0` orders for every merchant, forever, no matter how many orders that merchant
receives.

The name is also wrong for the storage model — a raw counter named `Today` has no reset mechanism.
The driver app hit this exact bug with `todayEarnings` and solved it correctly by deriving the
figure from today's delivered orders instead (`dashboard_screen.dart:149-161`, with a good comment
explaining why). Apply the same reasoning: derive `ordersToday` in the admin from the already-loaded
`orders` array rather than storing a counter.

**Promo `usedCount`** — same pattern, covered in §5.

**Merchant rating** — admin writes `rating: 5.0` at creation (`app.js:847`) and reads
`o.averageRating || o.rating` (`app.js:326`). Nothing ever computes `averageRating` for a merchant.
The customer's rating screen collects `merchantRating` on the order (`firestore_service.dart:289`)
but only aggregates the *driver's* rating (lines 293-310) — the merchant rating is written to the
order document and never rolled up. Every merchant shows a permanent 5.0.

**Driver rating breakdown** — `openDriverPanel` (`app.js:735-750`) looks for `ratingCounts` /
`ratingBreakdown`, which nothing writes; the customer's `submitRating` only maintains
`totalRatings` / `ratingCount` / `averageRating`. The panel correctly falls back to an honest
"No per-star rating data recorded yet" message rather than fabricating a distribution — that is
good judgement and worth preserving — but the underlying per-star data should be captured, which is
a one-field addition to the `submitRating` transaction.

---

## 12. P2 — Field-name mismatches in the customer's driver card

`order_status_screen.dart:499-501` reads three fields:

```dart
final vehicleMake  = _driver?['vehicleMake']  as String? ?? '';   // written by nothing
final vehicleModel = _driver?['vehicleModel'] as String? ?? '';   // admin only, never driver
final licensePlate = _driver?['licensePlate'] as String? ?? '';   // American spelling
```

Against what is actually written:

- Driver self-registration (`register_screen.dart:97-109`) writes `vehicleType`, `licencePlate`,
  `licenceNumber` — **British spelling**, and no `vehicleModel` or `vehicleMake` field exists in
  the registration form at all.
- Admin writes `vehicleModel` and `licencePlate` (`app.js:675-677`) — British spelling.

**Consequence:** `vehicleInfo` (line 502-506) resolves to an empty string for every driver, so the
customer tracking screen shows only a name and rating with no vehicle or plate. For a delivery
product, "which car am I looking for" is core information, and the customer has no way to identify
the approaching vehicle.

**Fix:** standardise on the British spelling already used by both writers (`licencePlate`,
`licenceNumber`), correct the customer reader, and add a vehicle make/model field to driver
registration — the admin form already has one, so the two forms are also inconsistent with each
other.

Related: the customer reads `averageRating` (line 498) which `submitRating` does maintain — that
one is correct.

---

## 13. P2 — The customer app seeds demo data into production

`home_screen.dart:67` calls `FirestoreService.seedMerchantsIfEmpty()` on every home-screen load. If
the `merchants` collection is ever empty, the **customer app writes 15 hardcoded demo merchants**
— Island Jerk Palace, Rasta Pasta, PharmaCare Rx — plus menu items, straight into the live database
(`firestore_service.dart:11-91`), complete with Unsplash stock photos and emoji.

Every one of those will appear in the admin panel's merchant list as if an administrator had created
it. The failure is silent by design (`catch (_) {}`, line 46, comment: *"Silent fail — app still
shows placeholder data"*).

This is fine for a demo and wrong for production: a client app must never be able to write to an
admin-owned collection, and correct security rules (§7.1) would reject it — which means this call
will begin failing silently the moment the backend is secured, which is the right outcome. Remove
the call and move seeding to a one-off admin script.

Note the demo data also uses `emoji`, `deliveryTime`, `deliveryFee`, and `promo` fields — which is
precisely why the customer app reads those field names (§6.1). The customer app was built against
its own seed data, and the admin panel was built against a different schema, and the two were never
reconciled. That is the root cause of most of §6.

---

## 14. P2 — Approval revocation does not take effect

`driver_app/lib/main.dart:65-78` checks `status == 'approved'` **once, at cold start**, to decide
between `DriverShell` and `PendingApprovalScreen`. `login_screen.dart:82-94` performs the same
one-shot check at sign-in.

Once a driver is inside `DriverShell`, nothing re-reads their approval status. `DashboardScreen`
subscribes to the driver document (`dashboard_screen.dart:85`) but only ever reads `isOnline` from
it (line 90) — `status` is ignored.

**Consequence:** an admin who rejects or suspends an active driver (`app.js:709-718`) does not
remove them. The driver keeps working, keeps receiving orders, and keeps accepting them until they
happen to force-quit and relaunch the app. For a suspension triggered by a safety incident, that is
a serious control failure.

Credit where due: the *reverse* direction is handled properly — `PendingApprovalScreen` watches its
own status live (`pending_approval_screen.dart:49-54`) with a comment explaining that the previous
version forced a restart. Apply the same treatment to the revocation direction: have
`DashboardScreen`'s existing driver-document listener check `status` and eject to
`PendingApprovalScreen` if it leaves `approved`.

---

## 15. P2 — No cancellation path for customers

Grepping the customer app for any cancellation write returns nothing — the only `cancel` matches
are `StreamSubscription.cancel()`. The customer app renders a "Cancelled" tab in order history
(`order_history_screen.dart:76`) and colours a cancelled badge (line 104), but **no customer-facing
action can ever produce that state.**

Only an admin can cancel, via the status dropdown. When they do:
- The driver's `activeOrderStream` (`whereIn ['confirmed','picked_up']`) drops the order with no
  notification — the driver's screen simply empties, as in §2.4.
- The customer's `_currentStep` returns `0` for `cancelled`, so the tracking screen shows
  **"Order Confirmed"** on a cancelled order. Actively misleading.

**Fix:** add a customer cancel action, permitted while `status == 'pending'` (before a driver has
committed) and behind a confirmation sheet. Handle `cancelled` explicitly in `_currentStep` /
`_statusLabel` with a distinct terminal presentation. Notify the driver when an order they hold is
cancelled.

---

## 16. What is genuinely well built

This audit is a defect list by design, so it under-represents the quality of the work. Several
things are done properly and should not be disturbed by the fixes above:

- **Order-claim race handling.** `acceptOrder` (`driver_firestore_service.dart:58-92`) is a real
  transaction that re-reads the order and aborts if another driver won, with a clear comment
  explaining the double-accept bug it prevents. This is exactly right.
- **Delivery finalisation is atomic.** `confirmDelivery` (line 109-129) batches the order update and
  the driver stat increment, so they cannot diverge.
- **Derived-not-stored earnings.** The `todayEarnings` reasoning (`dashboard_screen.dart:149-161`)
  is the correct instinct, correctly documented. §11 recommends extending it, not changing it.
- **Live approval screen.** `pending_approval_screen.dart` watching its own status is good.
- **Honest empty states.** The admin's driver rating breakdown refuses to synthesise a distribution
  it does not have (`app.js:735-750`), and the customer's tracking hero explicitly declines to fake
  a map (`order_status_screen.dart:209-211`). Both choose honesty over a prettier screen. Keep this.
- **Admin XSS hygiene.** Every interpolation in `app.js` goes through `esc()`. For a codebase built
  on string-concatenated HTML, the discipline is consistent — I found no unescaped user data path.
- **Design system.** SEDS is applied coherently across all three apps: shared token files, no
  `alert()`/`confirm()` in the admin (replaced by toasts and a proper focus-managing dialog),
  reduced-motion respected (`app.js:36`, and throughout the Flutter motion tokens), skeleton
  loaders on every async surface, keyboard handling and ARIA on admin interactive elements.
- **Stream error handling.** The driver app attaches `onError` to every subscription with a comment
  noting that a rules failure previously looked identical to "no data" — good defensive instinct.

The individual apps are well-crafted. The failure is at the seams between them.

---

## 17. Recommended order of work

**Phase 1 — Unblock correctness (nothing ships before this).**
1. Define the canonical order-status enum; fix all three apps (§2). Single highest-value change.
2. Fix admin driver assignment to set `confirmed` transactionally (§3).
3. Write and deploy `firestore.rules` + `storage.rules`; commit `firestore.indexes.json` (§7.1, §7.2).
4. Remove the customer-app seeder (§13).
5. Remove the admin "Add Driver" button pending §19 (§4).

**Phase 2 — Money and data integrity.**
6. Reconcile the merchant schema: `deliveryFee` as a number, `deliveryTime`, drop the `$`-prefixed
   `fee` string; fix the customer reader (§6.1).
7. Reconcile the promo schema; store `discount` + `promoCode` on the order; increment `usedCount`
   transactionally (§5, §6.2).
8. Standardise driver vehicle field names; add make/model to registration (§12).
9. Derive `ordersToday` and merchant `averageRating` rather than storing stale counters (§11).

**Phase 3 — Close the requested feature gaps.**
10. Firebase Storage image upload for merchants and menu items in the admin panel (§8).
11. Stand up `functions/`; implement push fan-out; initialise FCM in the customer app (§9).
12. Move driver commission computation server-side (§6.3).
13. Cloud Function for admin-initiated driver account provisioning; restore "Add Driver" (§4).

**Phase 4 — Complete the product surface.**
14. Wire Packages and Overseas to real orders, or remove their entry points (§10).
15. Customer-initiated cancellation + correct cancelled-state rendering in all three apps (§15).
16. Live approval revocation in the driver shell (§14).
17. Admin: a Customers page (the `users` collection has no admin surface at all — the admin can see
    orders but cannot look up the customer who placed them).

**Phase 5 — Verification, which this audit could not perform.**
18. Install the Flutter toolchain; run `flutter analyze` and `flutter test` on both apps in CI.
    The two existing workflows build APKs but there is no analyze or test gate.
19. Manual end-to-end pass on real devices against a **staging** Firebase project: place an order,
    watch it appear on the driver's dashboard, accept it, and confirm the customer's tracker
    advances through every step in realtime. That specific scenario is the one this audit predicts
    will fail today, and it is the one that must pass before launch.
20. Re-run this audit against the fixed code, with the toolchain present, including the visual pass
    that could not be done here.

---

## 18. Bottom line

Each app, viewed alone, looks close to production quality — the design system is disciplined, the
loading and empty states are considered, and the tricky concurrency in the driver's accept-order
path is handled correctly.

Viewed together, they do not form a working system. An order placed by a customer today will freeze
on the tracking screen the moment a driver accepts it, disappear from the customer's order list for
the entire delivery, charge a delivery fee that matches neither what was displayed nor what the
admin configured, and accept a promo code that discounts nothing. An order the admin dispatches by
hand will never be delivered at all. A driver the admin adds cannot log in. A driver the admin
suspends keeps working. None of this is protected by security rules.

The distance to production is not a long list of small polish items — it is roughly a dozen schema
decisions that were never made once and applied three times. Make them, then rebuild the seams.
The apps on either side of those seams are worth connecting properly.
