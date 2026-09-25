# Rollback Plan

**Implements:** [execution-all-three-plan.md](execution-all-three-plan.md) P2-06
**Scope:** every deployable artifact — client APKs, admin panel, rules, indexes, functions, data.

> A rollback plan that has never been executed is a hypothesis. **Rehearse the data restore on
> staging at least once before the first production migration**, and record the date below.
>
> | Rehearsal | Date | By | Outcome |
> |---|---|---|---|
> | Data restore into a scratch project | ⬜ not yet done | — | — |
> | Rules rollback on staging | ⬜ not yet done | — | — |

---

## The one that will actually bite you

Ranked by the plan's own risk register, the most likely failure is **not** data corruption — it is
a **rules deploy blocking a legitimate flow**. The symptom is a spike in permission-denied errors
and users reporting that something "just stopped working", while every dashboard looks healthy.

**Detection:** watch the Firestore rules-denial rate for the first hour after any rules deploy. A
spike means a legitimate path is blocked.

**Rollback:** seconds, and safe — rules carry no state.

```bash
git checkout <previous-tag> -- firestore.rules storage.rules
firebase deploy --only firestore:rules,storage --project shipeast-1a1f6
```

Then reproduce the blocked flow against the emulator, add the missing case to
`test/rules/firestore.rules.test.js`, and only redeploy once that test passes. **Do not** widen a
rule directly in the console — the console version is invisible to CI and will be silently
overwritten by the next deploy.

---

## Per-artifact rollback

### Firestore rules / Storage rules

Stateless, instantly reversible, as above. Always deploy rules **before** the clients that depend
on them, and roll back in the reverse order.

### Indexes

Adding an index is safe and non-breaking. **Deleting one is not** — a query with no index fails
outright. If a deploy removed an index, re-add it and wait for the build to finish (minutes to
hours depending on collection size). Never `--force` an index deploy against production without
reading the diff.

### Cloud Functions

```bash
# List versions, then roll back to a known-good release.
firebase functions:list --project shipeast-1a1f6
git checkout <previous-tag> -- functions/
cd functions && npm ci && npm run build
firebase deploy --only functions --project shipeast-1a1f6
```

Functions are versioned per-deploy. Note that a rolled-back function may still receive events
queued by the newer version, so **handlers must be idempotent** — that is a design requirement, not
a rollback step.

### Admin panel (hosting)

```bash
firebase hosting:rollback --project shipeast-1a1f6
```

Or via the console's release history. Instant, and the safest rollback in the system: the panel is
static and holds no state.

### Client APKs — the one you cannot roll back

**You cannot recall an installed APK.** Both apps ship as sideloaded artifacts from GitHub
Releases, so a user on a broken build stays on it until they choose to update — and some never
will.

This is why the migration protocol below insists both data shapes are readable for a full release
cycle. Concretely:

- Publish the previous APK to the `customer-latest` / `driver-latest` release to stop *new*
  installs of a bad build.
- **Assume the bad build is still in the field.** If it writes malformed data, the fix belongs in
  rules (which reject it) or in a function (which repairs it) — not in a client update you cannot
  force.
- Consider the forced-upgrade check the plan's risk register recommends.

---

## Data restore

The heaviest and slowest rollback. Budget hours, not minutes.

### Before any production migration

1. **Full export**, immediately before:
   ```bash
   gcloud firestore export gs://shipeast-backups/$(date +%Y%m%d-%H%M) \
     --project shipeast-1a1f6
   ```
2. **Verify the export is restorable by actually restoring it** into a scratch project. An
   untested backup is not a backup — this is the single step teams skip and regret.
   ```bash
   gcloud firestore import gs://shipeast-backups/<stamp> --project shipeast-restore-test
   ```
3. Run the migration **dry-run** and review the diff (dry-run is the default):
   ```bash
   NODE_PATH=functions/node_modules node tools/migrate/run.mjs --project shipeast-1a1f6
   ```
4. Execute only in the lowest-traffic window, with `--confirm-production`.
5. Verify with a read-only assertion pass.
6. **Keep the export for 30 days.**

### Restoring

```bash
gcloud firestore import gs://shipeast-backups/<stamp> --project shipeast-1a1f6
```

**Import does not delete documents created after the export.** A restore therefore *merges* — it
does not rewind. Orders placed during the bad window survive, in whatever shape the bad code wrote
them. Plan for reconciliation, not a clean revert.

**This is why the migrations are designed not to need a restore.** They are idempotent, they never
overwrite an already-canonical value, and they flag anything they cannot derive rather than
guessing. A re-run is cheaper and safer than an import, and should always be the first response.

---

## Phase-by-phase

| Phase | Riskiest artifact | Rollback | Reversible? |
|---|---|---|---|
| 1 — canonical statuses | Client APKs | Republish previous APK | ⚠️ Not for installed apps |
| 2 — rules, indexes, functions | **Rules** | Redeploy previous tag | ✅ Seconds |
| 2 — data migration | Firestore data | Re-run migration; import as last resort | ⚠️ Import merges, does not rewind |
| 3 — money and integrity | Order economics | Rules + client rollback together | ⚠️ Historical orders keep new shape |
| 4 — uploads, push | Storage rules, functions | Independent, low risk | ✅ |
| 5 — product surface | Client APKs | Republish | ⚠️ |

**Ordering rule.** Deploy rules → functions → hosting → clients. Roll back in reverse. Rules and
the clients that depend on them must land in the same window, or a legitimate flow is blocked in
the gap.

---

## What to watch after any production deploy

For 48 hours (the plan's P6-07 monitoring window):

- **Rules-denial rate** — the leading indicator; a spike means a blocked legitimate flow
- Crashlytics, both apps
- Functions error rate and cold-start latency
- Firestore read/write volume — an unexpected jump means an unbounded query shipped
- Order completion rate — the business metric that catches what the technical ones miss

---

## Emergency contacts and access

Fill in before launch. A rollback plan nobody has access to execute is not a plan.

| Role | Who | Access needed |
|---|---|---|
| Firebase project owner | ⬜ | Console, `gcloud`, deploy |
| GitHub repo admin | ⬜ | Releases, branch protection |
| On-call for launch window | ⬜ | Both of the above |
