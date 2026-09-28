#!/usr/bin/env node
/* Live tracking — admin panel copy (admin_panel/tracking.js). The same cases
   as tracking_test.dart in both apps, so the three read identically. */
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const T = await import(pathToFileURL(join(ROOT, 'admin_panel/tracking.js')).href);

let failed = 0, passed = 0;
function check(name, fn) {
  try { fn(); passed++; } catch (e) { failed++; console.error('::error::' + name + ': ' + e.message); }
}
function eq(a, b) { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error('expected ' + JSON.stringify(b) + ', got ' + JSON.stringify(a)); }
function ok(v, m) { if (!v) throw new Error(m || 'expected truthy'); }

check('distance: Morant Bay to Yallahs is about 16 km', () => {
  const d = T.distanceM(17.8817, -76.4095, 17.8742, -76.5617);
  ok(d > 15000 && d < 17500, String(d));
});
check('arrive radius: ~111 m is inside, ~333 m is not', () => {
  ok(T.distanceM(17.8817, -76.4095, 17.8827, -76.4095) <= T.ARRIVE_RADIUS_M);
  ok(T.distanceM(17.8817, -76.4095, 17.8847, -76.4095) > T.ARRIVE_RADIUS_M);
});
check('eta and distance labels match the apps', () => {
  eq(T.etaMinutes(0), 1);
  eq(T.etaMinutes(5000), 16);
  eq(T.distanceLabel(447), '450 m');
  eq(T.distanceLabel(3240), '3.2 km');
});
check('live labels match the apps', () => {
  eq(T.liveLabel('confirmed', 'to_pickup'), 'Driver on the way to the restaurant');
  eq(T.liveLabel('confirmed', 'at_pickup'), 'Driver waiting at the restaurant');
  eq(T.liveLabel('confirmed', null, { isPackage: true }), 'Driver on the way to the pickup');
  eq(T.liveLabel('picked_up', null), 'Order picked up');
  eq(T.liveLabel('in_transit', 'to_dropoff'), 'On the way to you');
  eq(T.liveLabel('in_transit', 'to_dropoff', { metresToDropoff: 600 }), 'Driver is nearby');
  eq(T.liveLabel('in_transit', 'at_dropoff'), 'Driver has arrived');
  eq(T.liveLabel('preparing', null), '');
});
check('freshness window is three minutes', () => {
  const now = Date.now();
  ok(T.isFresh(new Date(now - 60000), now));
  ok(!T.isFresh(new Date(now - 4 * 60000), now));
  ok(!T.isFresh(null, now));
});

console.log(`tracking.js: ${passed}/${passed + failed} checks passed`);
if (failed) process.exit(1);
