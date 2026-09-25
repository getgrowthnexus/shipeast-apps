/**
 * Unit tests for the admin panel's image pipeline (P4-01 / P4-02).
 *
 * The admin panel ships unbundled ES modules with no build step, so nothing
 * type-checks these paths before a browser runs them. `image-upload.js` is
 * import-free precisely so this file can load it in plain Node and pin the
 * decisions that are easy to get wrong and expensive to get wrong:
 *
 *   - what we refuse to upload,
 *   - what we resize to (and, importantly, what we refuse to enlarge),
 *   - whether a stored image belongs to us before we delete it.
 *
 * Run: node --test tools/test-image-upload.mjs
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import {
  ALLOWED_TYPES,
  MAX_UPLOAD_BYTES,
  validateFile,
  fitWithin,
  dimensionWarning,
  merchantCoverPath,
  menuItemPath,
  storagePathFromUrl,
  humanSize
} from '../admin_panel/image-upload.js';

const file = (type, size) => ({ type, size, name: 'photo' });

describe('validateFile', () => {
  test('accepts the three types storage.rules accepts', () => {
    for (const type of ALLOWED_TYPES) {
      assert.equal(validateFile(file(type, 1024)).ok, true, type);
    }
  });

  test('refuses anything else', () => {
    // A PDF or an SVG passed here would be refused by storage.rules anyway;
    // failing in the browser gives the admin a sentence instead of a
    // permission error after the bytes are already on the wire.
    for (const type of ['application/pdf', 'image/svg+xml', 'image/gif', '']) {
      assert.equal(validateFile(file(type, 1024)).ok, false, type);
    }
  });

  test('refuses a file over the cap, and says how far over', () => {
    const result = validateFile(file('image/jpeg', 6 * 1024 * 1024));
    assert.equal(result.ok, false);
    assert.match(result.error, /6 MB/);
    assert.match(result.error, /5 MB/);
  });

  test('the cap matches the one in storage.rules', () => {
    // If these two drift, the admin gets an opaque permission denial on an
    // upload the panel told them was fine.
    assert.equal(MAX_UPLOAD_BYTES, 5 * 1024 * 1024);
    assert.equal(validateFile(file('image/jpeg', MAX_UPLOAD_BYTES)).ok, true);
    assert.equal(validateFile(file('image/jpeg', MAX_UPLOAD_BYTES + 1)).ok, false);
  });

  test('a missing file is a message, not a crash', () => {
    assert.equal(validateFile(null).ok, false);
    assert.equal(validateFile(undefined).ok, false);
  });
});

describe('fitWithin', () => {
  test('shrinks a phone photo into the merchant cover bounds', () => {
    // 4032×3024 is a stock iPhone frame — the case this pipeline exists for.
    assert.deepEqual(fitWithin(4032, 3024, 1600, 800), { width: 1067, height: 800 });
  });

  test('keeps the aspect ratio, binding on whichever axis overflows more', () => {
    assert.deepEqual(fitWithin(3200, 800, 1600, 800), { width: 1600, height: 400 });
    assert.deepEqual(fitWithin(800, 3200, 1600, 800), { width: 200, height: 800 });
  });

  test('never upscales', () => {
    // Enlarging a small logo produces a blurry image several times the byte
    // size of the original — the opposite of what this pipeline is for.
    assert.deepEqual(fitWithin(200, 100, 1600, 800), { width: 200, height: 100 });
    assert.deepEqual(fitWithin(1600, 800, 1600, 800), { width: 1600, height: 800 });
  });

  test('honours the smaller menu-item bounds', () => {
    assert.deepEqual(fitWithin(4000, 3000, 800, 600), { width: 800, height: 600 });
  });

  test('never returns a zero dimension', () => {
    // A canvas of width 0 throws on toBlob, so clamping here is what keeps a
    // pathological image from breaking the form.
    const out = fitWithin(10000, 1, 800, 600);
    assert.ok(out.width >= 1 && out.height >= 1);
  });
});

describe('dimensionWarning', () => {
  test('is silent at or above the recommended size', () => {
    assert.equal(dimensionWarning(1600, 800, 800, 400), null);
    assert.equal(dimensionWarning(800, 400, 800, 400), null);
  });

  test('warns below it but never blocks', () => {
    // Deliberately a warning: a merchant whose only asset is a 320px logo
    // should still be able to save it. That is the admin's call.
    const warn = dimensionWarning(320, 200, 800, 400);
    assert.ok(warn && warn.includes('320×200'));
  });
});

describe('storage paths', () => {
  test('a merchant cover is timestamped, not fixed-name', () => {
    // With a fixed `cover.jpg` the CDN keeps serving the old bytes after a
    // replacement and the admin concludes the upload silently failed.
    assert.equal(merchantCoverPath('m1', 1700000000000),
      'merchants/m1/cover_1700000000000.jpg');
    assert.notEqual(merchantCoverPath('m1', 1), merchantCoverPath('m1', 2));
  });

  test('menu item images live under their merchant', () => {
    // So deleting the merchant folder takes its item images with it.
    assert.equal(menuItemPath('m1', 'i9', 1700000000000),
      'merchants/m1/menuItems/i9_1700000000000.jpg');
    assert.ok(menuItemPath('m1', 'i9', 1).startsWith('merchants/m1/'));
  });
});

describe('storagePathFromUrl', () => {
  test('extracts and decodes the object path', () => {
    const url = 'https://firebasestorage.googleapis.com/v0/b/shipeast.appspot.com/o/' +
      'merchants%2Fm1%2Fcover_1700000000000.jpg?alt=media&token=abc-123';
    assert.equal(storagePathFromUrl(url), 'merchants/m1/cover_1700000000000.jpg');
  });

  test('returns null for a URL we do not own', () => {
    // This is the guard that keeps "delete the old image on replace" from
    // throwing on every merchant seeded with a pasted third-party link. The
    // panel keeps that paste field because existing merchants depend on it.
    assert.equal(storagePathFromUrl('https://i.imgur.com/abc.jpg'), null);
    assert.equal(storagePathFromUrl('https://example.com/o/merchants%2Fm1.jpg'), null);
  });

  test('returns null rather than throwing on junk', () => {
    assert.equal(storagePathFromUrl(''), null);
    assert.equal(storagePathFromUrl(null), null);
    assert.equal(storagePathFromUrl(undefined), null);
    assert.equal(storagePathFromUrl(42), null);
    assert.equal(storagePathFromUrl(
      'https://firebasestorage.googleapis.com/v0/b/bucket/no-object-segment'), null);
    assert.equal(storagePathFromUrl(
      'https://firebasestorage.googleapis.com/v0/b/bucket/o/%E0%A4%A?alt=media'), null);
  });
});

describe('humanSize', () => {
  test('reads the way an admin would say it', () => {
    assert.equal(humanSize(6 * 1024 * 1024), '6 MB');
    assert.equal(humanSize(1.5 * 1024 * 1024), '1.5 MB');
    assert.equal(humanSize(400 * 1024), '400 KB');
    assert.equal(humanSize(10), '1 KB');
  });
});
