# ShipEast Admin Panel — Full Engineering Audit

**Audited:** 2026-07-17
**Scope:** `/workspaces/Shipeast-App/admin_panel/` (read-only)
**Files audited:** `index.html` (1,566 lines — the entire application), `firebase.json`, `.firebaserc`
**Firebase project:** `shipeast-1a1f6`

---

## 1. Overview

**Purpose.** A single-page, browser-based admin/back-office portal for the ShipEast Couriers & Bearer Services delivery platform (Jamaica). It lets a super-admin log in and manage the live operational data shared with the customer app and driver app: orders, drivers, merchants (and their menu items), promo codes, push notifications, and an analytics dashboard.

**Tech stack.**
- **Pure vanilla HTML/CSS/JS** — no framework (no React/Vue/Angular), no build step, no bundler, no `package.json`, no `node_modules`. The entire app is one self-contained `index.html`.
- **JavaScript style:** ES module (`<script type="module">`) for the Firebase imports, but the app code itself is written in old-school ES5 (`var`, `function`, no arrow functions in app logic, string-concatenated HTML). Functions are hoisted to `window` at the bottom to support inline `onclick`/`oninput` handlers.
- **Firebase 10.12.0 modular SDK** loaded directly from the Google CDN (`gstatic.com`) — Auth + Firestore only.
- **State model:** In-memory "local data mirrors" (`orders`, `drivers`, `merchants`, `promoCodes`, `notifHistory`) kept in sync by Firestore `onSnapshot` realtime listeners, re-rendered into the DOM on every snapshot.

**Hosting.** Firebase Hosting. `firebase.json` serves the current directory (`"public": "."`) as static files; `.firebaserc` pins the default project to `shipeast-1a1f6`. No Cloud Functions, no rewrites, no emulator config.

**External scripts / CDNs.**
| Resource | Source | Purpose |
|---|---|---|
| Montserrat + Inter fonts | `fonts.googleapis.com` | Typography |
| `firebase-app.js` 10.12.0 | `gstatic.com` | Firebase core |
| `firebase-auth.js` 10.12.0 | `gstatic.com` | Admin login |
| `firebase-firestore.js` 10.12.0 | `gstatic.com` | All data reads/writes |

No analytics, no charting library (charts are hand-rolled with CSS bars), no icon font (emoji used as icons).

---

## 2. Architecture

**File structure.** Flat — everything is `admin_panel/index.html`. Three logical layers all live in that one file:
1. `<style>` (lines 8–254): full design system — CSS variables, login, sidebar shell, topbar, cards/tables/badges, tabs, modals, side panel, status-flow, notifications preview, promo preview, analytics bar/zone/payment charts, responsive breakpoints.
2. `<body>` markup (lines 256–546): login page, app shell (sidebar + topbar + 7 pages), mobile overlay, right-hand side panel, and two modals (driver, merchant).
3. `<script type="module">` (lines 548–1564): all logic.

**Page organization.** A classic show/hide SPA. All 7 pages exist in the DOM simultaneously as `.page` divs (`#page-dashboard` … `#page-analytics`); `navTo(page)` (line 620) toggles the `.active` class on both the nav item and the page, and updates the breadcrumb/title. No router, no URL hash — navigation state is not preserved on refresh (always lands on Dashboard).

**Firebase initialization** (lines 550–564): imports the modular SDK, defines `firebaseConfig` inline, and creates `app`/`auth`/`db` singletons at module load.

**Auth gating** (lines 1532–1544): `onAuthStateChanged` is the single entry gate. Logged in → hide `#login-page`, show `#app`, set the avatar name, call `initApp()`. Logged out → show login, `stopListeners()`, and clear all in-memory arrays.

**Data flow.** `initApp()` (line 1519) paints loading spinners, then `startListeners()` (line 650) attaches five `onSnapshot` listeners (orders, drivers, merchants, promoCodes, notifications) plus an on-demand sixth for a merchant's `menuItems` subcollection. Each listener maps Firestore docs into a normalized local object (with generous field fallbacks) and calls the relevant `render*()` functions. All rendering is full-innerHTML replacement.

**Event handling.** Almost entirely **event-delegation** based: one global `click` listener (line 1481) dispatches via `data-action`/`data-page` attributes; one `change` listener (line 1511) for toggles; one `input` listener for the orders search; one `keydown` for Enter-to-login. A handful of buttons still use inline `onclick` (login, save-driver, save-merchant, send-notif, create-promo, save-order-changes, menu-item actions), which is why those functions are re-exposed on `window` (lines 1547–1558).

---

## 3. Page / Section-by-Section Inventory

### Login (`#login-page`, lines 259–269)
- **Status:** ✅ Fully functional.
- Email + password fields, `doLogin()` (line 601) calls `signInWithEmailAndPassword`. Loading spinner on submit, inline error handling with friendly messages for bad-credential codes, Enter-key submits. No "forgot password", no signup (by design — admin users are created manually in the Firebase console, per the comment on line 600).

### Dashboard (`#page-dashboard`, lines 314–325 / `renderDashboard()` line 761)
- **Status:** ✅ Functional, real data.
- **4 stat cards:** Orders Today (count of today's orders), Revenue Today (sum of `rawTotal` for today's *delivered* orders), Pending Orders (status pending), Active Drivers (drivers with `isOnline`).
- **Recent Orders table:** first 10 orders, with a view (👁) action opening the order side panel.
- ⚠️ Card labels vs. reality: card 2 header text is "Revenue Today" but the HTML `sc-lbl` static label still reads "Revenue Today"/sub "Delivered orders" — consistent. Fine.

### Orders (`#page-orders`, lines 328–338 / `renderOrders()` line 800)
- **Status:** ✅ Functional, real + realtime.
- **Tabs:** All / Active / Completed / Cancelled with live counts (`updateOrdersTabs()` line 788). Note the static HTML has hardcoded placeholder counts (`All 48`, `Active 12`, etc., lines 331–334) but these are immediately overwritten by `updateOrdersTabs()` on first snapshot.
- **Search:** client-side filter over id/customer/merchant.
- **Table:** id, customer, merchant, driver, total, payment, status badge, time, view action.
- **Order side panel** (`openOrderPanel()` line 824): status-flow stepper, customer/merchant/driver blocks, items list, order total, **admin actions** — assign driver (dropdown of approved drivers with online dots) + update status (dropdown) → `saveOrderChanges()` (line 891) writes `driverId/driverName/driverPhone/status` back to the order doc. Fully wired.

### Drivers (`#page-drivers`, lines 341–348 / `renderDrivers()` line 909)
- **Status:** ✅ Functional, real + realtime, full CRUD + approval workflow.
- **Stat cards:** Total / Online / On Delivery / Pending Approval.
- **Table:** name (with online dot), phone, vehicle type, plate, rating (stars), trips, status badge, and a context-sensitive "Active" column:
  - `pending` → **Approve / Reject** buttons.
  - `rejected` → "Rejected ↩" badge (click to re-approve).
  - `approved` → online/offline toggle.
- **Actions:** view (driver profile panel), edit, delete.
- **Add/Edit modal** (`openDriverModal()` line 953, `saveDriver()` line 970): name, phone, email, vehicle type/model, plate, licence number, status. Add creates with `rating:5.0, totalTrips:0`; new drivers with status "Active" are written as `approved`.
- **Driver profile panel** (`openDriverPanel()` line 1008): avatar, contact, vehicle, performance, **rating breakdown** (⚠️ *fabricated distribution*, see §7), and recent deliveries (filtered by driver name match).

### Merchants (`#page-merchants`, lines 351–358 / `renderMerchants()` line 1048)
- **Status:** ✅ Functional, real + realtime, full CRUD + menu-item subcollection management.
- **Stat cards (g3):** Total / Open Now / Closed.
- **Table:** merchant (image or category icon), category, phone, address, orders-today, rating, status, open/closed toggle, view/edit/delete.
- **Add/Edit modal** (`openMerchantModal()` line 1070, `saveMerchant()` line 1088): name, category, owner, phone, email, delivery fee, hours, status, address, image URL.
- **Merchant profile panel** (`openMerchantPanel()` line 1114) with **two tabs**:
  - *Details:* hero image, business details, contact, stats, recent orders.
  - *Menu Items:* **full CRUD on the `merchants/{id}/menuItems` subcollection** (`loadMenuItemsTab()` line 1157, realtime `onSnapshot`; `saveMenuItem()`/`editMenuItemFn()`/`deleteMenuItemFn()`). Name, description, price, category, image URL. This is the most sophisticated nested feature in the app and it is fully live.

### Notifications (`#page-notifications`, lines 361–403)
- **Status:** ⚠️ Partial — writes are real, but there is **no delivery mechanism**.
- **Send form:** target (Customers/Drivers/Everyone), title, message, live phone-mockup preview (`updPhonePreview()` line 1249). `sendNotif()` (line 1265) writes a doc to the `notifications` collection with `title/message/target/sentBy/createdAt`.
- **Recent Notifications:** realtime list from the `notifications` collection.
- **Critical gap:** writing to Firestore does **not** send a push notification. There is no FCM send, no Cloud Function trigger in this repo. It is effectively a "notification log," not a broadcast system (see §7).

### Promo Codes (`#page-promos`, lines 406–443 / `renderPromos()` line 1298)
- **Status:** ✅ Functional, real + realtime.
- **Create form:** code, type (percent/fixed), discount amount, max uses, valid-until date, with a live "promo card" preview (`updPromoPreview()` line 1290). `createPromo()` (line 1313) uses `setDoc(doc(db,'promoCodes',code))` — **the code string is the document ID**, giving natural uniqueness (a duplicate code silently overwrites, see §7).
- **Active codes table:** code, discount, used/max, valid-until, status (Active/Expired computed client-side from `validUntil`), delete. No edit.

### Analytics (`#page-analytics`, lines 446–474 / `renderAnalytics()` line 1344)
- **Status:** ✅ Mostly real & computed from live orders; a few visual cheats.
- **Period buttons:** Today / This Week / This Month (`setPeriod()` line 1462).
- **Stat cards:** Revenue / Orders / Customers / Avg Order Value — all computed from the live `orders` array per period.
- **Bar chart** (`renderBarChart()` line 1377): hourly (Today) / daily (Week) / weekly (Month) order counts — real, hand-rolled CSS bars.
- **Deliveries by Zone** (`renderZones()` line 1416): buckets order delivery addresses by regex (Kingston/Portmore/St Thomas/St Catherine/Other) — real but crude.
- **Top Merchants** (`renderTopMerch()` line 1436): computed from live orders by count + revenue.
- **Payment Split** (`renderPaySplit()` line 1451): PayPal/card vs COD/cash split from live orders.
- ⚠️ **Driver rating breakdown** in the driver panel is the only fully fabricated chart.

---

## 4. Firebase & Backend Integration

**Auth.** Firebase Email/Password. Single admin gate via `onAuthStateChanged`. Admin accounts provisioned manually in the console (no in-app user management, no role checks beyond "is authenticated"). The topbar hardcodes "Admin User / Super Admin" (line 306) though the avatar name is replaced with the real email on login.

**Storage.** **Not used.** Images (merchant hero, menu items) are plain URL text fields — the admin is expected to paste an external URL (Imgur/Firebase Storage). No upload widget.

**Firestore collections & operations:**

| Collection / path | Read | Write | Realtime? | Notes |
|---|---|---|---|---|
| `orders` | ✅ `query(orderBy('createdAt','desc'),limit(200))` | ✅ `updateDoc` (assign driver, update status) | ✅ `onSnapshot` (line 653) | **REAL/REALTIME.** No create/delete of orders from admin (orders originate in the customer app). |
| `drivers` | ✅ full collection | ✅ `addDoc`, `updateDoc`, `deleteDoc` (create/edit/approve/reject/toggle-online/delete) | ✅ `onSnapshot` (line 678) | **REAL/REALTIME.** Full CRUD + approval workflow. |
| `merchants` | ✅ full collection | ✅ `addDoc`, `updateDoc`, `deleteDoc` | ✅ `onSnapshot` (line 701) | **REAL/REALTIME.** Full CRUD. |
| `merchants/{id}/menuItems` | ✅ subcollection | ✅ `addDoc`, `updateDoc`, `deleteDoc` | ✅ `onSnapshot` (line 1178, on-demand) | **REAL/REALTIME.** Loaded only when the Menu Items tab opens; unsubscribed on panel close. |
| `promoCodes` | ✅ `query(orderBy('createdAt','desc'))` | ✅ `setDoc` (create, code=docID), `deleteDoc` | ✅ `onSnapshot` (line 720) | **REAL/REALTIME.** No edit. |
| `notifications` | ✅ `query(orderBy('createdAt','desc'),limit(50))` | ✅ `addDoc` | ✅ `onSnapshot` (line 744) | **REAL write, but log-only** — no push delivery. |

**Data normalization.** Every listener defensively reads multiple field-name variants (e.g. `o.customerName||o.customer`, `o.vehicleModel||o.vehicle`, `o.averageRating||o.rating`, `o.isOpen ?? o.open ?? true`). This suggests the schema evolved / the three apps don't share a single canonical field naming, and the admin panel is written to tolerate both.

**What is static/mock/hardcoded:**
- Orders tab counts in raw HTML (48/12/32/4) — overwritten at runtime.
- `analyticsStats` initial placeholders (`$—`) — overwritten at runtime.
- Driver rating-breakdown distribution (lines 1016) — **genuinely fabricated** from a single average.
- Topbar "Super Admin" role label.
- Phone-mockup status bar ("9:41 AM ●●● 100%") — cosmetic.

---

## 5. Feature Completeness Matrix

| Capability | Status | Notes |
|---|---|---|
| Admin login (email/pass) | ✅ Done | Real Firebase Auth, spinner, error handling |
| Auth-gated app + logout | ✅ Done | `onAuthStateChanged`, listener teardown on logout |
| Dashboard KPIs | ✅ Done | Computed live from orders/drivers |
| Recent orders feed | ✅ Done | Realtime |
| Orders list + tabs + search | ✅ Done | Realtime, client-side filter |
| Order detail + status flow | ✅ Done | Side panel |
| Assign driver to order | ✅ Done | Writes to order doc |
| Update order status | ✅ Done | Writes to order doc |
| Cancel/refund order | ❌ Not started | "Cancelled" is only a status value; no refund logic |
| Drivers list + stats | ✅ Done | Realtime |
| Add / edit / delete driver | ✅ Done | Full CRUD |
| Approve / reject driver | ✅ Done | Approval workflow |
| Toggle driver online | ✅ Done | Realtime write |
| Driver profile | ⚠️ Partial | Rating breakdown is fabricated; recent deliveries match by name (fragile) |
| Merchants list + stats | ✅ Done | Realtime |
| Add / edit / delete merchant | ✅ Done | Full CRUD |
| Toggle merchant open/closed | ✅ Done | Realtime write |
| Merchant menu-item CRUD | ✅ Done | Subcollection, realtime |
| Merchant image upload | ⚠️ UI-only | URL paste only; no Storage upload |
| Notifications — compose/log | ✅ Done | Writes to `notifications` |
| Notifications — actual push delivery | ❌ Not started | No FCM/Cloud Function; log only |
| Notification targeting (cust/drv/all) | ⚠️ Partial | Field is stored but nothing consumes it |
| Promo codes — create/list/delete | ✅ Done | Realtime |
| Promo codes — edit | ❌ Not started | Delete + recreate only |
| Promo code enforcement | ⚠️ External | Redemption must happen in customer app; admin only defines them |
| Analytics — KPIs/charts | ✅ Done | Computed live (except driver rating chart) |
| Analytics — export/report | ❌ Not started | No CSV/PDF export |
| Customer/user management | ❌ Not started | No users page at all |
| Payments/payouts management | ❌ Not started | Only a read-only payment split chart |
| Admin roles / multi-admin mgmt | ❌ Not started | Single implicit super-admin |
| Settings / configuration page | ❌ Not started | No settings anywhere |

---

## 6. Premium Redesign Status

**Not applied — the pending premium redesign has NOT been done.** Current visual state is a clean, competent but *standard* light-theme admin dashboard:

- **Design tokens** (line 10): red `#C8102E` brand, dark `#1A1A1A`, light gray backgrounds (`#edf0f4`), a single accent. Montserrat (headings) + Inter (body).
- **Look:** flat white cards with a 3px red top-border, subtle `0 1px 6px` shadows, pill badges, rounded 14px cards. Charts are simple CSS gradient bars.
- **What "premium" is missing:** no dark mode, no glassmorphism/gradient surfaces beyond the login and promo-card, no micro-interactions/animation beyond spinners and CSS transitions, no refined data-viz (real chart library, sparklines), no empty-state illustrations, no skeleton loaders (just a text spinner row), no density/theme options. The login gradient and the promo preview card are the only "premium-feeling" surfaces.

Conclusion: functionally solid, visually **v1 baseline**. The redesign is still outstanding.

---

## 7. Known Issues, TODOs, Broken/Incomplete Flows, Security Concerns

### Security
1. **No Firestore security rules in the repository.** A repo-wide search finds **no `firestore.rules`, `storage.rules`, or `firestore.indexes.json` anywhere** in `/workspaces/Shipeast-App`. Rules are managed only in the console (unversioned, unreviewable). Given three client apps write directly to Firestore, **this is the single biggest risk** — if rules are permissive (a common dev default), any client could read/write orders, drivers, merchants, and promo codes. **Must be verified and version-controlled.**
2. **Firebase API key & project config are embedded in client source** (lines 555–561). This is *expected and acceptable* for Firebase web apps (the key is an identifier, not a secret) — **but it only stays safe if Firestore rules and Auth are locked down.** Note `appId` and `measurementId` are absent; not required for current features.
3. **No authorization/role model.** Any account that can authenticate to this Firebase project's Auth can use the full admin panel — there is no admin allowlist or custom-claim check in the client, and (per #1) possibly none server-side. A driver/customer account created through the mobile apps could potentially load this page and operate it unless rules forbid the specific writes.
4. **`limit(200)` on orders** (line 654): dashboard/analytics only ever see the most recent 200 orders — "revenue this month" silently undercounts once volume exceeds that. Not a security issue but a correctness cap.

### Broken / incomplete flows
5. **Notifications don't notify.** `sendNotif()` only writes a Firestore doc; nothing delivers a push. Needs an FCM integration / Cloud Function trigger, or the mobile apps must poll the `notifications` collection. The "Target Audience" value is stored but unused.
6. **Driver rating breakdown is fabricated** (`openDriverPanel`, line 1016): the 5/4/3/2/1-star distribution is derived from `if rating>=4.8 ? 70 : ...` heuristics, not real rating data. Misleading if trusted.
7. **Recent deliveries / recent orders matched by name string** (`o.driver===d.name` line 1012; `o.merchant===m.name` line 1119). Fragile — breaks on rename or duplicate names; should match by `driverId`/`merchantId`.
8. **Promo code creation silently overwrites** (`setDoc` with code as doc ID, line 1323): creating an existing code replaces it (resets `usedCount` to 0) with no warning. Should check existence first.
9. **No promo edit, no order create/delete, no merchant image upload, no customer management** — all noted as gaps in §5.
10. **`analyticsStats` global is dead-ish:** recomputed every render but the top-level `var analyticsStats` initial object (lines 568–572) is only a placeholder; harmless but confusing.
11. **`renderMerchants()` calls `renderMerchantStats()`** but there is also a separate `renderTopMerch()` triggered from the merchants listener — fine, just note the two are coupled to the same snapshot.
12. **Confirmation via `alert()`/`confirm()`** throughout (delete driver/merchant/promo/menu-item, error reporting). Works but is not "premium" and blocks the UI thread; inconsistent with the otherwise custom UI.

### Hardcoded that should be dynamic
13. Orders tab counts (48/12/32/4) in static HTML — cosmetic, overwritten, but should be `—` to avoid a flash of fake numbers.
14. Topbar "Super Admin" role and avatar "A" initial are static (lines 305–306).
15. Zone bucketing (`renderZones`) is a hardcoded regex list of 4 parishes — won't scale to full Jamaica coverage.
16. Payment-split classification keywords (`paypal/card/online` vs `cod/cash`, line 1454) are hardcoded string matches; a new payment method wouldn't be categorized.

---

## 8. What's Next (Prioritized)

**P0 — Security (do first)**
1. Write, review, and **commit `firestore.rules`** (and `storage.rules` if Storage is adopted). Enforce that only admin-claim users can write drivers/merchants/promoCodes/notifications and update orders; scope customer/driver writes tightly. Add to `firebase.json` deploy targets.
2. Add an **admin authorization check** — Firebase custom claim (`admin:true`) verified both in rules and gated in the client (redirect non-admins out of the panel).

**P1 — Close the functional gaps that make the panel misleading**
3. **Real push notifications:** Cloud Function on `notifications` create → FCM send to the targeted audience (respect the `target` field). Without this the whole Notifications page is inert.
4. **Fix fabricated/fragile data:** replace the driver rating breakdown with real aggregated ratings; switch recent-deliveries/orders lookups from name-match to `driverId`/`merchantId`.
5. **Promo-code safety:** check for existing code before `setDoc`, and add an **edit** flow.
6. Remove the `limit(200)` ceiling for analytics (use aggregation queries or a stats doc) so revenue totals are accurate at scale.

**P2 — Missing management surfaces**
7. **Customer/Users page** (list, view, block/unblock) — currently absent entirely.
8. **Payments/payouts page** — driver earnings, merchant settlements, refunds (only a chart exists today).
9. **Order cancel/refund** actions and an audit trail.
10. **Merchant/menu image upload** to Firebase Storage instead of URL paste.
11. **Analytics export** (CSV/PDF) and configurable date ranges.
12. Settings page + multi-admin management.

**P3 — The premium redesign (still outstanding)**
13. Introduce a real chart library, dark mode, skeleton loaders, refined empty states, toast notifications (replace `alert`/`confirm`), and micro-interactions. Consider splitting the 1,566-line monolith into modules if a build step is added.

---

### Appendix — Key function map (`index.html`)
`doLogin` 601 · `doLogout` 616 · `navTo` 620 · `toggleSidebar` 633 · `startListeners` 650 · `stopListeners` 758 · `renderDashboard` 761 · `renderOrders` 800 · `openOrderPanel` 824 · `saveOrderChanges` 891 · `renderDrivers` 909 · `openDriverModal` 953 · `saveDriver` 970 · `deleteDriver` 989 · `approveDriver` 995 · `rejectDriver` 999 · `toggleDriverOnline` 1003 · `openDriverPanel` 1008 · `renderMerchants` 1048 · `openMerchantModal` 1070 · `saveMerchant` 1088 · `deleteMerchant` 1105 · `toggleMerchant` 1110 · `openMerchantPanel` 1114 · `loadMenuItemsTab` 1157 · `saveMenuItem` 1231 · `deleteMenuItemFn` 1243 · `sendNotif` 1265 · `createPromo` 1313 · `deletePromo` 1337 · `renderAnalytics` 1344 · `renderBarChart` 1377 · `renderZones` 1416 · `renderTopMerch` 1436 · `renderPaySplit` 1451 · `onAuthStateChanged` observer 1532.
