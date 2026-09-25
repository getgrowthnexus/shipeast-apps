#!/usr/bin/env node
/* Package pricing editor (P5-01).
 *
 * `admin_panel/pricing-form.js` imports nothing, so plain Node can load it —
 * which is the only reason the admin panel's parsing is testable at all, since
 * the panel has no build step and ships unbundled modules to the browser.
 *
 * What is being protected: the customer app declines to quote a package price
 * unless this table exists, so a table that parses *wrongly* is worse than one
 * that fails to parse. Every case below is a way the admin's intent and the
 * saved table could quietly disagree.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  parseBands, formatBands, describeBands, parseAmount, OPEN_BAND
} from '../admin_panel/pricing-form.js';

describe('parseBands', () => {
  test('parses the ordinary four-line table', () => {
    const { bands, errors } = parseBands('2 = 600\n5 = 900\n10 = 1400\n+ = 2200');
    assert.deepEqual(errors, []);
    assert.deepEqual(bands, [
      { maxKg: 2, price: 600 },
      { maxKg: 5, price: 900 },
      { maxKg: 10, price: 1400 },
      { maxKg: null, price: 2200 }
    ]);
  });

  test('sorts bands so what is saved is what was previewed', () => {
    const { bands, errors } = parseBands('+ = 2200\n10 = 1400\n2 = 600');
    assert.deepEqual(errors, []);
    assert.deepEqual(bands.map((b) => b.maxKg), [2, 10, null]);
  });

  test('tolerates blank lines, comments, dollar signs and thousands separators', () => {
    const { bands, errors } = parseBands(
      '# Standard rates, agreed March\n\n  2 = $600 \n\n10 = 1,400\n'
    );
    assert.deepEqual(errors, []);
    assert.deepEqual(bands, [
      { maxKg: 2, price: 600 },
      { maxKg: 10, price: 1400 }
    ]);
  });

  test('accepts a fractional bound', () => {
    const { bands, errors } = parseBands('0.5 = 400\n+ = 900');
    assert.deepEqual(errors, []);
    assert.equal(bands[0].maxKg, 0.5);
  });

  test('rounds a fractional price — rules require an integer', () => {
    // The order create rule demands `deliveryFee is int`; a double fails the
    // write, and the customer would see the form succeed with no order behind
    // it.
    const { bands } = parseBands('2 = 599.6');
    assert.equal(bands[0].price, 600);
  });

  test('an empty table is an error, not an empty price list', () => {
    // Saving nothing would read to the apps as "packages unavailable", which
    // may be what the admin wants but is never what they meant by pressing
    // Save on a pricing form.
    const { errors } = parseBands('   \n\n');
    assert.equal(errors.length, 1);
    assert.match(errors[0], /at least one band/i);
  });

  test('reports a malformed line with its line number', () => {
    const { errors } = parseBands('2 = 600\nthis is not a band\n+ = 900');
    assert.equal(errors.length, 1);
    assert.match(errors[0], /Line 2/);
  });

  test('rejects a price that is not a number', () => {
    const { errors } = parseBands('2 = free');
    assert.equal(errors.length, 1);
    assert.match(errors[0], /not a price/i);
  });

  test('rejects a negative price', () => {
    const { errors } = parseBands('2 = -100');
    assert.match(errors[0], /not a price/i);
  });

  test('rejects a zero or negative weight bound', () => {
    // maxKg 0 is unreachable, so every parcel silently falls through to the
    // next band and the admin's cheapest tier never applies.
    for (const line of ['0 = 600', '-2 = 600', 'abc = 600', ' = 600']) {
      const { errors } = parseBands(line);
      assert.ok(errors.length > 0, line);
    }
  });

  test('rejects a second open-ended band', () => {
    const { errors } = parseBands('+ = 600\n+ = 900');
    assert.equal(errors.length, 1);
    assert.match(errors[0], /only be one/i);
  });

  test('rejects two bands ending at the same weight', () => {
    // One of them can never be reached. Almost always a line that was copied
    // to be edited and then was not.
    const { errors } = parseBands('5 = 900\n5 = 1200');
    assert.equal(errors.length, 1);
    assert.match(errors[0], /both end at 5/);
  });

  test('a table with no open band is allowed', () => {
    // It means "we do not carry anything heavier", which the customer app
    // reports honestly rather than quoting.
    const { bands, errors } = parseBands('2 = 600\n5 = 900');
    assert.deepEqual(errors, []);
    assert.equal(bands.length, 2);
  });

  test('junk input never throws', () => {
    for (const input of [null, undefined, '', 0, {}, []]) {
      assert.doesNotThrow(() => parseBands(input), String(input));
    }
  });
});

describe('formatBands', () => {
  test('round-trips a parsed table', () => {
    const text = '2 = 600\n5 = 900\n+ = 2200';
    const { bands } = parseBands(text);
    assert.equal(formatBands(bands), text);
  });

  test('renders the open band with its marker', () => {
    assert.equal(formatBands([{ maxKg: null, price: 2200 }]), OPEN_BAND + ' = 2200');
  });

  test('survives a malformed stored value', () => {
    // The document is editable from the Firebase console, so this reader must
    // not be the thing that breaks the page.
    assert.equal(formatBands(null), '');
    assert.equal(formatBands('nonsense'), '');
    assert.equal(formatBands([null, 'x', { maxKg: 2, price: 600 }]), '2 = 600');
  });
});

describe('describeBands', () => {
  test('names each range from the previous bound', () => {
    const { bands } = parseBands('2 = 600\n5 = 900\n+ = 2200');
    assert.deepEqual(describeBands(bands, 100), [
      '0–2 kg: J$600',
      '2–5 kg: J$900',
      'Over 5 kg: J$2200 plus J$100 per extra kg'
    ]);
  });

  test('says "flat" when there is no overage rate', () => {
    const { bands } = parseBands('2 = 600\n+ = 2200');
    assert.match(describeBands(bands, 0)[1], /flat/);
  });

  test('describes nothing when there is nothing', () => {
    assert.deepEqual(describeBands([], 0), []);
    assert.deepEqual(describeBands(null, 0), []);
  });
});

describe('parseAmount', () => {
  test('reads a plain number', () => {
    assert.equal(parseAmount('350'), 350);
  });

  test('strips currency formatting', () => {
    assert.equal(parseAmount(' $1,250 '), 1250);
    assert.equal(parseAmount('J$1,250'), 1250);
  });

  test('distinguishes a cleared field from a typed zero', () => {
    // They mean different things for a surcharge: "no packing charge" versus
    // "leave this as it was".
    assert.equal(parseAmount(''), null);
    assert.equal(parseAmount('   '), null);
    assert.equal(parseAmount('0'), 0);
  });

  test('rejects junk and negatives', () => {
    for (const input of ['abc', '-5', 'NaN', {}, null, undefined]) {
      assert.equal(parseAmount(input), null, String(input));
    }
  });
});
