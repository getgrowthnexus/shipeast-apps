# ShipEast Driver App — Full Engineering Audit

**Audit date:** 2026-07-17
**Scope:** `driver_app/` (read-only). Every Dart file under `lib/`, Android config, `pubspec.yaml`.
**Codebase size:** 14 Dart files (~4,000 LOC), 1 service layer, 11 screens.

---

## 1. Overview

### App purpose
A Flutter driver-side companion app for the **ShipEast Jamaica** delivery platform. Drivers register, get admin-approved, go online, receive delivery requests in real time, accept them, confirm pickup at the merchant, deliver to the customer (with optional proof photo + note), and track earnings/history. It is one of three apps in the platform (customer app, admin panel, this driver app), all sharing a single Firebase project (`shipeast-1a1f6`).

### Tech stack
| Layer | Technology |
|---|---|
| Framework | Flutter (Material 2 — `useMaterial3: false`) |
| Language | Dart, SDK constraint `^3.11.5` |
| Backend | Firebase (Auth, Cloud Firestore, Storage, Cloud Messaging) |
| State mgmt | Vanilla `setState` + `StreamSubscription` / `StreamBuilder` + one `ValueNotifier` |
| Fonts | `google_fonts` (Montserrat, Inter, Nunito, Dancing Script) — fetched at runtime |
| Min Android SDK | 23 (Android 6.0) · target/compile inherited from Flutter · Java 17 |
| App ID | `com.shipeast.shipeast_driver` |

### Dependencies (`pubspec.yaml`)
| Package | Version | Used for |
|---|---|---|
| `firebase_core` | ^3.0.0 | Firebase init (`main.dart`, `_initFirebase`) |
| `firebase_auth` | ^5.0.0 | Email/password auth — login, register, sign-out, current UID |
| `cloud_firestore` | ^5.0.0 | All data: `drivers` + `orders` collections |
| `firebase_storage` | ^12.0.0 | Delivery proof photos + driver avatars |
| `firebase_messaging` | ^15.0.0 | FCM token save + permission request (see §4 for gaps) |
| `image_picker` | ^1.1.2 | Camera/gallery for delivery photo & avatar |
| `shared_preferences` | ^2.3.2 | **Declared but never imported/used anywhere** |
| `google_fonts` | ^6.2.1 | Typography |
| `cupertino_icons` | ^1.0.8 | iOS-style icons (unused in practice) |
| `flutter_lints` | ^6.0.0 (dev) | Lints |

> **Notable absence:** no `geolocator` / `location` / maps package. There is **no GPS or live location tracking** anywhere — "location" is text addresses only (§4, §7).

### Assets
- `assets/logo.png` (only declared asset).

### Firebase config
- `lib/firebase_options.dart` — **Android only**. iOS explicitly throws `UnsupportedError('Firebase is not configured for iOS yet.')`; web throws too.
- `android/app/google-services.json` present.
- Project: `shipeast-1a1f6`, storage bucket `shipeast-1a1f6.firebasestorage.app`.

---

## 2. Architecture

### Folder structure
```
lib/
├── main.dart                        # Bootstrap, FCM init, auth-gate routing, DriverShell (bottom nav)
├── app_theme.dart                   # AppTheme: colors, text styles, input decoration, ThemeData
├── firebase_options.dart            # Android-only FirebaseOptions
├── services/
│   └── driver_firestore_service.dart # ALL Firestore/Storage/FCM data access (static methods)
└── screens/
    ├── login_screen.dart
    ├── register_screen.dart
    ├── pending_approval_screen.dart
    ├── dashboard_screen.dart        # Home tab (+ DriverShell is in main.dart)
    ├── new_order_screen.dart        # Incoming order modal w/ 60s timer
    ├── pickup_confirmation_screen.dart
    ├── delivery_confirmation_screen.dart
    ├── history_screen.dart          # History tab
    ├── earnings_screen.dart         # Earnings tab (+ _BarChartPainter)
    └── profile_screen.dart          # Profile tab
```

### State management
- **No** Provider/Riverpod/Bloc/GetX. Pure `StatefulWidget` + `setState`.
- Realtime data via `StreamSubscription` (Dashboard) and `StreamBuilder` (History, Earnings).
- Cross-screen shared state: a single `ValueNotifier<String> _driverNameNotifier` created in `_DriverShellState`, passed to `DashboardScreen` (reads) and `ProfileScreen` (writes on save). This is the only shared-state wiring; everything else re-fetches per screen.

### Navigation / routing
- Named routes registered in `ShipEastDriverApp.build`: `/login` → `LoginScreen`, `/dashboard` → `DriverShell`. `home` is resolved dynamically by `_resolveHome()`.
- Everything else uses imperative `Navigator.push` / `pushReplacement` / `pushAndRemoveUntil` with `MaterialPageRoute` (no route names → `popUntil(route.settings.name == '/dashboard' || route.isFirst)` in delivery success relies on `isFirst` fallback).
- **Auth gate** (`main._resolveHome`): if no user → `LoginScreen`; if `drivers/{uid}.status == 'approved'` → `DriverShell`; else → `PendingApprovalScreen`.
- Bottom nav is an `IndexedStack` of 4 tabs in `_DriverShellState` (Home / History / Earnings / Profile), custom-built `Row` (not `BottomNavigationBar`).

### Data flow
1. `main()` → init Firebase (5-attempt retry backoff) → init FCM → `_resolveHome()` → `runApp`.
2. All reads/writes go through **`DriverFirestoreService`** (static methods). Screens never touch `FirebaseFirestore.instance` through the service *except* several that call it directly (inconsistency — see §7): `main.dart`, `login_screen.dart`, `register_screen.dart`, `profile_screen.dart` all use `FirebaseFirestore.instance` directly.
3. Dashboard subscribes to 3 streams (driver doc, active order, order history) in `initState` and manages a 4th (pending orders) dynamically based on online/active state.

---

## 3. Screen-by-screen inventory

Legend: **✅ Functional** (real data, working) · **🟡 Partial** · **🔵 UI-only/stub**

### 3.1 `LoginScreen` — ✅ Functional
- **Widgets:** `Form`, 2 `TextFormField` (email, password w/ obscure toggle), `ElevatedButton`, "Forgot Password?" text, register link.
- **Reads/Writes:** `FirebaseAuth.signInWithEmailAndPassword`; then reads `drivers/{uid}.status` to route to `/dashboard` (approved) or `PendingApprovalScreen`.
- **Real:** auth + status gate. Human-readable error mapping (`_authErrorMessage`).
- **🔵 Stub:** "Forgot Password?" `onTap: () {}` — does nothing.
- No inline field validation beyond empty check (validator on `Form` not wired to `_formKey.validate()`).

### 3.2 `RegisterScreen` — ✅ Functional
- **Widgets:** `Form` w/ 7 fields (name, phone, email, password, confirm, licence plate, licence number), vehicle-type chip selector (Motorcycle/Car/Van/Truck), create button, sign-in link.
- **Writes:** `createUserWithEmailAndPassword` → creates `drivers/{uid}` doc with: `name, phone, email, vehicleType, licencePlate, licenceNumber, status:'pending', isOnline:false, rating:5.0, totalTrips:0, createdAt`.
- **Real:** full account creation + Firestore profile. Client-side validation (name/email present, password ≥6, match).
- Routes to `PendingApprovalScreen`.

### 3.3 `PendingApprovalScreen` — 🟡 Partial (UI complete, no live status watch)
- **Widgets:** pulsing animated logo, "Application Under Review" badge, 3-step progress (`_buildStep`: Received ✓ / Background Check ⏳ / Activated), "Back to Login" button.
- **Reads/Writes:** **none.** The 3 steps are **hardcoded** static UI — it does *not* listen to `drivers/{uid}.status`. A driver approved while on this screen sees no change; must sign out & back in (or restart) to reach the dashboard. Message claims "You will receive a notification once approved" but no such notification is implemented (§4).

### 3.4 `DashboardScreen` (Home tab) — ✅ Functional (most complex screen)
- **Widgets:** red header (avatar, greeting, online toggle, stats strip: earnings/deliveries/status), status chip (ONLINE/OFFLINE/DELIVERING), one of {active-order card, offline banner, ready card}, 4 quick-action cards, pulse animations.
- **Streams (all realtime):**
  - `driverStream(uid)` → reads `isOnline`, `todayEarnings`. Toggling online starts/stops the pending-orders listener.
  - `activeOrderStream(uid)` → driver's order in status `confirmed`/`picked_up`; drives the active-order card and suppresses new-order listening.
  - `driverOrderHistoryStream(uid)` → computes `_todayDeliveries` (delivered today).
  - `pendingOrdersStream()` (dynamic) → when online & no active order, **auto-navigates** to `NewOrderScreen` for the first unseen pending order (`_seenOrderIds` dedup, `_navigating` guard).
- **Writes:** `setDriverOnline(uid, bool)` on toggle.
- **Real:** online toggle, live earnings/deliveries, active-order resume (`_continueActiveOrder` → Pickup or Delivery screen by status).
- **🔵 Stub:** "Help & Support" quick action → "coming soon" dialog (`_showHelpDialog`).
- **⚠️ Bug:** `_todayEarnings` comes from the driver doc's `todayEarnings` field, which is **incremented on every delivery but never reset daily** (§7) — so "Today's Earnings" here drifts from the Earnings tab's correctly period-filtered figure.

### 3.5 `NewOrderScreen` — ✅ Functional
- **Widgets:** pulsing "New Delivery Request" banner, 60s circular countdown timer (`_startTimer`, color shifts ≤20s/≤10s), 3 stat cards (earnings=total/10, item count, payment method), order-details card (pickup→delivery route, items summary, payment/total), Reject / Accept buttons, expired state.
- **Reads:** all from the `order` map passed in (`merchantName, customerName, deliveryAddress, merchantAddress|address, total, paymentMethod, items[]`).
- **Writes:** `acceptOrder(orderId, uid)` → sets `driverId, driverName, driverPhone, status:'confirmed', acceptedAt`. → `pushReplacement` to `PickupConfirmationScreen`.
- **🟡 Notes:**
  - **Reject** just `Navigator.pop` — records nothing; order stays pending for others (fine), but the driver's `_seenOrderIds` prevents re-offer that session.
  - **Timer expiry** only closes/blocks the screen; it does **not** cancel or reassign the order. Expiry is purely client-side cosmetic.
  - Earnings preview `_total ~/ 10` (10% commission) is a **client-side hardcoded** formula, duplicated across 4 screens.

### 3.6 `PickupConfirmationScreen` — ✅ Functional
- **Widgets:** animated "Order Accepted" banner, merchant card, deliver-to card, itemized list w/ per-line price + total, "Confirm Pickup" button.
- **Writes:** `confirmPickup(orderId)` → `status:'picked_up', pickedUpAt`. → `pushReplacement` to `DeliveryConfirmationScreen`.
- **Real:** status transition. Reads order map only.

### 3.7 `DeliveryConfirmationScreen` — ✅ Functional
- **Widgets:** gradient "Almost There" banner, delivery details, **photo picker** (camera/gallery/remove via bottom sheet, 160px preview), delivery **note** field, "Mark as Delivered" button, success dialog (earnings + COD collect reminder).
- **Writes:**
  - Optional `uploadDeliveryPhoto(orderId, file)` → Storage `orders/{orderId}/delivery_photo.jpg`; failure is swallowed and delivery proceeds.
  - `confirmDelivery(orderId, uid, total, photoUrl, note)` → **batched**: order `{status:'delivered', deliveredAt, deliveryPhotoUrl?, deliveryNote?}` + driver `{totalTrips +1, todayEarnings += total/10}`.
- **Real:** full completion, atomic-ish batch write, image upload. Success dialog `popUntil` back to dashboard.
- `_isCod` derived from payment method string; shows "Collect $X from customer".

### 3.8 `HistoryScreen` (History tab) — ✅ Functional
- **Widgets:** red header, 3 tabs (All/Completed/Cancelled), summary strip (total/completed/rate%), `ListView.separated` of order cards (icon, merchant, short ID, commission vs total, status badge, route, formatted date), empty state.
- **Reads:** `driverOrderHistoryStream(uid)` (realtime; client-sorted newest first).
- **Real:** live history, filtering, completion-rate calc, relative date formatting (`_formatDate`: Today/Yesterday/Mon D).
- **🟡 Note:** the "Cancelled" tab filters `status == 'cancelled'`, but **the driver app never writes `'cancelled'`** — cancellations would originate from the customer/admin apps. Tab is functional but may always be empty from this app's perspective.

### 3.9 `EarningsScreen` (Earnings tab) — ✅ Functional
- **Widgets:** red header, period tabs (Today/This Week/This Month), 2 summary cards (total earned, deliveries), **custom bar chart** (`_BarChartPainter`, `CustomPaint`), recent-trips list (top 5), payout card ("Every Friday").
- **Reads:** `driverOrderHistoryStream(uid)` via `StreamBuilder`; filters delivered orders by `deliveredAt` within period; sums `total/10`.
- **Real:** all figures computed from live delivered orders. Bar chart buckets: 8×2h blocks (today), 7 days (week), 4 weeks (month). Highlights max bar; placeholder bars when empty.
- **🔵 Static:** "Next Payout — Every Friday" is a hardcoded label; **no actual payout system** exists.

### 3.10 `ProfileScreen` (Profile tab) — 🟡 Partial
- **Widgets:** red header w/ avatar (tap → camera/gallery upload), edit toggle, view mode (stats: trips/completion/rating + info rows: phone/email/vehicle/licence), edit form (name/phone/email/vehicle chips/licence + save), rating card, settings list, sign-out tile.
- **Reads:** `_loadProfile()` one-shot `get()` of `drivers/{uid}` (`name, phone, email, vehicleType, licencePlate, avatarUrl, rating, totalTrips`).
- **Writes:** `_saveProfile()` updates `name, phone, email, vehicleType, licencePlate`. Avatar via `uploadProfilePhoto` → `drivers/{uid}/avatar.jpg` → updates `avatarUrl`. Updates shared `driverNameNotifier`.
- **🔵 Stubs:** Notifications, Privacy & Security, Help & Support → `_showComingSoon` dialogs. About → static dialog.
- **⚠️ Bogus metric:** "Completion" = `totalTrips/(totalTrips+1)*100` — a meaningless formula that just approaches 100% as trips grow (e.g. 1 trip → 50%, 9 trips → 90%). Not a real completion rate.
- **Static:** `rating` is read-only (set to 5.0 at registration; only customer/admin could change it — driver app never writes rating).

### 3.11 `DriverShell` (in `main.dart`) — ✅ Functional
- Bottom-nav container hosting the 4 tabs via `IndexedStack`; loads driver name once into the notifier.

---

## 4. Firebase & backend integration

### Firestore collections

#### `drivers/{uid}`
| Field | Written by | Read by | Mode |
|---|---|---|---|
| `name, phone, email, vehicleType, licencePlate, licenceNumber` | register, profile edit | login gate, profile, `acceptOrder` (name/phone) | **REAL** |
| `status` (`pending`/`approved`) | register (`pending`) — **approval set externally (admin)** | `_resolveHome`, login | **REAL** (approval is out-of-app) |
| `isOnline` | dashboard toggle (`setDriverOnline`) | dashboard `driverStream` | **REALTIME** |
| `rating` (default 5.0) | register only (in-app) | profile | **STATIC in this app** |
| `totalTrips` | `confirmDelivery` (increment) | profile | **REAL** |
| `todayEarnings` | `confirmDelivery` (increment) | dashboard `driverStream` | **REAL but never reset — see §7** |
| `fcmToken` | `saveFcmToken`, token-refresh listener | (consumed server-side, not in app) | **REAL (write-only here)** |
| `createdAt` | register | — | REAL |
| `avatarUrl` | profile photo upload | profile | REAL |

- Driver doc reads: **REALTIME** on dashboard (`driverStream` = `.snapshots()`); **one-shot** in login gate, `_resolveHome`, `_loadDriverName`, profile `_loadProfile`, `acceptOrder`.

#### `orders/{orderId}` (orders originate from the **customer app**, not created here)
| Query / write | Location | Mode |
|---|---|---|
| `where status=='pending' AND driverId==null` | `pendingOrdersStream` | **REALTIME** (new-order feed) |
| `where driverId==uid AND status in [confirmed, picked_up]` | `activeOrderStream` | **REALTIME** (active order) |
| `where driverId==uid` (client-sorted) | `driverOrderHistoryStream` | **REALTIME** (history + earnings) |
| `update` → confirmed (+driverId/Name/Phone/acceptedAt) | `acceptOrder` | **REAL** |
| `update` → picked_up (+pickedUpAt) | `confirmPickup` | **REAL** |
| `batch update` → delivered (+deliveredAt, photo, note) | `confirmDelivery` | **REAL** |

- Order fields read (never written by driver): `merchantName, merchantAddress|address, customerName, deliveryAddress, total, paymentMethod, items[] ({name, quantity, price})`.

### Firebase Auth — **REAL**
Email/password sign-in, sign-up, sign-out, `currentUser.uid`. No phone/social auth, no email verification, no password reset (button is dead).

### Firebase Storage — **REAL**
- `orders/{orderId}/delivery_photo.jpg` (delivery proof)
- `drivers/{uid}/avatar.jpg` (profile photo)
Both via `image_picker` (quality 85). Delivery upload failure is non-blocking.

### Firebase Messaging (FCM) — 🟡 **Partial / write-only**
- `main._initFCM`: registers background handler, requests notification permission, saves token to `drivers/{uid}.fcmToken`, listens for token refresh.
- `onMessage.listen` is registered but **does nothing** (comment: "handled by the active screen" — but no screen consumes it).
- **No `onMessageOpenedApp` / notification tap handling. No local-notification display.** So push notifications are effectively **not surfaced** in-app.
- **New orders are delivered via Firestore realtime polling (`pendingOrdersStream`), NOT via FCM push.** This means a driver only sees new orders while the app is **foregrounded and online** — no background/killed-app order alerts. The token is saved presumably for a server/admin-side Cloud Function to send pushes, but no such consumption exists in this repo.

### Location / GPS — ❌ **Not implemented**
No location package, no permission in manifest, no lat/long fields, no map. All "location" is text addresses read from the order. `Icons.location_on` is decorative only. **There is no driver live-tracking.**

### Android permissions (`AndroidManifest.xml`)
- `INTERNET`, `READ_EXTERNAL_STORAGE` (maxSdk 32), `READ_MEDIA_IMAGES` (for `image_picker`).
- Impeller disabled (workaround for TECNO KM7 Gralloc driver).
- **No** camera / location / notification permissions declared (camera works via `image_picker` intent; POST_NOTIFICATIONS not declared — may affect Android 13+ notification permission).

---

## 5. Feature completeness matrix

| Feature | Status | Notes |
|---|---|---|
| Driver registration (+ vehicle info) | ✅ Done | Writes full `drivers` doc |
| Login + approval gate | ✅ Done | Status-based routing |
| Pending-approval screen | 🟡 Partial | Static steps; **no live status listener** |
| Forgot password | 🔵 Not started | Dead button |
| Online/offline toggle | ✅ Done | Realtime `isOnline` |
| Receive new orders | ✅ Done (realtime) | Firestore stream; **foreground-only, no push** |
| Accept order | 🟡 Partial | Works, but **not transactional → double-accept race** (§7) |
| Reject order | 🟡 Partial | Cosmetic only; nothing recorded/reassigned |
| Order auto-expiry (60s) | 🔵 UI-only | Client timer; order not cancelled/reassigned |
| Confirm pickup | ✅ Done | `status:picked_up` |
| Confirm delivery (photo + note) | ✅ Done | Batched write, Storage upload |
| Active-order resume | ✅ Done | Survives app relaunch via stream |
| Delivery history | ✅ Done | Realtime, filterable |
| Earnings + charts | ✅ Done | Computed from delivered orders |
| Payouts | 🔵 UI-only | "Every Friday" label; no payout backend |
| Profile view/edit | ✅ Done | Real read/write |
| Avatar upload | ✅ Done | Storage |
| Driver rating | 🟡 Partial | Displayed; never updated by this app |
| Completion % metric | ⚠️ Broken | Meaningless `n/(n+1)` formula |
| Today's earnings (dashboard) | ⚠️ Buggy | `todayEarnings` never resets daily |
| FCM push notifications | 🟡 Partial | Token saved; **no in-app handling/display** |
| Live GPS tracking | 🔵 Not started | No location support at all |
| Settings (notifications/privacy/help) | 🔵 Not started | "Coming soon" dialogs |
| iOS support | 🔵 Not started | `firebase_options` throws for iOS |
| `shared_preferences` usage | ❌ Unused | Dependency declared, never used |

---

## 6. Order / delivery lifecycle (end-to-end)

```
[Customer app creates order: status='pending', driverId=null]  ← external
        │
        ▼  (REALTIME: pendingOrdersStream, only while driver is online & has no active order)
DashboardScreen._startListening → auto-push NewOrderScreen         [REAL stream]
        │
        ├─ Reject → Navigator.pop (order untouched; re-offer blocked for session)   [cosmetic]
        ├─ 60s timer expires → screen blocks (order NOT cancelled/reassigned)        [cosmetic]
        │
        ▼  Accept → acceptOrder()  status='confirmed', driverId/Name/Phone, acceptedAt   [REAL, non-atomic]
PickupConfirmationScreen
        │
        ▼  Confirm Pickup → confirmPickup()  status='picked_up', pickedUpAt              [REAL]
DeliveryConfirmationScreen
        │  (optional) uploadDeliveryPhoto → Storage                                      [REAL, non-blocking]
        ▼  Mark Delivered → confirmDelivery() BATCH:
             orders/{id}: status='delivered', deliveredAt, deliveryPhotoUrl?, deliveryNote?
             drivers/{uid}: totalTrips+1, todayEarnings += total/10                      [REAL, atomic batch]
        │
        ▼  Success dialog → popUntil dashboard
[activeOrderStream now empty → dashboard resumes new-order listening]                    [REAL]
```

**Real vs mocked:** Every state transition (pending→confirmed→picked_up→delivered) is a **real Firestore write**, and every feed is a **real realtime stream**. The only mocked/cosmetic pieces are: the **reject** action, the **60-second expiry** (no server-side timeout), FCM **push delivery** of orders, and **payouts**. Resume-after-restart works because the active order is derived from a live query, not local state.

---

## 7. Known issues, TODOs, broken / incomplete flows, hardcoded values

### Correctness / data bugs
1. **`acceptOrder` is not atomic (double-accept race).** `driver_firestore_service.dart:56` does an unconditional `.update()` — no transaction re-checking `driverId == null`. Two online drivers can accept the same pending order; the second silently overwrites the first. Should be a `runTransaction` that aborts if `driverId != null` or `status != 'pending'`.
2. **`todayEarnings` never resets.** `confirmDelivery` increments `drivers/{uid}.todayEarnings` (`:97`) but nothing ever zeroes it at day rollover. The dashboard's "Today's Earnings" (`dashboard_screen.dart:76`) therefore accumulates lifetime commission, contradicting the Earnings tab (which correctly filters by `deliveredAt`). Either drop the field and compute from orders, or add a daily reset (Cloud Function / on-read date check).
3. **Bogus "Completion" metric.** `profile_screen.dart:497` — `totalTrips/(totalTrips+1)*100`. Not a real completion rate; remove or compute from `delivered / (delivered+cancelled)`.
4. **Streams have no `onError`.** None of the `.listen(...)` / `StreamBuilder`s handle errors. The composite queries `pendingOrdersStream` (status + driverId isNull) and `activeOrderStream` (driverId + status whereIn) **require Firestore composite indexes**; if missing, the streams throw and the UI silently shows nothing (dashboard) or spins/empties (History/Earnings). No `firestore.indexes.json` exists in the repo — indexes must be created in console or these features break in production.

### Incomplete / stub flows
5. **PendingApprovalScreen doesn't watch status** — approved drivers must relaunch/sign-in again. Add a `drivers/{uid}.snapshots()` listener that auto-advances to `DriverShell`.
6. **Forgot Password** (`login_screen.dart:222`) — dead `onTap`.
7. **Reject / 60s expiry** are cosmetic (no backend effect / no reassignment).
8. **FCM not consumed** — `onMessage` empty; no `onMessageOpenedApp`; no local notifications; `POST_NOTIFICATIONS` permission not declared for Android 13+. Background/killed-app order alerts don't work.
9. **Coming-soon stubs:** Help & Support (dashboard + profile), Notifications, Privacy & Security.
10. **No payout system** — "Every Friday" is decorative.
11. **Driver rating** is display-only; never updated in this app.

### Hardcoded values that should be dynamic
12. **10% commission** (`total ~/ 10` / `total / 10`) hardcoded and **duplicated in 5 places**: `driver_firestore_service.dart:87`, `new_order_screen.dart:216`, `delivery_confirmation_screen.dart:201`, `earnings_screen.dart` (bars + fold), `history_screen.dart:267`. Should come from a config/remote value and live in one helper.
13. **Currency formatting** (`_formatPrice`/`_formatEarnings`) — the `$X,XXX` formatter is copy-pasted into 5 screens; assumes JMD-style whole-dollar integers.
14. **Payout cadence "Every Friday"**, **"24–48 hours" approval**, **"Kingston, JA"** location label — all hardcoded strings.
15. **Registration defaults** `rating:5.0` hardcoded.

### Platform / build
16. **iOS unsupported** — `firebase_options.dart` throws for iOS; no `ios/` Firebase config.
17. **Release build signed with debug keys** (`build.gradle.kts` `signingConfig = signingConfigs.getByName("debug")`) and `isMinifyEnabled=false` — not shippable to Play Store as-is.
18. **`shared_preferences` unused** — remove or use (e.g. cache online state / onboarding).
19. **Inconsistent data access** — `main.dart`, `login`, `register`, `profile` bypass `DriverFirestoreService` and call `FirebaseFirestore.instance` directly. Centralize.
20. **Deprecated API mix** — `Color.value` (`app_theme.dart:103`) and `withOpacity` (login/register) alongside the newer `withValues(alpha:)` used elsewhere. Minor, but will warn/deprecate.
21. **No automated tests** — only default `flutter_test` dep; zero test files.
22. **API keys in source** — Firebase Android API key is committed in `firebase_options.dart` + `google-services.json` (normal for Firebase, but security depends entirely on **Firestore/Storage rules**, which are **not present in this repo** — verify they exist server-side and restrict `drivers`/`orders` appropriately).

---

## 8. What's next — prioritized

### P0 — Correctness & safety (do first)
1. **Make `acceptOrder` a transaction** that aborts if the order is already claimed (prevents double-accept).
2. **Fix "Today's Earnings"**: compute from delivered orders (like the Earnings tab) or add a daily reset for `todayEarnings`.
3. **Create/commit Firestore composite indexes** for the pending, active, and history queries; add `onError` handling + error UI to all streams.
4. **Verify Firestore & Storage security rules** exist and scope access (a driver should only read pending/own orders and write own driver doc/order transitions). Not in repo — confirm server-side.

### P1 — Core UX gaps
5. **Live approval on PendingApprovalScreen** (snapshot listener → auto-enter dashboard).
6. **Wire FCM properly**: consume `onMessage`/`onMessageOpenedApp`, show local notifications, declare `POST_NOTIFICATIONS`; add a server Cloud Function to push new-order alerts so drivers get them when backgrounded.
7. **Implement Forgot Password** (`sendPasswordResetEmail`).
8. **Handle reject & expiry server-side** (record rejection / release order back to pool / reassign; server-side 60s timeout).

### P2 — Feature completion
9. **Live GPS tracking** — add `geolocator`, write driver location to Firestore (or Realtime DB), show ETA/route (needs a maps SDK). Currently entirely absent.
10. **Real payout tracking** (ledger of commissions, payout status).
11. **Fix or remove the completion-% metric**; surface real rating updates.
12. Build out Notifications / Privacy / Help & Support screens.

### P3 — Hygiene & release-readiness
13. **Centralize** commission %, currency formatting, and Firestore access into shared helpers/config.
14. **Proper release signing** + enable minify/shrink; remove debug signing.
15. **iOS support** (FlutterFire configure for iOS) if targeting iOS.
16. Remove unused `shared_preferences`; modernize deprecated `Color.value`/`withOpacity` calls.
17. **Add tests** — at minimum widget tests for the order lifecycle and unit tests for earnings/period math.

---

*End of audit — driver_app. No code was modified.*
