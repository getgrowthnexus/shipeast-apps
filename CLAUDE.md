# ShipEast

Monorepo for the ShipEast delivery platform (imported from
`derionscarlett-lang/Shipeast-App` with full history).

| Folder | What it is | How it ships |
|---|---|---|
| `customer_app/` | Flutter customer app (`com.shipeast.customerapp`) | APK via `build-customer-apk.yml` |
| `driver_app/` | Flutter driver app (`com.shipeast.shipeast_driver`) | APK via `build-driver-apk.yml` |
| `admin_panel/` | Admin web portal (unbundled ES modules, no build step) | Firebase Hosting via `deploy-admin.yml` |
| `functions/` | Firebase Cloud Functions (TypeScript) | `firebase deploy` |
| `firestore.rules`, `storage.rules`, `test/rules/` | Security rules and their emulator tests | `firebase deploy` |
| `tools/` | Parity checks, migrations and JS unit tests run by CI | — |

Flutter is pinned in `.tool-versions` (single source of truth for CI and local).

## Finding the latest APKs

Every push to `main` runs `verify.yml` first, then builds both APKs. When they pass:

- **GitHub Releases** `customer-latest` and `driver-latest` are replaced with the new
  debug-signed APKs (`shipeast-customer.apk`, `shipeast-driver.apk`). Each release's
  notes name the commit it was built from.
- The same APKs are also uploaded as workflow run artifacts
  (`shipeast-customer-apk`, `shipeast-driver-apk`).

To tell the user what's installable, check the latest runs of "Build Customer APK" and
"Build Driver APK" on `main` and the two releases above; report the commit each APK was
built from and whether any build failed (and why). Builds can also be started by hand
through `workflow_dispatch`.

## CI notes

- `verify.yml` gates everything: status-parity checks, Flutter analyze/test for both
  apps, Firestore rules tests, Functions build/lint/test, and admin panel lint.
- `deploy-admin.yml` needs the `FIREBASE_SERVICE_ACCOUNT_SHIPEAST_1A1F6` repository
  secret; without it the deploy step fails (the APK builds don't need any secrets).
- Planning and audit docs live at the root (`PLAN.md`, `execution-all-three-plan.md`,
  `full-audit-*.md`, `SCHEMA.md`, `ROLLBACK.md`).
