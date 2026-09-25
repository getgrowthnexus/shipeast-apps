/* ═══════════════════════════════════════════════════════════════
   Image upload — dropzone, client-side compression, validation.
   P4-01 / P4-02.

   This module deliberately imports NOTHING. It touches `document` only from
   inside functions that are called in the browser, and the Firebase Storage
   calls are injected by the caller (`opts.upload` / `opts.removeObject`).

   Two reasons for that shape:
     1. `app.js` imports Firebase from a gstatic URL, which Node cannot
        resolve. Keeping this file import-free means the pure logic below —
        the validation, the resize arithmetic, the download-URL parsing — can
        be unit-tested by `tools/test-image-upload.mjs` with no browser and
        no network. This panel has no build step; tests are the only gate.
     2. The same component serves merchants and menu items, which write to
        different collections. Injecting the writes keeps one component
        instead of two near-copies.
   ═══════════════════════════════════════════════════════════════ */

/** Storage rules (storage.rules) enforce the same list. */
export var ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

/** Matches the cap in storage.rules. Client-side checking is a courtesy —
    the rule is the control. Both exist so the admin gets a useful message
    instead of an opaque permission error after a 6 MB upload. */
export var MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

export function humanSize(bytes) {
  var mb = bytes / (1024 * 1024);
  if (mb >= 1) return (Math.round(mb * 10) / 10) + ' MB';
  return Math.max(1, Math.round(bytes / 1024)) + ' KB';
}

/**
 * Gate a file before any work is done on it.
 *
 * Checked before compression, not after: decoding a 40 MB TIFF to find out it
 * is not a JPEG costs the admin a frozen tab.
 */
export function validateFile(file, opts) {
  opts = opts || {};
  var maxBytes = opts.maxBytes || MAX_UPLOAD_BYTES;
  if (!file) return { ok: false, error: 'No file selected.' };
  if (ALLOWED_TYPES.indexOf(file.type) === -1) {
    return { ok: false, error: 'Only JPEG, PNG and WebP images can be uploaded.' };
  }
  if (file.size > maxBytes) {
    return {
      ok: false,
      error: 'That image is ' + humanSize(file.size) + '. The limit is ' +
             humanSize(maxBytes) + ' — try a smaller one.'
    };
  }
  return { ok: true };
}

/**
 * Largest size fitting inside maxW×maxH with the aspect ratio kept.
 *
 * Never upscales. Enlarging a 200px logo to 1600px produces a blurry image
 * several times the byte size of the original, which is the opposite of what
 * this pipeline is for.
 */
export function fitWithin(width, height, maxW, maxH) {
  var w = Math.max(1, Math.round(Number(width) || 0));
  var h = Math.max(1, Math.round(Number(height) || 0));
  if (w <= maxW && h <= maxH) return { width: w, height: h };
  var scale = Math.min(maxW / w, maxH / h);
  return {
    width: Math.max(1, Math.round(w * scale)),
    height: Math.max(1, Math.round(h * scale))
  };
}

/**
 * A warning, not a rejection.
 *
 * A merchant with only a small logo should still be able to save it; a
 * stretched 320px image on the customer home screen is the admin's call to
 * make, not ours to block.
 */
export function dimensionWarning(width, height, minW, minH) {
  if (width >= minW && height >= minH) return null;
  return 'This image is ' + width + '×' + height + '. Below ' + minW + '×' +
         minH + ' it will look soft on the customer app.';
}

/**
 * Storage object path for a merchant cover.
 *
 * Timestamped, never a fixed name. With `cover.jpg` the CDN keeps serving the
 * old bytes after a replacement and the admin concludes the upload failed;
 * a cache-busting query string is a worse fix than simply not reusing paths.
 */
export function merchantCoverPath(merchantId, now) {
  return 'merchants/' + merchantId + '/cover_' + (now || Date.now()) + '.jpg';
}

/** Menu item images live under the merchant that owns them, so deleting a
    merchant's folder takes its item images with it. */
export function menuItemPath(merchantId, itemId, now) {
  return 'merchants/' + merchantId + '/menuItems/' + itemId + '_' +
         (now || Date.now()) + '.jpg';
}

/**
 * Object path inside a Firebase Storage download URL, or null.
 *
 * Used to decide whether a replaced or deleted image is one of OURS before
 * calling deleteObject on it. The URL-paste field has been removed (uploads
 * only), but merchants seeded earlier with a pasted third-party link still
 * carry one in their data — those must be left alone, since attempting to
 * delete a URL we do not own would throw on every save.
 */
export function storagePathFromUrl(url) {
  if (typeof url !== 'string' || url.indexOf('firebasestorage.googleapis.com') === -1) {
    return null;
  }
  var m = /\/o\/([^?]+)/.exec(url);
  if (!m) return null;
  try {
    return decodeURIComponent(m[1]);
  } catch {
    return null;
  }
}

/**
 * Re-encode to a bounded JPEG before upload.
 *
 * This is the difference between a working feature and a slow one. Merchant
 * photos come off phone cameras at 4–8 MB and 4000px wide; unprocessed, the
 * customer home screen loads a dozen of them over Jamaican mobile data.
 *
 * Browser-only: uses Image, canvas and URL.createObjectURL.
 */
export function compressImage(file, opts) {
  opts = opts || {};
  var maxW = opts.maxW || 1600, maxH = opts.maxH || 800;
  var quality = opts.quality || 0.82;
  return new Promise(function (resolve, reject) {
    var objectUrl = URL.createObjectURL(file);
    var img = new Image();
    img.onload = function () {
      URL.revokeObjectURL(objectUrl);
      var natural = { width: img.naturalWidth, height: img.naturalHeight };
      var dim = fitWithin(natural.width, natural.height, maxW, maxH);
      var canvas = document.createElement('canvas');
      canvas.width = dim.width;
      canvas.height = dim.height;
      var ctx = canvas.getContext('2d');
      // A transparent PNG re-encoded as JPEG renders its alpha as black
      // without this matte. White matches the card background it sits on.
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, dim.width, dim.height);
      ctx.drawImage(img, 0, 0, dim.width, dim.height);
      canvas.toBlob(function (blob) {
        if (!blob) { reject(new Error('This image could not be processed.')); return; }
        resolve({ blob: blob, width: dim.width, height: dim.height, natural: natural });
      }, 'image/jpeg', quality);
    };
    img.onerror = function () {
      URL.revokeObjectURL(objectUrl);
      reject(new Error('That file is not a readable image.'));
    };
    img.src = objectUrl;
  });
}

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

var uploaderSeq = 0;

/**
 * Dropzone with preview, progress and Replace/Remove.
 *
 * Accessibility: the click target is a real <input type="file"> inside its
 * <label>, not a <div> with a click handler, so it is keyboard-operable and
 * announced correctly with no ARIA needed to fake it. Progress is announced
 * through an aria-live region — an admin who cannot see the bar still learns
 * the upload finished.
 *
 * opts:
 *   inputId       id of the file input (label `for` targets it)
 *   maxW/maxH     compression bounds
 *   minW/minH     below this, warn (never block)
 *   hint          text under the title
 *   pathFor()     → storage path for a new object, called at upload time
 *   upload(blob, path, onProgress) → Promise<downloadURL>
 *   removeObject(url) → Promise<void>   (may reject; failures are non-fatal)
 *   onChange(url) called whenever the stored URL changes
 *   toast(type,msg,title)
 *
 * Returns { el, setValue, getValue, setEnabled, reset }.
 */
export function createUploader(opts) {
  opts = opts || {};
  var uid = 'up' + (++uploaderSeq);
  var inputId = opts.inputId || (uid + '-file');
  var value = '';
  var enabled = opts.enabled !== false;
  var busy = false;

  var el = document.createElement('div');
  el.className = 'up';
  el.innerHTML =
    '<div class="up-zone" id="' + uid + '-zone">' +
      '<label class="up-drop" for="' + inputId + '">' +
        '<span class="up-drop-title">' + esc(opts.title || 'Drop an image here') + '</span>' +
        '<span class="up-drop-hint">' + esc(opts.hint || 'or click to browse · JPEG, PNG or WebP · max 5 MB') + '</span>' +
      '</label>' +
      '<input class="up-input" type="file" id="' + inputId + '" accept="' + ALLOWED_TYPES.join(',') + '"/>' +
    '</div>' +
    '<div class="up-preview" id="' + uid + '-preview" hidden>' +
      '<img class="up-thumb" id="' + uid + '-thumb" alt="Uploaded image preview"/>' +
      '<div class="up-meta"><div class="up-name" id="' + uid + '-name"></div>' +
        '<div class="up-sub" id="' + uid + '-sub"></div></div>' +
      '<div class="up-actions">' +
        '<button type="button" class="btn btn-outline btn-sm" id="' + uid + '-replace">Replace</button>' +
        '<button type="button" class="btn btn-outline btn-sm up-danger" id="' + uid + '-remove">Remove</button>' +
      '</div>' +
    '</div>' +
    '<div class="up-progress" id="' + uid + '-prog" hidden>' +
      '<div class="up-bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0" ' +
        'aria-label="Upload progress"><div class="up-bar-fill" id="' + uid + '-fill"></div></div>' +
    '</div>' +
    '<div class="up-status" id="' + uid + '-status" role="status" aria-live="polite"></div>';

  function q(suffix) { return el.querySelector('#' + uid + '-' + suffix); }
  var input = el.querySelector('input.up-input');
  var zone = q('zone'), preview = q('preview'), thumb = q('thumb');
  var nameEl = q('name'), subEl = q('sub'), prog = q('prog'), fill = q('fill');
  var bar = el.querySelector('.up-bar'), statusEl = q('status');

  function say(msg) { statusEl.textContent = msg || ''; }

  function paint() {
    var has = !!value;
    preview.hidden = !has;
    zone.hidden = has;
    if (has) {
      thumb.src = value;
    } else {
      /* Half of the "form shows the last restaurant's photo" bug. The other
         half was CSS (`.up-preview{display:flex}` outranked the UA's
         `[hidden]{display:none}` — fixed in styles.css), but even hidden
         correctly, leaving the old src on the <img> meant the component still
         held the previous merchant's image and would flash it the instant
         anything made the preview visible again. A cleared uploader must hold
         no bytes at all.

         removeAttribute, not src=''. An empty src resolves against the document
         URL, so the browser re-requests the PAGE as an image, fails, and paints
         the broken-image glyph — which is precisely the broken thumbnail that
         appeared under "Add Menu Item", where a freshly built uploader had no
         value to begin with. */
      thumb.removeAttribute('src');
    }
    el.classList.toggle('up-disabled', !enabled || busy);
    input.disabled = !enabled || busy;
  }

  function setValue(url, meta) {
    value = url || '';
    if (nameEl) nameEl.textContent = meta && meta.name ? meta.name : (value ? 'Current image' : '');
    if (subEl) subEl.textContent = meta && meta.sub ? meta.sub : '';
    paint();
  }

  function progress(pct) {
    prog.hidden = false;
    fill.style.width = pct + '%';
    bar.setAttribute('aria-valuenow', String(pct));
  }

  function fail(msg) {
    busy = false;
    prog.hidden = true;
    paint();
    say(msg);
    if (opts.toast) opts.toast('error', msg, 'Upload failed');
  }

  function handle(file) {
    if (!enabled || busy) return;
    var check = validateFile(file);
    if (!check.ok) {
      say(check.error);
      if (opts.toast) opts.toast('warning', check.error);
      return;
    }
    busy = true;
    paint();
    say('Processing image…');
    progress(0);

    compressImage(file, { maxW: opts.maxW, maxH: opts.maxH, quality: opts.quality })
      .then(function (out) {
        var warn = dimensionWarning(out.natural.width, out.natural.height,
                                    opts.minW || 0, opts.minH || 0);
        if (warn && opts.toast) opts.toast('warning', warn);
        var path;
        try {
          path = opts.pathFor();
        } catch (e) {
          throw new Error(e.message || 'Nowhere to upload this to yet.');
        }
        if (!path) throw new Error('Nowhere to upload this to yet.');
        say('Uploading…');
        var previous = value;
        return opts.upload(out.blob, path, progress).then(function (url) {
          busy = false;
          prog.hidden = true;
          setValue(url, {
            name: file.name,
            sub: out.width + '×' + out.height + ' · ' + humanSize(out.blob.size)
          });
          say('Upload complete.');
          if (opts.onChange) opts.onChange(url);
          // Best-effort: an orphaned object costs pennies, a failed save
          // costs the admin their work. Never let cleanup break the flow.
          if (previous && previous !== url && opts.removeObject) {
            Promise.resolve(opts.removeObject(previous)).catch(function () {});
          }
        });
      })
      .catch(function (e) { fail(e.message || 'Upload failed.'); });
  }

  input.addEventListener('change', function () {
    if (input.files && input.files[0]) handle(input.files[0]);
    input.value = '';
  });

  ['dragenter', 'dragover'].forEach(function (evt) {
    zone.addEventListener(evt, function (e) {
      e.preventDefault();
      if (enabled && !busy) zone.classList.add('up-over');
    });
  });
  ['dragleave', 'drop'].forEach(function (evt) {
    zone.addEventListener(evt, function (e) {
      e.preventDefault();
      zone.classList.remove('up-over');
    });
  });
  zone.addEventListener('drop', function (e) {
    var files = e.dataTransfer && e.dataTransfer.files;
    if (files && files[0]) handle(files[0]);
  });

  q('replace').addEventListener('click', function () { input.click(); });
  q('remove').addEventListener('click', function () {
    var removed = value;
    setValue('');
    say('Image removed. Save to apply.');
    if (opts.onChange) opts.onChange('');
    if (removed && opts.removeObject) {
      Promise.resolve(opts.removeObject(removed)).catch(function () {});
    }
  });

  paint();

  return {
    el: el,
    getValue: function () { return value; },
    setValue: setValue,
    setEnabled: function (on) { enabled = !!on; paint(); },
    reset: function () { setValue(''); say(''); prog.hidden = true; }
  };
}
