# ShipEast — project guide for Claude

ShipEast is a courier and bearer service in St. Thomas and Kingston, Jamaica
(prices in J$). Three apps share one Firebase project, `shipeast-1a1f6`:

| Folder | What | Stack |
|---|---|---|
| `customer_app/` | Customer app: order food/packages, Shop & Deliver requests, track, rate | Flutter, package `shipeast_customer`, Android id `com.shipeast.customerapp` |
| `driver_app/` | Driver app: register, go online, accept, pick up, deliver, earnings | Flutter, package `shipeast_driver`, Android id `com.shipeast.shipeast_driver` |
| `admin_panel/` | Admin web panel (admin.shipeastja.com): orders, drivers, merchants, customers, promos, notifications, settings | Plain ES-module JS + HTML/CSS, no build step, Firebase JS SDK from gstatic |
| `functions/` | Cloud Functions (TypeScript) | **Not deployed** — see Firebase plan below |
| root | `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json` | |

## Where the truth lives

- `SCHEMA.md` — schema of record for every Firestore collection and field, plus
  invariants. Change it together with any data-shape change.
- `docs/RECOVERY-NOTES.md` — how this repo was rebuilt (Sep 2026), which
  history lines were merged, signing history, and **known gaps**. Read it
  before touching Firebase-dependent features.
- `docs/github-archive/pull-requests.md` — descriptions of the old repo's PRs.
- `docs/PLAN-order-tracking.md` — planned (not started): restaurant stages
  (confirmed → preparing → ready), rider assignment as a field, and a web
  merchant portal. Read before touching order statuses.
- `design-system/DESIGN-SYSTEM.md` and `admin_panel/DESIGN-SPEC.md` — the 2026
  brand: tokens, type (Figtree only), components, and the reasons behind them.
- Commit messages are detailed and cite checklist IDs (DR-25, PR-5, DV-5,
  NT-4, OR-3…). `git log --grep <ID>` finds the history of a client request.

## Code layout

- Flutter apps: `lib/screens`, `lib/widgets` (`Se*` components), `lib/theme`
  (`SeColors`, `SeType`, `SeSpacing`, `SeIcons`, `SeMotion` — use tokens, never
  raw hex), `lib/services` (Firestore access), `lib/models`, `lib/utils`.
  Customer uses `provider`. `lib/dev/` wires the Firebase emulators.
- Admin: `app.js` (main), small modules (`order-status.js`,
  `overseas-status.js`, `promo-eligibility.js`, `pricing-form.js`,
  `image-upload.js`, `location-input.js`), styles in `css/` loaded in order
  tokens → shell → components → pages → responsive.
- Order status vocabulary (`pending, awaiting_merchant, preparing,
  awaiting_driver, confirmed, picked_up, in_transit, delivered, cancelled,
  failed_delivery` — shown as Order Placed … Failed Delivery, same words in
  all three apps) exists in four copies — both apps'
  `models/order_status.dart`, `admin_panel/order-status.js`,
  `functions/src/orderStatus.ts`. `tools/check-status-parity.mjs` fails CI if
  they drift; change all four together.
- Live GPS tracking: `models/tracking.dart` (byte-identical in both apps, also
  checked by the parity tool) + `admin_panel/tracking.js`; the driver app's
  `services/location_service.dart` writes `driverLocations/{uid}` and
  `orders/{id}.driverLoc` / `driverStage`. Maps are OpenStreetMap (flutter_map,
  Leaflet) — no API key.

## Firebase plan: Spark (free) — this shapes the code

No Cloud Functions are deployed and no Cloud Storage bucket exists. Existing
workarounds: merchant/menu photos stored inline in Firestore as compressed
`data:` URLs; delivery completion enforced in `firestore.rules` instead of the
`confirmDelivery` function. Features that still depend on Functions/Storage and
therefore do not work in production are listed in `docs/RECOVERY-NOTES.md`
(driver registration documents, promo redemption, ratings, profile and
delivery photos, push notifications). Treat those features as broken for now.
The owner is **evaluating moving off Firebase** to another backend (as of
2026-09-28, undecided) — do not upgrade the Firebase plan, deploy functions,
or add new Firebase-specific dependencies without asking first.

## Platforms

Both apps must ship on **Android and iOS** — that is why they are Flutter.
Only Android has been built so far. iOS is not configured yet (no Firebase
iOS app, missing Info.plist permission strings, no iOS CI); the checklist is
in `docs/IOS-STATUS.md`. Keep new code platform-neutral, and when a feature
needs a native permission, add it for both platforms.

## Build, test, release — all in GitHub Actions

The owner does not run Flutter locally; CI is the build machine.

- `verify.yml` — status parity, Node tool tests, migrations, Firestore rules
  tests on the emulator, functions build/lint/test, admin ESLint, and
  `flutter analyze` (errors fatal, warnings not) + `flutter test` for both apps.
- `build-customer-apk.yml` / `build-driver-apk.yml` — run `verify.yml` first,
  then `flutter build apk --release` and publish to the `customer-latest` /
  `driver-latest` GitHub Release on pushes to `main`. Signing uses secrets
  `{CUSTOMER,DRIVER}_KEYSTORE_BASE64`, `_KEYSTORE_PASSWORD`, `_KEY_ALIAS`; if
  absent the APK is debug-signed and labelled as a test build.
- `deploy-admin.yml` — deploys `admin_panel/` to Firebase Hosting; needs secret
  `FIREBASE_SERVICE_ACCOUNT_SHIPEAST_1A1F6`.
- Flutter version is pinned in `.tool-versions`. Keep `version:` in each
  `pubspec.yaml` and `SeBrand.version` in `lib/theme/se_brand.dart` in step;
  bump the build number for every APK meant to install over the last.
- Runs locally with Node only: `node tools/test-*.mjs`, `node --test …`,
  `cd functions && npm ci && npm run build && npm test`,
  `cd admin_panel && npm ci && npx eslint app.js`.

## Working with the owner

The owner is not a developer. Explain changes in plain language, handle git
(commit, push, branches) for them, and confirm before anything that touches the
live Firebase project or publishes a release.
