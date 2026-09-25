#!/usr/bin/env node
/* Merchant pickup coordinates (P5-06).
 *
 * `admin_panel/location-input.js` imports nothing, so plain Node can load it —
 * the same reason pricing-form.js and image-upload.js are testable despite the
 * panel having no build step.
 *
 * What is being protected: whatever this parser returns is written to the
 * merchant, denormalised onto every future order as pickupLat/pickupLng, and
 * used to rank which driver is dispatched. A coordinate read from the wrong part
 * of a URL, or a half-parsed pair, is invisible in production until a driver is
 * sent to the wrong side of the island. Every case below is a way the pasted
 * text and the stored point could quietly disagree.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  parseLatLng, isValidLat, isValidLng, isValidLatLng, roundCoord, formatLatLng
} from '../admin_panel/location-input.js';

describe('parseLatLng — plain pairs a person types', () => {
  test('"lat, lng" with a comma', () => {
    assert.deepEqual(parseLatLng('18.0179, -76.8099'), { lat: 18.0179, lng: -76.8099 });
  });

  test('"lat lng" with just a space', () => {
    assert.deepEqual(parseLatLng('18.0179 -76.8099'), { lat: 18.0179, lng: -76.8099 });
  });

  test('surrounding whitespace is ignored', () => {
    assert.deepEqual(parseLatLng('   18.0179 , -76.8099   '), { lat: 18.0179, lng: -76.8099 });
  });

  test('whole-number coordinates', () => {
    assert.deepEqual(parseLatLng('18, -76'), { lat: 18, lng: -76 });
  });
});

describe('parseLatLng — Google Maps links', () => {
  test('a place URL prefers the pinned !3d/!4d over the viewport @', () => {
    // The @ is where the map is centred; !3d/!4d is the business pin. They
    // differ, and the pin is the pickup we want.
    const url = 'https://www.google.com/maps/place/Juici+Patties/@18.0179,-76.8099,17z/'
      + 'data=!3m1!4b1!4m6!3m5!1s0x8edb!8m2!3d18.0176!4d-76.8102';
    assert.deepEqual(parseLatLng(url), { lat: 18.0176, lng: -76.8102 });
  });

  test('a bare @lat,lng viewport link', () => {
    assert.deepEqual(
      parseLatLng('https://www.google.com/maps/@18.0179,-76.8099,15z'),
      { lat: 18.0179, lng: -76.8099 }
    );
  });

  test('a ?q=lat,lng link', () => {
    assert.deepEqual(
      parseLatLng('https://maps.google.com/?q=18.0179,-76.8099'),
      { lat: 18.0179, lng: -76.8099 }
    );
  });

  test('a URL-encoded comma (%2C) in q=', () => {
    assert.deepEqual(
      parseLatLng('https://www.google.com/maps?q=18.0179%2C-76.8099'),
      { lat: 18.0179, lng: -76.8099 }
    );
  });

  test('a shortened maps.app.goo.gl link carries no coordinates → null', () => {
    // It only resolves once a browser follows the redirect; guessing would be
    // worse than asking the operator for the full link.
    assert.equal(parseLatLng('https://maps.app.goo.gl/aBcdEfGhiJk'), null);
  });
});

describe('parseLatLng — refuses the dangerous almost-valid', () => {
  test('empty and non-string inputs', () => {
    assert.equal(parseLatLng(''), null);
    assert.equal(parseLatLng('   '), null);
    assert.equal(parseLatLng(null), null);
    assert.equal(parseLatLng(undefined), null);
    assert.equal(parseLatLng(42), null);
  });

  test('a single number is not a coordinate', () => {
    assert.equal(parseLatLng('18.0179'), null);
  });

  test('free text with no pair', () => {
    assert.equal(parseLatLng('Kingston, Jamaica'), null);
  });

  test('exact 0,0 is Null Island, never a merchant', () => {
    // The signature of an empty/failed field, not a place in the Gulf of Guinea.
    assert.equal(parseLatLng('0, 0'), null);
    assert.equal(parseLatLng('0.0, 0.0'), null);
  });

  test('out-of-range latitude or longitude is rejected, not clamped', () => {
    assert.equal(parseLatLng('91, -76'), null);
    assert.equal(parseLatLng('18, -181'), null);
  });
});

describe('validity helpers', () => {
  test('isValidLat / isValidLng bound their ranges', () => {
    assert.equal(isValidLat(90), true);
    assert.equal(isValidLat(-90), true);
    assert.equal(isValidLat(90.1), false);
    assert.equal(isValidLat(NaN), false);
    assert.equal(isValidLng(180), true);
    assert.equal(isValidLng(-180.1), false);
  });

  test('isValidLatLng rejects an incomplete or Null-Island pair', () => {
    assert.equal(isValidLatLng(18.0179, -76.8099), true);
    assert.equal(isValidLatLng(NaN, -76.8099), false);
    assert.equal(isValidLatLng(0, 0), false);
  });
});

describe('roundCoord / formatLatLng', () => {
  test('roundCoord trims URL noise to ~1 m (6 decimals)', () => {
    assert.equal(roundCoord(18.017912345), 18.017912);
    assert.equal(roundCoord(-76.80990000001), -76.8099);
  });

  test('formatLatLng pads to six decimals for a stable display', () => {
    assert.equal(formatLatLng(18.0179, -76.8099), '18.017900, -76.809900');
  });

  test('formatLatLng is empty for an unusable pair', () => {
    assert.equal(formatLatLng(NaN, -76.8099), '');
    assert.equal(formatLatLng(0, 0), '');
  });
});
