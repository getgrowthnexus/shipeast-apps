# ShipEast Customer App — Full Engineering Audit

**Audited path:** `/workspaces/Shipeast-App/customer_app`
**Audit date:** 2026-07-17
**Audit type:** Read-only, engineer-level. No code was modified.
**Scope:** Every file under `lib/`, Android config, `pubspec.yaml`, and build config.

> **Note on branch:** The task described this as branch `redesign/customer-app-ui`, but the working tree is currently on **`main`** (verified via `git branch --show-current`). The audit reflects the code as it exists on `main`. See §6 for redesign-status analysis.

---

## 1. Overview

### App purpose
**ShipEast Customer** is a Flutter mobile app for on-demand local delivery in **St. Thomas & Kingston, Jamaica**. Customers browse local merchants (Food, Grocery, Pharmacy), place orders, pay (Cash on Delivery), track deliveries in real time, and rate drivers/merchants. It also offers:
- A **Packages** courier-request flow (point-to-point package delivery).
- An **Overseas Order** portal (diaspora ordering) embedded as an external web form via WebView.

It is the customer-facing member of a multi-app system (there is a sibling driver app and admin panel — the code reads `drivers` docs and order `status`/`driverId` written by those other apps).

### Tech stack
| Item | Value | Source |
|---|---|---|
| Framework | Flutter | `pubspec.yaml` |
| Language | Dart | — |
| Dart SDK constraint | `^3.11.5` | `pubspec.yaml` → `environment.sdk` |
| App version | `1.0.2+3` (versionName 1.0.2, versionCode 3) | `pubspec.yaml` → `version` |
| State management | `provider` (ChangeNotifier) + local `setState` | `main.dart`, `cart_provider.dart` |
| Backend | Firebase (Firestore, Auth, Storage) | `firestore_service.dart` |
| Android applicationId | `com.shipeast.customerapp` | `android/app/build.gradle.kts` |
| minSdk | `max(flutter.minSdkVersion, 23)` | `android/app/build.gradle.kts` |
| Firebase project | `shipeast-1a1f6` | `lib/firebase_options.dart` |

### Dependencies (from `pubspec.yaml`) and their actual usage
| Package | Version | Purpose | Actually used? |
|---|---|---|---|
| `flutter` (sdk) | — | Framework | ✅ |
| `cupertino_icons` | ^1.0.8 | iOS-style icons | Transitive/default; not directly referenced |
| `google_fonts` | ^6.2.1 | Montserrat / Nunito / Inter / DancingScript typography | ✅ Heavily used across every screen |
| `shared_preferences` | ^2.3.2 | Local key/value storage | ⚠️ **Declared but never imported** — no `shared_preferences` usage anywhere in `lib/` |
| `webview_flutter` | ^4.10.0 | Embeds overseas order web form | ✅ `overseas_order_screen.dart` |
| `image_picker` | ^1.1.2 | Pick avatar from gallery | ✅ `profile_screen.dart` |
| `url_launcher` | ^6.3.0 | Open WhatsApp / mailto | ✅ `help_support_screen.dart` |
| `firebase_core` | ^3.0.0 | Firebase init | ✅ `main.dart` |
| `firebase_auth` | ^5.0.0 | Email/password auth, password reset, account delete | ✅ Multiple screens |
| `cloud_firestore` | ^5.0.0 | All data storage & realtime streams | ✅ `firestore_service.dart` + screens |
| `firebase_storage` | ^12.0.0 | Avatar image upload | ✅ `firestore_service.uploadAvatar` |
| `firebase_messaging` | ^15.0.0 | Push notifications (FCM) | ❌ **Declared but NEVER used** — no import, no token registration, no handlers anywhere in `lib/`. See §4 and §7. |
| `provider` | ^6.1.2 | Cart state | ✅ `cart_provider.dart`, `main.dart` |
| `cached_network_image` | ^3.4.1 | Cached remote images (merchant/menu/avatar) | ✅ Multiple screens |
| `flutter_lints` | ^6.0.0 (dev) | Lint rules | ✅ via `analysis_options.yaml` |

**Codebase size:** 25 Dart files, ~10,742 lines total. Largest files: `home_screen.dart` (862), `payment_screen.dart` (840), `merchant_menu_screen.dart` (757), `order_status_screen.dart` (724), `profile_screen.dart` (676).

---

## 2. Architecture

### Folder structure
```
lib/
├── main.dart                       # App root, routes, MainShell (bottom nav + cart FAB)
├── firebase_options.dart           # Hardcoded Android Firebase config (no iOS/web)
├── providers/
│   └── cart_provider.dart          # CartProvider (ChangeNotifier) + CartItem model
├── services/
│   └── firestore_service.dart      # ALL Firestore/Storage access (static methods)
├── theme/
│   └── app_theme.dart              # Color constants + Material3 ThemeData
├── widgets/
│   └── shimmer_box.dart            # Reusable animated shimmer placeholder
└── screens/                        # 20 screen files
    ├── splash_screen.dart          welcome_screen.dart      login_screen.dart
    ├── register_screen.dart        home_screen.dart         search_screen.dart
    ├── merchant_menu_screen.dart   cart_screen.dart         checkout_screen.dart
    ├── payment_screen.dart         order_confirmed_screen.dart  order_status_screen.dart
    ├── order_history_screen.dart   overseas_order_screen.dart   profile_screen.dart
    ├── rate_driver_screen.dart     saved_addresses_screen.dart  notifications_screen.dart
    ├── help_support_screen.dart    privacy_security_screen.dart coming_soon_screen.dart
```

### State management
- **Global cart state:** `CartProvider extends ChangeNotifier` wrapped at the app root by a single `ChangeNotifierProvider` in `main.dart:58`. Consumed via `context.watch`/`context.read`/`Consumer` in `merchant_menu_screen`, `cart_screen`, `payment_screen`, and the cart FAB in `MainShell`.
- **Everything else is local `StatefulWidget` + `setState`.** Each screen manages its own Firestore `StreamSubscription`s and loading flags. No Riverpod/BLoC/Redux.
- **No repository/model layer** — Firestore documents are passed around as raw `Map<String, dynamic>` everywhere. The only typed model is `CartItem`.

### Navigation / routing
- **Named routes** declared in `MaterialApp.routes` (`main.dart:65-86`). 20 routes registered. `initialRoute: '/'` → `SplashScreen`.
- Data is passed between routes via `Navigator.pushNamed(..., arguments: {...})` and read in `didChangeDependencies` through `ModalRoute.of(context)?.settings.arguments`. This is the dominant data-passing pattern (checkout → payment → confirmed → status all thread a `Map`).
- A few screens are pushed via `MaterialPageRoute` directly rather than named routes (e.g. `SavedAddressesScreen`, `ComingSoonScreen`, `HelpSupportScreen`, `PrivacySecurityScreen`, `NotificationsScreen` from Profile).
- **`MainShell`** (`main.dart:92`) is the post-login home; it uses an `IndexedStack` over 5 tabs (Home, Search, Orders, Alerts, Profile) with a custom bottom nav bar, plus a global cart FAB.

### Data flow
1. **Auth gate:** `SplashScreen` waits ~2.8s then routes to `/home` if `FirebaseAuth.currentUser != null`, else `/welcome`.
2. **Reads:** Screens subscribe to `FirestoreService` streams (merchants, menu items, orders, addresses, notifications, user profile, drivers) → `setState`.
3. **Writes:** Registration writes `users/{uid}`; ordering writes `orders/{id}`; ratings update `orders` + `drivers` transactionally; addresses are a `users/{uid}/addresses` subcollection; avatar → Storage + `users/{uid}.avatarUrl`.
4. **Cart:** Menu screen populates `CartProvider` → cart screen computes totals → checkout selects address → payment places order via `FirestoreService.placeOrder` → clears cart → confirmed → status (realtime).

---

## 3. Screen-by-screen inventory

Legend: **✅ Functional** = real behavior wired to backend/logic · **🟡 Partial** = works but has mocked/hardcoded pieces · **⚪ UI-only** = no backend, cosmetic or stub.

### 3.1 `splash_screen.dart` — SplashScreen — **✅ Functional**
- Widgets: `Stack`, decorative circles, `Image.asset('assets/logo.png')`, animated `LinearProgressIndicator` (2.8s `AnimationController`).
- Logic: On animation complete, reads `FirebaseAuth.instance.currentUser` and `pushReplacementNamed` to `/home` or `/welcome`.
- Reads/writes: **Reads** auth state only. Displays hardcoded `v1.0.2`.

### 3.2 `welcome_screen.dart` — WelcomeScreen — **⚪ UI-only**
- Widgets: Red hero with hand-painted `_DeliveryIllustration` (`CustomPaint` motorcycle + speed lines), floating animation, two buttons.
- Logic: "Get Started" → `/register`; "I Already Have an Account" → `/login`. Terms/Privacy text spans are **not tappable** (no gesture handlers).
- Reads/writes: none.

### 3.3 `login_screen.dart` — LoginScreen — **🟡 Partial**
- Widgets: Custom text fields, password visibility toggle, Google button, snackbars.
- Logic: `FirebaseAuth.signInWithEmailAndPassword` (✅ real). On success → `/home`.
- **Stubs:** "Forgot Password?" → snackbar `'Password reset coming soon!'` (note: real reset *does* exist in Privacy & Security). "Continue with Google" → snackbar `'Google Sign-In coming soon!'`.
- Reads/writes: Firebase Auth sign-in.

### 3.4 `register_screen.dart` — RegisterScreen — **✅ Functional**
- Widgets: Name/phone/email/password fields, "encrypted" reassurance banner.
- Logic: Validates non-empty + password ≥6 chars. `createUserWithEmailAndPassword` then **writes** `users/{uid}` with `{name, phone, email, createdAt}`. → `/home`.
- Reads/writes: **Writes** `users/{uid}` (Firestore) + creates Auth user.

### 3.5 `home_screen.dart` — HomeScreen — **🟡 Partial**
- Widgets: Red header (greeting + avatar + fake search bar), overseas banner, category chips, merchant cards with `CachedNetworkImage` + gradient fallback, package grid, shimmer loaders (`ShimmerBox`), empty states.
- Logic:
  - `initState` calls `FirestoreService.seedMerchantsIfEmpty()` (seeds 15 merchants + menu items on first run if empty).
  - Subscribes to `merchantsByCategory` for **Food(0), Grocery(1), Pharmacy(3)** — realtime streams.
  - Category **Packages(2)** shows a static 6-tile grid; tapping opens a **package request bottom sheet** whose Submit only shows a snackbar (`'Package request submitted!'`) — **does NOT write to Firestore**.
  - Greeting is time-based; user name/avatar from `watchUserProfile` (realtime).
- **Hardcoded/mock:** Location text `'St. Thomas, Jamaica'`; "See all" → snackbar `'All merchants coming soon!'`; favourite heart → snackbar `'Added to favourites!'` (no persistence); category gradient palettes.
- Reads/writes: **Reads** `merchants` (×3 categories, realtime) + `users/{uid}` profile (realtime). **Writes** merchant/menu seed data on first launch.

### 3.6 `search_screen.dart` — SearchScreen — **✅ Functional**
- Widgets: Search field, result cards, empty/no-results states, category-icon fallback.
- Logic: Subscribes to `allMerchantsStream()` (realtime). **Client-side** filter on name/category substring. Tapping a result → `/merchant` with args.
- Reads/writes: **Reads** all `merchants` (realtime). Search is purely local filtering (no query to backend, no menu-item search).

### 3.7 `merchant_menu_screen.dart` — MerchantMenuScreen — **✅ Functional**
- Widgets: Hero image/gradient, info bar (rating/time/fee/open badge), category tabs derived from menu items, menu item cards with qty controls, cart FAB, shimmer list, empty state, "start new order?" dialog.
- Logic: Reads merchant meta from route args; subscribes to `menuItemsStream(merchantId)` (realtime). Add/remove items → `CartProvider`. If cart already has another merchant's items, prompts to clear.
- **Mock:** favourite heart → snackbar. Tabs = `['Popular', ...distinct categories]`; "Popular" just shows all items (no real popularity ranking).
- Reads/writes: **Reads** `merchants/{id}/menuItems` (realtime). Writes to cart (in-memory).

### 3.8 `cart_screen.dart` — CartScreen — **✅ Functional**
- Widgets: Item cards with qty steppers, "Add More Items", special-instructions field, summary card, checkout button, empty state.
- Logic: Reads `CartProvider` live. Computes `serviceFee = round(subtotal * 0.10)`, `total = subtotal + deliveryFee + serviceFee`. Checkout → `/checkout` with order args.
- **Gap:** The "Special Instructions" `TextField` value is **never read or forwarded** — captured into a controller and dropped.
- Reads/writes: Cart (in-memory) only.

### 3.9 `checkout_screen.dart` — CheckoutScreen — **✅ Functional**
- Widgets: Address selector (radio list), order summary, "Choose Payment" button, address empty state, `SavedAddressesScreen` push.
- Logic: Subscribes to `addressStream(uid)` (realtime). Requires an address before proceeding (`_showError` otherwise). Forwards selected address text into `/payment` args.
- Reads/writes: **Reads** `users/{uid}/addresses` (realtime).

### 3.10 `payment_screen.dart` — PaymentScreen — **🟡 Partial**
- Widgets: Payment method rows (PayPal disabled "Coming Soon", COD active), security-reassurance card, promo code card, total card with discount, place-order button, confirmation bottom sheet.
- Logic:
  - Promo: `validatePromoCode(code)` reads `promoCodes/{CODE}` (✅ real, checks `active` + `expiresAt`, supports `percentage`/fixed discount).
  - Place order: shows confirm sheet → `FirestoreService.placeOrder(...)` (✅ real write) → clears cart → `/order-confirmed`.
- **Mock/stubs:** PayPal disabled; "256-bit SSL / Buyer Protection" security card is purely decorative text. Payment is COD only.
- Reads/writes: **Reads** `promoCodes/{code}`. **Writes** `orders/{id}`.

### 3.11 `order_confirmed_screen.dart` — OrderConfirmedScreen — **🟡 Partial**
- Widgets: Confetti (`CustomPaint` + 40 particles), success animation, Order ID chip, ETA card, delivery address, receipt card, "Track My Order" / "Back to Home".
- Logic: Reads order details from route args (no re-fetch). Track → `/order-status`.
- **Hardcoded:** ETA `'30 – 40 mins'` is static text, not computed.
- Reads/writes: none (all from args).

### 3.12 `order_status_screen.dart` — OrderStatusScreen — **🟡 Partial**
- Widgets: Fake map (`_MapGridPainter` grid + static pin + pulsing dot), status bar, 4-step tracker, driver card, rate button, tracking note.
- Logic: Subscribes to `watchOrder(orderId)` (realtime). Maps `status` (`pending/accepted/in_transit/delivered`) → step 0–3. When `driverId` appears, subscribes to `watchDriver(driverId)` (realtime) and shows name/rating/vehicle. Rate button appears at step 3 if not yet rated.
- **Mock:** The map is decorative only — **no real GPS/route/driver-location**. ETAs (`~40/~25/~15 min`) are hardcoded per step. Driver "call" button → snackbar `'Calling ...'` (does **not** dial; `url_launcher` not used here).
- Reads/writes: **Reads** `orders/{id}` + `drivers/{driverId}` (realtime).

### 3.13 `order_history_screen.dart` — OrderHistoryScreen — **✅ Functional**
- Widgets: Tabs (All/Active/Completed/Cancelled), order cards with status badge, date, items preview, total, Track button, empty state.
- Logic: Subscribes to `orderHistoryStream(uid)` (realtime, sorted client-side by `createdAt` desc). Tab filtering is client-side on `status`. Track → `/order-status`.
- Reads/writes: **Reads** `orders where customerId == uid` (realtime).

### 3.14 `overseas_order_screen.dart` — OverseasOrderScreen — **🟡 Partial (external)**
- Widgets: `WebViewWidget`, info banner, loading overlay, error/retry state.
- Logic: Loads `https://tally.so/r/shipeast`; on error falls back to `https://form.jotform.com/shipeast`; then shows retry UI.
- **Concern:** Both URLs look like **placeholders** (generic slugs) and likely 404 — needs a real form URL. Nothing is written to Firestore; submissions live entirely in the external form.
- Reads/writes: external web only.

### 3.15 `profile_screen.dart` — ProfileScreen — **✅ Functional**
- Widgets: Red gradient header with avatar (tap to change), stats card (Orders / Rating / Saved), menu list, sign-out, edit bottom sheet.
- Logic:
  - `_loadProfile` (one-time `get`, **not** a stream) loads `users/{uid}`.
  - `getUserStats` computes order count, avg driver rating, saved-address count (aggregated reads).
  - Avatar: `image_picker` → `uploadAvatar` (Storage) → `users/{uid}.avatarUrl`.
  - Edit sheet → `_saveProfile` merges `{name, phone, email, updatedAt}`.
  - Menu → Saved Addresses ✅, Notifications ✅, Payment Methods → **ComingSoon** ⚪, Privacy & Security ✅, Help & Support ✅.
  - Sign out → `FirebaseAuth.signOut` → `/welcome`.
- Reads/writes: **Reads** `users/{uid}` (once) + stats aggregation over `orders` & `addresses`. **Writes** profile fields + avatar.
- **Note:** Uses a one-time read, so profile does not update live if changed elsewhere (Home screen uses the realtime stream and can diverge briefly).

### 3.16 `rate_driver_screen.dart` — RateDriverScreen — **✅ Functional**
- Widgets: Driver star rating, praise tag chips, merchant star rating, comment field, submit button.
- Logic: Loads driver via `watchDriver` (realtime). Requires driver rating > 0. Submits via `submitRating` → **transactionally** updates `drivers/{id}` aggregates + marks `orders/{id}.rated=true`. → `/home`.
- Reads/writes: **Reads** `drivers/{id}`. **Writes** `orders/{id}` + `drivers/{id}` (transaction).

### 3.17 `saved_addresses_screen.dart` — SavedAddressesScreen — **✅ Functional**
- Widgets: Address cards (edit/delete), add/edit bottom sheet with quick-label chips, delete confirm dialog, empty state.
- Logic: Subscribes to `addressStream(uid)` (realtime). Add/update/delete via `FirestoreService`.
- Reads/writes: **Reads/Writes** `users/{uid}/addresses` (full CRUD, realtime).

### 3.18 `notifications_screen.dart` — NotificationsScreen — **✅ Functional (in-app)**
- Widgets: Notification cards (type icon, unread dot/highlight), empty state, time-ago label.
- Logic: Subscribes to `notificationsStream(uid)` (realtime) — filters by `target ∈ {all, customers, uid}`. On open, `markNotificationsRead` writes `users/{uid}.notificationsReadAt`. Unread = `createdAt > notificationsReadAt`.
- Reads/writes: **Reads** `notifications` (realtime) + `users/{uid}` read-timestamp. **Writes** `notificationsReadAt`.
- **Note:** These are **in-app** notifications only — there is no push (FCM) delivery. See §4.

### 3.19 `help_support_screen.dart` — HelpSupportScreen — **✅ Functional**
- Widgets: Contact card (WhatsApp/Email buttons), expandable FAQ accordion (5 hardcoded FAQs), version card.
- Logic: WhatsApp → `https://wa.me/18765559988`; Email → `mailto:info@shipeastja.com` (both via `url_launcher`, real).
- **Stale:** Version card hardcodes **"Version 1.0.0"** (app is actually 1.0.2). FAQ mentions "cancel within 2 minutes" but no cancel feature exists in-app.

### 3.20 `privacy_security_screen.dart` — PrivacySecurityScreen — **✅ Functional**
- Widgets: "Data we collect" info card, password-reset button, delete-account button + confirm dialog.
- Logic: `sendPasswordResetEmail(user.email)` (✅ real). Delete → deletes `users/{uid}` doc then `user.delete()`; handles `requires-recent-login`.
- Reads/writes: **Writes** (deletes) `users/{uid}` + Auth user; triggers password reset email.
- **Gap:** Account deletion removes the user doc + auth account but **orphans** the user's `addresses` subcollection, `orders`, ratings, and Storage avatar (no cascade cleanup).

### 3.21 `coming_soon_screen.dart` — ComingSoonScreen — **⚪ UI-only (intentional stub)**
- Generic "Coming Soon" placeholder with a `title` param. Used for **Payment Methods**.

---

## 4. Firebase & backend integration

**Init:** `main.dart:_initFirebase()` retries `Firebase.initializeApp` up to 5× with backoff. Config is **hardcoded** in `firebase_options.dart` for **Android only** — iOS and web explicitly throw `UnsupportedError`. `google-services.json` is **not committed** (gitignored) but the `com.google.gms.google-services` gradle plugin is applied (`android/build.gradle.kts`, `android/app/build.gradle.kts`).

### Firestore collections & access map
| Collection / doc | Operation | Where | Mode |
|---|---|---|---|
| `merchants` (query by `category`) | read | `merchantsByCategory` → Home | **REALTIME** (`.snapshots()`) |
| `merchants` (all) | read | `allMerchantsStream` → Search | **REALTIME** |
| `merchants` + `merchants/{id}/menuItems` | write (seed) | `seedMerchantsIfEmpty` → Home init | Batch write, one-time (guarded by `limit(1)` check) |
| `merchants/{id}/menuItems` | read | `menuItemsStream` → Merchant menu | **REALTIME** |
| `orders` | create | `placeOrder` → Payment | REAL write |
| `orders where customerId==uid` | read | `orderHistoryStream` → History; `getUserStats` | **REALTIME** (history) / one-time (stats) |
| `orders/{id}` | read | `watchOrder` → Order status | **REALTIME** |
| `orders/{id}` | update | `submitRating` → Rate | REAL (transaction) |
| `drivers/{id}` | read | `watchDriver` → Order status, Rate | **REALTIME** |
| `drivers/{id}` | update | `submitRating` | REAL (transaction: totalRatings/ratingCount/averageRating) |
| `users/{uid}` | create/merge/read | Register, Profile, Home | Mixed: realtime (`watchUserProfile`) + one-time (`getUserStats`, Profile load) |
| `users/{uid}/addresses` | full CRUD | Saved Addresses, Checkout | **REALTIME** (stream) + one-time helper |
| `users/{uid}.avatarUrl` | write | `uploadAvatar` | REAL |
| `users/{uid}.notificationsReadAt` | write/read | Notifications | REAL |
| `notifications` | read | `notificationsStream`, unread count | **REALTIME** |
| `promoCodes/{CODE}` | read | `validatePromoCode` → Payment | REAL one-time `get` |

### Firebase Auth
- **Email/password** sign-in (`login`), sign-up (`register`), sign-out (`profile`), password reset (`privacy_security`), account delete (`privacy_security`). All **REAL**.
- Auth-state gate in `SplashScreen`. `currentUser.uid` is the key used throughout.
- **Missing:** Google Sign-In (stubbed snackbar), phone auth, email verification enforcement.

### Firebase Storage
- **REAL:** `users/{uid}/avatar.jpg` upload + download URL in `uploadAvatar`. Only Storage usage in the app.

### Firebase Messaging / FCM — **NOT IMPLEMENTED**
- `firebase_messaging: ^15.0.0` is in `pubspec.yaml` but **there is no `import`, no `FirebaseMessaging.instance`, no `getToken()`, no `onMessage`/background handler, no permission request, and no FCM token written to Firestore** anywhere in `lib/`.
- The AndroidManifest has **no** FCM service, default-channel, or `POST_NOTIFICATIONS` permission.
- **Consequence:** All "notifications" are **in-app only** (the `notifications` Firestore collection rendered in `NotificationsScreen` + the unread badge). Copy across the app ("We'll notify you at every step", "Push alerts & order updates") **overstates** the actual capability. Push delivery does not work.

### Realtime vs static summary
- **Realtime (stream/listener):** merchants (home + search), menu items, order history, single-order tracking, driver, addresses, notifications + unread count, user profile (home).
- **One-time reads:** profile screen load, `getUserStats`, promo validation, address `getAddressesOnce` (unused helper).
- **Static/hardcoded/mock:** location label, ETAs, order-status map, favourites, "See all", package-request submission, overseas form (external), security/SSL card, help version string.

---

## 5. Feature completeness matrix

| Feature | Status | Notes |
|---|---|---|
| Splash / auth gate | ✅ Done | Real auth check + routing |
| Email/password register | ✅ Done | Writes `users/{uid}` |
| Email/password login | ✅ Done | — |
| Google Sign-In | ⚪ Not started | Snackbar stub in login |
| Forgot password (login) | 🟡 Partial | Stubbed in login, but real reset exists in Privacy & Security |
| Home: merchants by category | ✅ Done | Realtime, 3 categories |
| Merchant seeding | ✅ Done | One-time first-run seed (15 merchants) |
| Categories: Food/Grocery/Pharmacy | ✅ Done | Realtime |
| Packages (courier request) | 🟡 UI-only | Form submit = snackbar only; **no persistence** |
| Overseas order portal | 🟡 Partial | External WebView; **placeholder URLs** |
| Search | ✅ Done | Realtime data, client-side filter (merchants only) |
| Merchant menu + tabs | ✅ Done | Realtime menu; "Popular" not real ranking |
| Cart (add/remove/qty) | ✅ Done | Provider-based |
| Cart special instructions | ⚪ Not started | Captured but never sent |
| Checkout + address select | ✅ Done | Realtime addresses; requires address |
| Promo codes | ✅ Done | Real `promoCodes` validation + discount |
| Payment — COD | ✅ Done | Places real order |
| Payment — PayPal | ⚪ Not started | Disabled "Coming Soon" |
| Payment Methods screen | ⚪ Not started | ComingSoon placeholder |
| Order confirmation | ✅ Done | ETA is hardcoded text |
| Order tracking (status steps) | 🟡 Partial | Real status stream; **fake map**, hardcoded ETAs |
| Live driver info | ✅ Done | Realtime `drivers/{id}` |
| Call driver | ⚪ Not started | Snackbar only (no dial) |
| Order history + filters | ✅ Done | Realtime + client filter |
| Cancel order | ⚪ Not started | Mentioned in FAQ; no UI/logic |
| Rate driver + merchant | ✅ Done | Transactional aggregate update |
| Saved addresses CRUD | ✅ Done | Realtime, full CRUD |
| Profile view/edit | ✅ Done | One-time read (not live) |
| Avatar upload | ✅ Done | Storage + Firestore |
| User stats | ✅ Done | Aggregated reads |
| Notifications (in-app) | ✅ Done | Realtime + read tracking |
| Push notifications (FCM) | ❌ Not started | Dependency present, **zero implementation** |
| Favourites | ⚪ Not started | Snackbar only, no persistence |
| Help & Support | ✅ Done | WhatsApp/Email/FAQ; version string stale |
| Privacy: password reset | ✅ Done | Real |
| Privacy: delete account | 🟡 Partial | Deletes user+doc; **no cascade** of subdata/storage |

---

## 6. Redesign status (branch `redesign/customer-app-ui`)

> The working tree is on `main`, so this reflects the merged/current UI system.

The app already uses a **single, consistent, custom design system** across **all 21 screens** — there is no visible "old vs new UI" split remaining in the tree:
- **Consistent primitives:** brand red `#C8102E` (`AppTheme.primary`), Google Fonts (Montserrat black for headings, Nunito for buttons/labels, Inter for body), 11–14px rounded cards with soft shadows, circular back buttons, pill chips, red gradient headers, floating snackbars, shimmer loaders (`ShimmerBox`).
- **Every screen** follows the same header/card/spacing conventions. `coming_soon_screen`, `privacy_security`, `help_support`, `notifications` all match the same language.

**Design-system observations / inconsistencies to note:**
- `AppTheme` is thin — it only exposes color constants + a bare `ColorScheme.fromSeed` Material3 theme. **Typography, button styles, and card decorations are re-declared inline in every screen** rather than centralized (`ElevatedButton.styleFrom`, `GoogleFonts.*`, `BoxDecoration` repeated dozens of times). This is the biggest maintainability debt in the redesign.
- Two header patterns coexist: white header with circular back button (most screens) vs. red/gradient header (home, profile, help, overseas, coming-soon, search). Intentional but worth documenting.
- The app is **light-mode only**; no dark theme handling.

**Conclusion:** Redesign appears **complete and uniformly applied**. The remaining "design" work is **refactoring** repeated styling into `AppTheme`/shared widgets, not converting screens.

---

## 7. Known issues, TODOs, broken/incomplete flows, and hardcoded values

### High priority
1. **FCM entirely unimplemented** despite dependency + UI copy promising push. Either implement (token registration, permission, handlers, manifest channel) or remove the dependency and adjust copy.
2. **Package (courier) request writes nothing** — `home_screen._showPackageForm` submit only shows a snackbar. All entered pickup/delivery/weight/instructions data is discarded.
3. **Overseas order URLs are placeholders** (`tally.so/r/shipeast`, `form.jotform.com/shipeast`) — almost certainly non-functional; needs the real form link.
4. **Account deletion does not cascade** — orphans `users/{uid}/addresses`, `orders`, ratings on `drivers`, and the Storage avatar. Needs a Cloud Function or client-side cleanup.
5. **Cart "Special Instructions" is dropped** — never attached to the order payload in `placeOrder`.

### Medium priority
6. **`unreadNotificationsCountStream` is inefficient** (`firestore_service.dart:394`): on **every** `users/{uid}` snapshot it does a **full `notifications` collection `get()`**. Scales poorly and adds read cost; should use a query filtered by `createdAt > readAt` or maintain a counter.
7. **Profile uses a one-time read** while Home uses the realtime stream → the two can show different name/avatar until reload. Consider a single source of truth.
8. **Order-status map & ETAs are fake** — decorative grid, static pin, hardcoded per-step ETAs. No real driver location. May mislead users.
9. **"Call driver" doesn't call** — snackbar only, even though `url_launcher` is available and drivers presumably have a `phone`.
10. **Search is merchant-name/category only** — no menu-item search, despite hint text "Search food, merchants, items...". Purely client-side substring.
11. **Version strings are inconsistent:** `pubspec` = `1.0.2+3`, splash = `v1.0.2`, Help & Support card = **hardcoded "Version 1.0.0"** (stale).
12. **`seedMerchantsIfEmpty` runs on every Home `initState`** — cheap (guarded by `limit(1)`), but ships demo/seed data logic into the production client. Seeding should be an admin/server task, not customer-app responsibility.

### Low priority / cleanup
13. **Unused dependencies:** `shared_preferences` and `firebase_messaging` are declared but never used. `firebase_options.dart` still contains a live API key committed to source (standard for Firebase Android, but note it's in-repo).
14. **`getAddressesOnce` / `_sortedAddresses`** in `firestore_service.dart` are defined but not referenced.
15. **Hardcoded UI values:** location `'St. Thomas, Jamaica'`; confirmed-screen ETA `'30 – 40 mins'`; status ETAs; favourites; "See all" → "coming soon" snackbars.
16. **Terms & Privacy links** on the welcome screen are styled as links but not tappable.
17. **FAQ claims a 2-minute cancel window** that has no corresponding feature — copy/feature mismatch.
18. **README is the default Flutter template** — no project-specific documentation.
19. **iOS/web unsupported** — `firebase_options.dart` throws for both; the app is Android-only in practice.
20. **Impeller disabled** in the manifest (workaround for TECNO KM7 Gralloc driver) — fine, but a device-specific hack worth tracking.
21. **Client-side sorting/filtering** for orders, addresses, and notifications avoids composite Firestore indexes but shifts work to the client; acceptable at small scale, revisit as data grows.

---

## 8. What's next — prioritized remaining work

### P0 — Correctness / trust (do before launch)
1. **Implement or remove FCM.** If push is a launch feature: add permission request, token registration → store on `users/{uid}`, foreground/background handlers, Android notification channel + `POST_NOTIFICATIONS`. Otherwise remove the dep and soften "push"/"we'll notify you" copy.
2. **Wire the Packages courier request to Firestore** (e.g. a `packageRequests` collection with pickup/delivery/weight/packing/instructions + status) so submissions aren't lost.
3. **Fix the Overseas order URL** (real form) or convert it to a native in-app form that writes to Firestore.
4. **Attach cart special instructions** to the order payload in `placeOrder`.
5. **Cascade account deletion** (Cloud Function recommended) to remove addresses, avatar, and anonymize/retain orders per policy.

### P1 — Feature parity with UI promises
6. **Real order tracking:** integrate driver location (from driver app) into `order_status_screen` map, or replace the fake map with an honest status-only view; compute ETAs from real data.
7. **"Call driver"** via `url_launcher` `tel:` using the driver's phone.
8. **Order cancellation** within the promised window (status guard + Firestore update + optional notification).
9. **Google Sign-In** (or remove the button).
10. **Payment Methods** — either implement PayPal/cards or keep as clearly-labeled roadmap.
11. **Favourites** — persist to `users/{uid}/favourites` and surface them (currently pure snackbar).

### P2 — Quality, performance, maintainability
12. **Centralize the design system:** move repeated `GoogleFonts`, button styles, and card `BoxDecoration` into `AppTheme` / shared widgets. Biggest ROI for the redesign branch.
13. **Optimize unread-notifications counting** (avoid full-collection `get()` per profile snapshot).
14. **Unify profile data source** (stream everywhere) to avoid stale profile vs. home divergence.
15. **Extend search** to menu items and/or move filtering server-side as data grows.
16. **Introduce typed models** (Merchant, MenuItem, Order, Address) instead of raw `Map<String, dynamic>`.
17. **Fix version strings** (single source; remove hardcoded "1.0.0" in Help).
18. **Remove dead code/deps** (`shared_preferences`, unused address helpers).
19. **Move merchant seeding** out of the customer client into admin/server tooling.
20. **Add tests** (`test/` currently holds only the default template) and a project-specific README.
21. **Add Firestore Security Rules review** (not in this repo scope, but critical — client reads/writes `users`, `orders`, `drivers`, `promoCodes`, `notifications` directly).

---

*End of audit. All findings are traceable to specific files/functions cited above; no code was modified during this review.*
