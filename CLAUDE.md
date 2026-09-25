# ShipEast: notes for Claude

Start with `README.md`: it maps the four parts (customer app, driver app, admin panel,
Firebase backend), how an order moves between them, and the current known gaps.
`SCHEMA.md` is the source of truth for every Firestore collection and field; code
comments cite it as `SCHEMA.md §x`.

| Folder | Package / target |
|---|---|
| `customer_app/` | Flutter, `com.shipeast.customerapp` |
| `driver_app/` | Flutter, `com.shipeast.shipeast_driver` |
| `admin_panel/` | Unbundled ES modules on Firebase Hosting |
| `functions/` | Cloud Functions (TypeScript, Node 20) |

Toolchain versions are pinned in `.tool-versions`. Flutter isn't installed in every
environment, so a Dart change may only be checkable in CI.

## Finding the latest APKs

Every push to `main` runs `verify.yml`, then `build-customer-apk.yml` and
`build-driver-apk.yml`. When they pass, the GitHub Releases `customer-latest` and
`driver-latest` are replaced with new debug-signed APKs (`shipeast-customer.apk`,
`shipeast-driver.apk`); the release notes name the commit. The same files are attached
to each run as artifacts. Builds on other branches can be started with
`workflow_dispatch`; those produce only artifacts, not releases.

To tell the user what's installable, check the latest runs of both APK workflows on
`main` and the two releases, and report each APK's commit and any failure.

## Conventions that CI enforces

- The order-status lifecycle is duplicated in `customer_app`, `driver_app`,
  `admin_panel/order-status.js` and `functions/src/orderStatus.ts`;
  `tools/check-status-parity.mjs` fails CI if they drift. Change all four together.
- Admin panel logic lives in import-free modules so `tools/test-*.mjs` can test it in
  plain Node. Keep new logic there, not in `app.js`.
- Money is stored as integers (SCHEMA.md §a).
- `deploy-admin.yml` skips publishing when the `FIREBASE_SERVICE_ACCOUNT_SHIPEAST_1A1F6`
  secret is missing; the APK builds need no secrets.
