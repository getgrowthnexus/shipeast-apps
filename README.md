# ShipEast

ShipEast is a delivery service in Jamaica. Customers order food, send packages, or
have a driver shop for them; drivers pick up and deliver; staff run everything from
an admin website.

## The four parts

| Part | Folder | What it is | Who uses it |
|---|---|---|---|
| Customer app | `customer_app/` | Android app (Flutter) | Customers |
| Driver app | `driver_app/` | Android app (Flutter) | Drivers |
| Admin panel | `admin_panel/` | Website (plain HTML/JS, no build step) | ShipEast staff |
| Backend | `functions/`, `firestore.rules`, `storage.rules`, `firestore.indexes.json` | Firebase: database, logins, file storage, server code | Everything above |

## How they connect

All three front ends talk to **one Firebase project, `shipeast-1a1f6`**. They never talk
to each other directly. Each one reads and writes the shared database, and changes
show up everywhere in real time.

```
 Customer app ─┐
               ├──►  Firebase (shipeast-1a1f6)  ◄── Admin panel
 Driver app ───┘     • Firestore database
                     • Auth (logins)
                     • Storage (photos, documents)
                     • Cloud Functions (trusted server code)
```

- **Firestore database** holds orders, drivers, merchants and their menus, customers,
  promo codes, notifications, overseas enquiries and pricing. Every collection and
  field is described in [`SCHEMA.md`](SCHEMA.md).
- **Security rules** (`firestore.rules`, `storage.rules`) decide who may read or
  change what. For example, a driver can only move an order they hold.
- **Cloud Functions** (`functions/src/`) do the things a phone must not be trusted to do:
  redeem promo codes, confirm deliveries and work out driver commission, record
  ratings, create driver accounts, disable customers, grant admin rights, and send
  push notifications (new orders, status changes, scheduled broadcasts).

### An order's journey

1. **Customer** places an order → it is saved with status `pending`.
2. A function notifies available **drivers**, re-offering it every 2 minutes if nobody takes it.
3. A **driver** accepts → `confirmed`, picks it up → `picked_up`, heads out → `in_transit`.
4. The driver confirms delivery, optionally with a photo → `delivered` (a function records the commission).
5. The customer can rate the driver. **Admin** can follow and manage every step, or cancel.

Allowed moves: `pending → confirmed → picked_up → in_transit → delivered`, and any
active order can go to `cancelled`. The same rules are copied into all three apps and
the backend; CI checks the copies stay identical.

## Getting the apps (APKs)

Every change merged into `main` is tested and then built automatically. The latest
installable APKs are always at the same two links:

- Customer: [Releases → `customer-latest`](../../releases/tag/customer-latest)
- Driver: [Releases → `driver-latest`](../../releases/tag/driver-latest)

These are **debug-signed test builds**. On Android, allow "Install unknown apps" for your
browser or Files app, then open the APK.

## The admin panel

The panel publishes to Firebase Hosting automatically when `admin_panel/` changes on
`main`. For that to work, the repo needs the `FIREBASE_SERVICE_ACCOUNT_SHIPEAST_1A1F6`
secret (Settings → Secrets and variables → Actions). Until it's added, the workflow
still lints the panel but skips publishing.

## Automatic checks (CI)

`.github/workflows/verify.yml` runs on every pull request and every push to `main`:

- Flutter analyze and tests for both apps
- Firestore security-rule tests against the emulator (`test/rules/`)
- Cloud Functions build, lint and tests
- Admin panel syntax, lint, and unit tests for its logic (`tools/test-*.mjs`)
- A check that the order-status rules are identical in every app

An APK is only published if all of these pass.

## Folder map

```
customer_app/        Customer Android app (lib/screens = one file per screen)
driver_app/          Driver Android app
admin_panel/         Admin website (index.html + app.js + small logic modules)
functions/src/       Cloud Functions (TypeScript), each with its own *.test.ts
firestore.rules      Database security rules
storage.rules        File-storage security rules
test/rules/          Tests for the security rules
tools/               Dev scripts: local preview, emulator seed data, data
                     migrations (tools/migrate), admin bootstrap, logic tests
SCHEMA.md            The database, collection by collection
ROLLBACK.md          How to roll back each part if a release goes wrong
.tool-versions       Pinned Flutter/Node versions used by CI
```

## Running everything locally

`tools/dev-up.sh` starts the Firebase emulators (a fake, local backend) plus both apps
in a browser and the admin panel, so you can click through without touching real data.
The script's header explains the ports and its limits.

## Current state and known gaps

- **Android only.** The `ios/` folders are kept for later, but iOS isn't connected to
  Firebase yet (it needs the iOS app registered in Firebase and its config file added).
- **Test signing.** APKs are signed with a debug key, which is fine for testing but not for
  the Play Store.
- **Payment Methods** in the customer's profile shows a "Coming soon" page.
- **`feat/admin-brand-2026` branch.** This is a large unmerged redesign of all three apps
  (the "2026 brand"), kept separate until it has been compared against the apps that are
  currently in use.
