#!/usr/bin/env node
/* Verifies the canonical order lifecycle is identical across all three apps.
   (execution-all-three-plan.md P1-02)

   Two checks:
     1. The two Dart copies are byte-identical.
     2. The admin panel's JS copy declares the same statuses and the same
        transition table as the Dart.

   Check 2 is the one the plan does not ask for, and the one that matters most.
   A byte-diff between the Dart files cannot notice the admin panel drifting —
   and the admin panel is where the original damage was done: its dropdown
   offered a status ('in_transit') that fell outside the driver's active-order
   query, which stripped drivers of live deliveries mid-route.

   Parses the Dart rather than importing it, which is why this is a text
   comparison of a structure rather than a behavioural test. The Dart
   behaviour is covered by order_status_test.dart in both apps.

   Retire this when P6-04 lands packages/shipeast_core. */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const CUSTOMER = 'customer_app/lib/models/order_status.dart';
const DRIVER = 'driver_app/lib/models/order_status.dart';
const ADMIN = 'admin_panel/order-status.js';
const FUNCTIONS = 'functions/src/orderStatus.ts';

const problems = [];
const read = (p) => readFileSync(join(ROOT, p), 'utf8');

// ── 1. The Dart copies must be byte-identical ──────────────────────────────
// Every model file the two apps share by copy is checked here. A file added to
// one app and forgotten in the other is the exact failure mode this catches —
// it compiles in both, and the two apps then disagree at runtime.
const SHARED_DART = [
  ['order_status.dart', CUSTOMER, DRIVER],
  [
    'order_type.dart',
    'customer_app/lib/models/order_type.dart',
    'driver_app/lib/models/order_type.dart',
  ],
];

const customerSrc = read(CUSTOMER);
const driverSrc = read(DRIVER);

for (const [name, customerPath, driverPath] of SHARED_DART) {
  let a, b;
  try {
    a = read(customerPath);
    b = read(driverPath);
  } catch (e) {
    // A missing copy is a divergence too, and a bare ENOENT stack does not say
    // which app forgot the file.
    problems.push(`${name} could not be read in both apps: ${e.message}`);
    continue;
  }
  if (a !== b) {
    problems.push(
      `${name} has diverged between apps.\n` +
      `  ${customerPath}\n  ${driverPath}\n` +
      `  These must be byte-identical. Edit both, or neither.`
    );
  } else {
    console.log(`ok   ${name} copies are byte-identical (${a.length} bytes)`);
  }
}

// ── 2. The admin JS must declare the same lifecycle ────────────────────────

/** Extracts `pending: [confirmed, cancelled],` style entries from the Dart
 *  `transitions` map, resolving the identifier names to their string values. */
function parseDartTransitions(src) {
  const constants = {};
  for (const m of src.matchAll(/static const (\w+) = '([a-z_]+)';/g)) {
    constants[m[1]] = m[2];
  }

  const block = src.match(/static const transitions = <String, List<String>>\{([\s\S]*?)\n {2}\};/);
  if (!block) throw new Error('could not locate the `transitions` map in the Dart source');

  const table = {};
  for (const m of block[1].matchAll(/(\w+):\s*\[([^\]]*)\]/g)) {
    const from = constants[m[1]];
    if (!from) throw new Error(`unknown Dart identifier "${m[1]}" as a transition key`);
    const to = m[2].split(',').map((s) => s.trim()).filter(Boolean).map((name) => {
      if (!constants[name]) throw new Error(`unknown Dart identifier "${name}" in transitions`);
      return constants[name];
    });
    table[from] = to;
  }
  return table;
}

const dartTransitions = parseDartTransitions(customerSrc);
const admin = await import(join(ROOT, ADMIN));

const dartStatuses = Object.keys(dartTransitions).sort();
const adminStatuses = [...admin.ALL].sort();

if (dartStatuses.join() !== adminStatuses.join()) {
  problems.push(
    `Status vocabulary differs between Dart and the admin panel.\n` +
    `  dart : ${dartStatuses.join(', ')}\n` +
    `  admin: ${adminStatuses.join(', ')}`
  );
} else {
  console.log(`ok   status vocabulary matches (${dartStatuses.length}): ${dartStatuses.join(', ')}`);
}

for (const from of dartStatuses) {
  const a = (dartTransitions[from] || []).slice().sort().join(', ');
  const b = (admin.TRANSITIONS[from] || []).slice().sort().join(', ');
  if (a !== b) {
    problems.push(
      `Transitions from "${from}" differ.\n  dart : [${a}]\n  admin: [${b}]`
    );
  }
}
if (!problems.some((p) => p.startsWith('Transitions'))) {
  console.log('ok   transition tables match for every status');
}

// ── 3. The functions copy must declare the same lifecycle ─────────────────
// Parsed as text rather than imported: it is TypeScript, and compiling it just
// to run this check would make a cheap job depend on the build.
const fnSrc = read(FUNCTIONS);

function parseTsTransitions(src) {
  const constants = {};
  for (const m of src.matchAll(/export const ([A-Z_]+) = '([a-z_]+)';/g)) {
    constants[m[1]] = m[2];
  }
  const block = src.match(/export const TRANSITIONS[^=]*=\s*\{([\s\S]*?)\n\};/);
  if (!block) throw new Error('could not locate TRANSITIONS in the functions source');

  const table = {};
  for (const m of block[1].matchAll(/\[(\w+)\]:\s*\[([^\]]*)\]/g)) {
    const from = constants[m[1]];
    if (!from) throw new Error(`unknown TS identifier "${m[1]}" as a transition key`);
    table[from] = m[2].split(',').map((x) => x.trim()).filter(Boolean).map((name) => {
      if (!constants[name]) throw new Error(`unknown TS identifier "${name}" in TRANSITIONS`);
      return constants[name];
    });
  }
  return table;
}

const fnTransitions = parseTsTransitions(fnSrc);
const fnStatuses = Object.keys(fnTransitions).sort();

if (fnStatuses.join() !== dartStatuses.join()) {
  problems.push(
    `Status vocabulary differs between Dart and functions.\n` +
    `  dart     : ${dartStatuses.join(', ')}\n` +
    `  functions: ${fnStatuses.join(', ')}`
  );
} else {
  console.log('ok   functions vocabulary matches');
}

let fnTransitionsMatch = true;
for (const from of dartStatuses) {
  const a = (dartTransitions[from] || []).slice().sort().join(', ');
  const b = (fnTransitions[from] || []).slice().sort().join(', ');
  if (a !== b) {
    fnTransitionsMatch = false;
    problems.push(
      `Transitions from "${from}" differ between Dart and functions.\n` +
      `  dart     : [${a}]\n  functions: [${b}]`
    );
  }
}
if (fnTransitionsMatch) console.log('ok   functions transition table matches');

// 'accepted' is retired; make sure nobody reintroduces it. Comments are
// stripped first — both files discuss the retired status in prose explaining
// why it was removed, and matching that would be a false positive.
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')   // block comments
    .replace(/^\s*\/\/.*$/gm, '');      // line and /// doc comments
}

const retired = 'accepted';
const inDart = stripComments(customerSrc).includes(`'${retired}'`);
const inAdmin = stripComments(read(ADMIN)).includes(`'${retired}'`) ||
  admin.ALL.includes(retired);
const inFunctions = stripComments(fnSrc).includes(`'${retired}'`);

if (inDart || inAdmin || inFunctions) {
  problems.push(
    `'${retired}' is a retired status and must not appear in the lifecycle ` +
    `(dart: ${inDart}, admin: ${inAdmin}, functions: ${inFunctions}).`
  );
} else {
  console.log(`ok   retired status '${retired}' is absent from all copies`);
}

// ── Report ─────────────────────────────────────────────────────────────────
if (problems.length) {
  console.error('\nStatus parity check FAILED:\n');
  for (const p of problems) {
    console.error('::error::' + p.split('\n')[0]);
    console.error(p + '\n');
  }
  process.exit(1);
}

console.log('\nStatus parity check passed.');
