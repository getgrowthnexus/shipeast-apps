/* Package pricing editor (P5-01).
 *
 * The customer app refuses to quote a package price unless `settings/pricing`
 * defines a weight-band table — deliberately, because inventing a price nobody
 * chose is worse than an unavailable feature. That makes this file the thing
 * that turns the Packages category on.
 *
 * ## Why a textarea and not a row editor
 *
 * A band table is four or five lines that change twice a year. A dynamic
 * add/remove row editor is an order of magnitude more code, more DOM state and
 * more ways to save a half-edited table. One line per band reads exactly like
 * the price list an operator already has on paper:
 *
 *     2 = 600
 *     5 = 900
 *     10 = 1400
 *     + = 2200
 *
 * ## Why this file imports nothing
 *
 * The admin panel has no build step; it ships unbundled ES modules straight to
 * the browser. An import-free module can be loaded by plain Node, which is what
 * puts the parsing below under CI in `tools/test-pricing-form.mjs`. The same
 * reasoning as image-upload.js.
 */

/** Marks the open-ended final band: everything above the last bounded one. */
export var OPEN_BAND = '+';

/**
 * Parses the textarea into the `packageBands` array the apps read.
 *
 * Returns `{ bands, errors }`. A non-empty `errors` means DO NOT SAVE: a
 * partially-parsed table would price parcels from a list the admin never
 * approved, which is the failure `PackagePricing.fromSettings` refuses on the
 * client side too.
 */
export function parseBands(text) {
  var errors = [];
  var bands = [];
  var seenOpen = false;
  var lines = String(text == null ? '' : text).split('\n');

  for (var i = 0; i < lines.length; i++) {
    var raw = lines[i].trim();
    if (raw === '') continue;
    // Tolerate '#' comments so an operator can annotate the table.
    if (raw.charAt(0) === '#') continue;

    var parts = raw.split('=');
    if (parts.length !== 2) {
      errors.push('Line ' + (i + 1) + ': expected "weight = price", got "' + raw + '"');
      continue;
    }

    var left = parts[0].trim();
    var right = parts[1].trim().replace(/[J$,]/g, '');
    var price = Number(right);

    if (right === '' || !isFinite(price) || price < 0) {
      errors.push('Line ' + (i + 1) + ': "' + parts[1].trim() + '" is not a price');
      continue;
    }

    if (left === OPEN_BAND) {
      if (seenOpen) {
        errors.push('Line ' + (i + 1) + ': there can only be one "+" band');
        continue;
      }
      seenOpen = true;
      bands.push({ maxKg: null, price: Math.round(price) });
      continue;
    }

    var maxKg = Number(left);
    if (left === '' || !isFinite(maxKg) || maxKg <= 0) {
      errors.push('Line ' + (i + 1) + ': "' + left + '" is not a weight in kg');
      continue;
    }
    bands.push({ maxKg: maxKg, price: Math.round(price) });
  }

  if (bands.length === 0 && errors.length === 0) {
    errors.push('Add at least one band, or packages stay unavailable.');
  }

  // Sort bounded ascending, open-ended last — the same order the apps expect,
  // so what is saved is what was previewed.
  bands.sort(function (a, b) {
    if (a.maxKg === null) return 1;
    if (b.maxKg === null) return -1;
    return a.maxKg - b.maxKg;
  });

  // A duplicate bound makes one of the two bands unreachable. The admin
  // probably meant to edit a line and added one instead.
  for (var j = 1; j < bands.length; j++) {
    if (bands[j].maxKg !== null && bands[j].maxKg === bands[j - 1].maxKg) {
      errors.push('Two bands both end at ' + bands[j].maxKg + ' kg.');
      break;
    }
  }

  return { bands: bands, errors: errors };
}

/** Renders a stored `packageBands` array back into editable text. */
export function formatBands(bands) {
  if (!Array.isArray(bands)) return '';
  return bands
    .map(function (b) {
      if (!b || typeof b !== 'object') return '';
      var left = b.maxKg == null ? OPEN_BAND : String(b.maxKg);
      return left + ' = ' + (b.price == null ? '' : b.price);
    })
    .filter(function (line) { return line !== ''; })
    .join('\n');
}

/**
 * Plain-language preview of what the table charges.
 *
 * Shown beside the editor because a band list is easy to misread — the boundary
 * cases are exactly where an operator's intent and the parsed table diverge.
 */
export function describeBands(bands, overagePerKg) {
  if (!Array.isArray(bands) || bands.length === 0) return [];
  var out = [];
  var lower = 0;
  for (var i = 0; i < bands.length; i++) {
    var b = bands[i];
    if (b.maxKg == null) {
      var over = Number(overagePerKg) || 0;
      out.push('Over ' + lower + ' kg: J$' + b.price +
        (over > 0 ? ' plus J$' + over + ' per extra kg' : ' flat'));
    } else {
      out.push(lower + '–' + b.maxKg + ' kg: J$' + b.price);
      lower = b.maxKg;
    }
  }
  return out;
}

/**
 * Reads a non-negative integer out of a form field.
 *
 * Returns `null` for blank or junk so the caller can tell "the admin cleared
 * this" from "the admin typed 0", which mean different things for a surcharge.
 */
export function parseAmount(value) {
  var text = String(value == null ? '' : value).trim().replace(/[J$,]/g, '');
  if (text === '') return null;
  var n = Number(text);
  if (!isFinite(n) || n < 0) return null;
  return Math.round(n);
}
