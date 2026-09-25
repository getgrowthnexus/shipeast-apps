/* Merchant pickup coordinates (P5-06).
 *
 * ## Why this exists
 *
 * A food order copies the merchant's `lat`/`lng` onto itself as
 * `pickupLat`/`pickupLng` (customer_app firestore_service.dart), and the driver
 * dashboard ranks incoming offers by how near that pickup is — nearest-first
 * dispatch. The merchant form never had a way to set those coordinates, so every
 * admin-created merchant produced orders with null pickup coords that sorted to
 * the back of every driver's queue. Seeded merchants got proximity dispatch;
 * hand-added ones silently did not.
 *
 * ## Why a paste box and not a map
 *
 * The panel ships unbundled ES modules with no build step and no third-party
 * runtime dependencies (self-hosted fonts, a local Phosphor sprite — no CDN
 * widgets). A Leaflet/Google map embed would break that and add a supply-chain
 * surface for a field an operator sets once per merchant. Instead the operator
 * does what they already do: open the place in Google Maps, copy the link (or
 * the "lat, lng" from the URL), and paste it here. This module pulls the
 * coordinate pair out of whatever they paste.
 *
 * ## Why this file imports nothing
 *
 * Same reasoning as pricing-form.js and image-upload.js: an import-free module
 * runs under plain Node, which puts the parsing below under CI in
 * tools/test-location-input.mjs. A silent coordinate bug is invisible in
 * production until a driver is dispatched to the wrong side of the island.
 */

/** A finite number string, optionally signed, with an optional decimal part. */
var NUM = '(-?\\d+(?:\\.\\d+)?)';

/* Extraction strategies, in priority order. Google "place" URLs carry the map
   viewport centre in `@lat,lng` AND the pinned place in `!3d<lat>!4d<lng>`; the
   pin is the actual business, so it wins over the viewport. Everything else is a
   fallback down to a bare "lat, lng" a person typed. */
var PATTERNS = [
  // .../data=...!3d18.0176!4d-76.8102  — the pinned place, most precise.
  new RegExp('!3d' + NUM + '!4d' + NUM),
  // .../@18.0179,-76.8099,17z  — the map viewport centre.
  new RegExp('@' + NUM + ',' + NUM),
  // ?q=18.0179,-76.8099 / ?ll=... / ?query=... / &q=...  (comma may be %2C).
  new RegExp('[?&](?:q|ll|query|daddr|saddr)=' + NUM + '(?:,|%2C)' + NUM, 'i'),
  // A bare pair a person typed or copied: "18.0179, -76.8099" or "18 -76.8".
  new RegExp('^\\s*' + NUM + '\\s*[,\\s]\\s*' + NUM + '\\s*$')
];

/**
 * Pulls a `{ lat, lng }` pair out of pasted text: a Google Maps link, a
 * "lat, lng" string, or a `?q=` URL. Returns null when nothing valid is found —
 * including for shortened `maps.app.goo.gl` links, which carry no coordinates
 * until a browser follows the redirect (so the caller must ask for the expanded
 * link rather than guess).
 *
 * Range-checks lat to [-90, 90] and lng to [-180, 180], and rejects exact
 * (0, 0): that is Null Island in the Gulf of Guinea, never a ShipEast merchant,
 * and is the classic signature of an empty/failed field rather than a place.
 */
export function parseLatLng(text) {
  if (typeof text !== 'string') return null;
  var s = text.trim();
  if (!s) return null;
  for (var i = 0; i < PATTERNS.length; i++) {
    var m = s.match(PATTERNS[i]);
    if (!m) continue;
    var lat = Number(m[1]);
    var lng = Number(m[2]);
    if (!isValidLat(lat) || !isValidLng(lng)) continue;
    if (lat === 0 && lng === 0) continue;
    return { lat: lat, lng: lng };
  }
  return null;
}

export function isValidLat(n) {
  return typeof n === 'number' && isFinite(n) && n >= -90 && n <= 90;
}

export function isValidLng(n) {
  return typeof n === 'number' && isFinite(n) && n >= -180 && n <= 180;
}

/** True only for a complete, in-range, non-Null-Island pair. */
export function isValidLatLng(lat, lng) {
  return isValidLat(lat) && isValidLng(lng) && !(lat === 0 && lng === 0);
}

/** Trims a coordinate to ~1 m precision. More than six decimals is noise from a
    URL and only makes the stored number look falsely exact. */
export function roundCoord(n) {
  return Math.round(n * 1e6) / 1e6;
}

/** "18.017900, -76.809900" for display; '' when the pair is incomplete. */
export function formatLatLng(lat, lng) {
  if (!isValidLatLng(lat, lng)) return '';
  return lat.toFixed(6) + ', ' + lng.toFixed(6);
}
