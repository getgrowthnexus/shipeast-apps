/* ═══════════════════════════════════════════════════════════════
   Live GPS tracking — admin panel copy.
   Source of truth: SCHEMA.md §orders.driverStage / §driverLocations
   ═══════════════════════════════════════════════════════════════

   Mirrors customer_app/lib/models/tracking.dart and the identical driver_app
   copy: the same stage names, the same labels, the same distance and
   rough-time maths, so the admin reads exactly what the customer and driver
   read. Tested by tools/test-tracking.mjs.

   Imports nothing, for the same reason order-status.js does: the panel ships
   unbundled, and a module free of Firebase imports loads in plain Node.   */

export const TO_PICKUP = 'to_pickup';
export const AT_PICKUP = 'at_pickup';
export const TO_DROPOFF = 'to_dropoff';
export const AT_DROPOFF = 'at_dropoff';

export const ARRIVE_RADIUS_M = 150;
export const NEARBY_RADIUS_M = 1000;
/** A position older than this is not "live" any more. */
export const FRESH_MS = 3 * 60 * 1000;

/** Straight-line distance in metres (haversine). */
export function distanceM(lat1, lng1, lat2, lng2) {
  const r = 6371000, rad = (d) => d * Math.PI / 180;
  const dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** Rough minutes by road: ×1.35 winding, ~25 km/h town traffic, never 0. */
export function etaMinutes(metres) {
  return Math.max(1, Math.round(metres * 1.35 / 1000 / 25 * 60));
}

/** "450 m" / "3.2 km". */
export function distanceLabel(metres) {
  return metres < 1000
    ? Math.round(metres / 10) * 10 + ' m'
    : (metres / 1000).toFixed(1) + ' km';
}

/** The live line everyone reads. Empty when no driver is on the job. */
export function liveLabel(status, stage, opts = {}) {
  const place = opts.isPackage ? 'the pickup' : 'the restaurant';
  if (status === 'confirmed') {
    return stage === AT_PICKUP ? 'Driver waiting at ' + place : 'Driver on the way to ' + place;
  }
  if (status === 'picked_up') return 'Order picked up';
  if (status === 'in_transit') {
    if (stage === AT_DROPOFF) return 'Driver has arrived';
    if (opts.metresToDropoff != null && opts.metresToDropoff <= NEARBY_RADIUS_M) return 'Driver is nearby';
    return 'On the way to you';
  }
  return '';
}

/** Whether a position stamp (Date or null) is recent enough to call live. */
export function isFresh(updatedAt, now = Date.now()) {
  return !!updatedAt && now - updatedAt.getTime() <= FRESH_MS;
}
