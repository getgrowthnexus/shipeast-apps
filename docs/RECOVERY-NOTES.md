# Recovery notes — 2026-09-28

This folder is now the source of truth for ShipEast. It was rebuilt from the old
GitHub repo (`derionscarlett-lang/Shipeast-App`) after the Codespace holding
unpushed work was deleted.

## What was on GitHub

Two lines of work had forked from the same commit (`ce37142`, 2026-07-30) and
were never joined:

| Line | What it holds | Versions |
|---|---|---|
| `feat/admin-brand-2026` (PR 7, Aug 1–3) | Full 2026 brand redesign of all three apps, driver launcher icon, v1+v2+v3 APK signing, CI fix that stops publishing debug-signed APKs | customer 1.2.2+16, driver 1.2.2+11 |
| old `main` (Sep 20, `c4537fa`) | Client review round: promo eligibility, phone utils, driver document photos, paused/suspended drivers, driver card roster, order filters, wording changes — built on the *pre-redesign* code | customer 1.0.9+10, driver 1.1.6+8 |

PRs 2–6 were already contained in `main`. PR 1 (`redesign/customer-app-ui`,
June) is an early customer redesign superseded by PR 7.

## What `main` is now

`main` = merge commit `c4c3f65`: the redesign **plus** every Sep-20 feature,
ported onto the redesign's components and tokens. See that commit's message
for the file-by-file resolution.

Verified locally: all `tools/` Node suites, admin ESLint, Cloud Functions
build/lint/tests. **Not yet compiled:** the two Flutter apps (no Flutter SDK
on this PC) — the first CI run on the new repo is the compile check.

Anything done in the Codespace *after* 2026-08-03 that was never pushed is
not recoverable from GitHub; compare the APKs you have against this build and
list what's missing.

## Branches kept

- `main` — combined, current.
- `archive/main-before-merge-2026-09-20` — old `main` exactly as it was.
- `feat/*`, `redesign/customer-app-ui` — every branch from the old repo.
- Remote renamed `old-github` so nothing pushes there by accident.
- Full-history backup bundle: `../ShipEast Backup/shipeast-full-history-*.bundle`
  (restore with `git clone <bundle> <folder>`).
- PR descriptions/discussion: `docs/github-archive/pull-requests.md`.

## Moving to the new GitHub repo

1. Create an empty repo on the new account (no README), then:
   `git remote add origin <new-url>` and `git push -u origin --all && git push origin --tags`.
2. Add Actions secrets (values are never readable from the old repo):
   - `CUSTOMER_KEYSTORE_BASE64`, `CUSTOMER_KEYSTORE_PASSWORD`, `CUSTOMER_KEY_ALIAS`
   - `DRIVER_KEYSTORE_BASE64`, `DRIVER_KEYSTORE_PASSWORD`, `DRIVER_KEY_ALIAS`
   - `FIREBASE_SERVICE_ACCOUNT_SHIPEAST_1A1F6` (admin panel deploy)
3. The Sep-20 customer APK was signed with the **Android debug key**, i.e. the
   old repo never had release keystores. Create one release keystore per app
   once, keep the `.jks` files and passwords somewhere safe outside git, and
   put them in the secrets above. Without them CI will build but (by design)
   not publish the APK.
4. Existing installs are debug-signed, so the first release-signed APK must be
   installed after uninstalling the old app on each phone. After that,
   updates install normally.
