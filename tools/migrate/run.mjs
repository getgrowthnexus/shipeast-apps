#!/usr/bin/env node
/* Migration runner (P2-05).
 *
 *   node tools/migrate/run.mjs --project shipeast-staging --dry-run
 *   node tools/migrate/run.mjs --project shipeast-staging --only merchants
 *   node tools/migrate/run.mjs --project shipeast-1a1f6 --confirm-production
 *
 * Properties, each of which exists because of a specific way migrations go
 * wrong:
 *
 *   Dry-run by DEFAULT. Writing requires an explicit --execute. The reverse
 *   default has destroyed production databases.
 *
 *   Idempotent. Every migration returns null for an already-converted
 *   document, so a resumed run is a no-op. Asserted by migrations.test.mjs.
 *
 *   Resumable. Progress is checkpointed per collection, so an interrupted run
 *   continues rather than restarting.
 *
 *   Loud about what it cannot decide. Values that cannot be derived —
 *   a merchant's real delivery ETA, an unparseable promo expiry — are
 *   defaulted AND flagged in `_needsReview`, then listed in the report for a
 *   human. The script never invents a business value.
 *
 * Requires:
 *   - GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account key
 *   - firebase-admin resolvable. The functions package already has it:
 *       NODE_PATH=functions/node_modules node tools/migrate/run.mjs ...
 *     or `npm i --no-save firebase-admin` at the repo root.
 *
 * The pure migration logic in migrations.mjs has NO such dependency, which is
 * why migrations.test.mjs runs in CI without any credentials at all.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ALL, DELETE } from './migrations.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const STATE_DIR = join(HERE, '.state');

function parseArgs(argv) {
  const args = { dryRun: true, only: null, project: null, confirmProduction: false, batchSize: 400 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--execute') args.dryRun = false;
    else if (a === '--dry-run') args.dryRun = true;
    else if (a === '--confirm-production') args.confirmProduction = true;
    else if (a === '--only') args.only = argv[++i];
    else if (a === '--project') args.project = argv[++i];
    else if (a === '--batch-size') args.batchSize = Number(argv[++i]) || 400;
    else if (a === '--help' || a === '-h') { usage(); process.exit(0); }
    else { console.error(`Unknown argument: ${a}`); usage(); process.exit(2); }
  }
  return args;
}

function usage() {
  console.log(`
Usage: node tools/migrate/run.mjs --project <id> [options]

  --project <id>           Firebase project (required)
  --dry-run                Report only. THE DEFAULT.
  --execute                Actually write. Requires deliberate opt-in.
  --only <collection>      One migration: ${ALL.map((m) => m.collection).join(', ')}
  --confirm-production     Required when --project is the production project
  --batch-size <n>         Documents per batched commit (default 400)
`);
}

const PRODUCTION = 'shipeast-1a1f6';

function checkpointPath(project, collection) {
  return join(STATE_DIR, `${project}.${collection}.json`);
}

function loadCheckpoint(project, collection) {
  const p = checkpointPath(project, collection);
  if (!existsSync(p)) return null;
  try {
    return JSON.parse(readFileSync(p, 'utf8')).lastDocId ?? null;
  } catch {
    return null;
  }
}

function saveCheckpoint(project, collection, lastDocId) {
  if (!existsSync(STATE_DIR)) mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(
    checkpointPath(project, collection),
    JSON.stringify({ lastDocId, at: new Date().toISOString() }, null, 2)
  );
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.project) {
    console.error('--project is required.');
    usage();
    process.exit(2);
  }

  if (args.project === PRODUCTION && !args.dryRun && !args.confirmProduction) {
    console.error(
      `\nRefusing to write to production (${PRODUCTION}) without ` +
      `--confirm-production.\n\n` +
      `Before you pass it, the protocol in ROLLBACK.md requires:\n` +
      `  1. A full Firestore export taken immediately before.\n` +
      `  2. That export RESTORED into a scratch project and verified. An\n` +
      `     untested backup is not a backup.\n` +
      `  3. A reviewed dry-run diff of this exact migration set.\n` +
      `  4. The lowest-traffic window.\n`
    );
    process.exit(2);
  }

  // Validate arguments BEFORE touching firebase-admin. Otherwise a typo'd
  // --only fails with a module-resolution error from a missing dependency,
  // which tells the operator nothing about what they actually got wrong.
  const selected = args.only
    ? ALL.filter((m) => m.collection === args.only)
    : ALL;

  if (selected.length === 0) {
    console.error(
      `No migration named "${args.only}". ` +
      `Available: ${ALL.map((m) => m.collection).join(', ')}`
    );
    process.exit(2);
  }

  const { default: admin } = await import('firebase-admin');
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: args.project });
  }
  const db = admin.firestore();

  console.log(`\nProject : ${args.project}`);
  console.log(`Mode    : ${args.dryRun ? 'DRY RUN (no writes)' : 'EXECUTE (writing)'}`);
  console.log(`Running : ${selected.map((m) => m.collection).join(', ')}\n`);

  const report = { scanned: 0, changed: 0, skipped: 0, review: [] };

  for (const migration of selected) {
    console.log(`── ${migration.collection} ${'─'.repeat(Math.max(0, 56 - migration.collection.length))}`);
    console.log(`   ${migration.describe}`);

    const resumeFrom = args.dryRun ? null : loadCheckpoint(args.project, migration.collection);
    if (resumeFrom) console.log(`   resuming after ${resumeFrom}`);

    let query = db.collection(migration.collection).orderBy('__name__').limit(args.batchSize);
    if (resumeFrom) {
      query = db.collection(migration.collection)
        .orderBy('__name__')
        .startAfter(resumeFrom)
        .limit(args.batchSize);
    }

    let scanned = 0, changed = 0, lastId = resumeFrom;

    for (;;) {
      const snap = await query.get();
      if (snap.empty) break;

      const batch = db.batch();
      let batchWrites = 0;

      for (const docSnap of snap.docs) {
        scanned++;
        const data = docSnap.data();
        const updates = migration.migrate(data);
        lastId = docSnap.id;

        if (!updates) continue;
        changed++;

        if (updates._needsReview) {
          report.review.push({
            collection: migration.collection,
            id: docSnap.id,
            reason: updates._needsReview
          });
        }

        // Preview the first few so the dry-run is inspectable, not just a count.
        if (args.dryRun && changed <= 5) {
          const preview = Object.fromEntries(
            Object.entries(updates).map(([k, v]) => [k, v === DELETE ? '<DELETE>' : v])
          );
          console.log(`   ${docSnap.id}: ${JSON.stringify(preview)}`);
        }

        if (!args.dryRun) {
          const payload = {};
          for (const [k, v] of Object.entries(updates)) {
            if (k === '_subdocs') continue;   // handled below, not a field
            payload[k] = v === DELETE ? admin.firestore.FieldValue.delete() : v;
          }

          /* Subcollection writes, for migrations that MOVE data rather than
             rename it (P4-05 moves licenceNumber to private/identity). Queued
             before the parent update so a single batch either writes the copy
             and deletes the original, or does neither — an interrupted run can
             never leave the value nowhere. */
          for (const sub of updates._subdocs ?? []) {
            batch.set(docSnap.ref.collection(sub.path[0]).doc(sub.path[1]),
              sub.data, { merge: true });
            batchWrites++;
          }

          batch.update(docSnap.ref, payload);
          batchWrites++;
        }
      }

      if (!args.dryRun && batchWrites > 0) {
        await batch.commit();
        saveCheckpoint(args.project, migration.collection, lastId);
      }

      if (snap.size < args.batchSize) break;
      query = db.collection(migration.collection)
        .orderBy('__name__')
        .startAfter(lastId)
        .limit(args.batchSize);
    }

    console.log(`   scanned ${scanned}, ${args.dryRun ? 'would change' : 'changed'} ${changed}\n`);
    report.scanned += scanned;
    report.changed += changed;
    report.skipped += scanned - changed;
  }

  console.log('═'.repeat(60));
  console.log(`scanned ${report.scanned} · ${args.dryRun ? 'would change' : 'changed'} ${report.changed} · already correct ${report.skipped}`);

  if (report.review.length) {
    console.log(`\n⚠  ${report.review.length} document(s) need a human decision:\n`);
    for (const r of report.review.slice(0, 40)) {
      console.log(`   ${r.collection}/${r.id} — ${r.reason}`);
    }
    if (report.review.length > 40) {
      console.log(`   … and ${report.review.length - 40} more`);
    }
    const out = join(HERE, `review-${args.project}-${Date.now()}.json`);
    writeFileSync(out, JSON.stringify(report.review, null, 2));
    console.log(`\n   Full list: ${out}`);
    console.log('   These were defaulted, not guessed. Query _needsReview to find them.');
  }

  if (args.dryRun) {
    console.log('\nDry run — nothing was written. Re-run with --execute to apply.');
  }
}

main().catch((e) => {
  console.error('\nMigration failed:', e.message);
  console.error('Re-run the same command; completed collections resume from their checkpoint.');
  process.exit(1);
});
