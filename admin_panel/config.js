/* ═══════════════════════════════════════════════════════════════
   ShipEast Admin Portal — environment configuration
   Extracted from app.js (execution-all-three-plan.md P0-01).
   ═══════════════════════════════════════════════════════════════

   Why this file exists
   ────────────────────
   Phases 1–3 rewrite the shape of live data. Rehearsing those migrations
   requires pointing the panel at a staging project, and the config was
   previously hardcoded in the middle of app.js.

   How the environment is chosen
   ─────────────────────────────
   By hostname, from an explicit allowlist. Anything not on the list resolves
   to production, because that is what keeps the existing deployment working.

   That default is the dangerous direction — an unrecognised host silently
   getting production credentials is exactly the accident P0-01 exists to
   prevent — so the safety control is not the resolution logic, it is the
   banner below: any non-production environment paints a persistent bar across
   the top of the panel. An admin can always see which database they are about
   to mutate, rather than inferring it from the URL.

   Firebase API keys are public by design and safe to ship *once security rules
   exist*. They do not exist yet (audit §7.1). Until P2-01 lands, this key
   guards nothing — that is a rules problem, not a secrets problem, and moving
   the key out of the repo would not help.
*/

const CONFIGS = {
  prod: {
    apiKey:            'AIzaSyDcETjuHcvmy7TKL7vHW6sYlUk9sxa-6CA',
    authDomain:        'shipeast-1a1f6.firebaseapp.com',
    projectId:         'shipeast-1a1f6',
    storageBucket:     'shipeast-1a1f6.firebasestorage.app',
    messagingSenderId: '783428944628'
  },

  /* The local preview harness (tools/dev-up.sh). Every value here is a
     placeholder, and that is the safety property, not an oversight.

     `demo-` is a reserved prefix in the Firebase tooling: the emulator suite
     serves a `demo-*` project happily, and the SDKs refuse to fall back to
     real Google endpoints for one. So if the emulator is not running, the
     panel fails to connect — it cannot quietly find production instead, which
     is the accident this whole file exists to prevent. */
  local: {
    apiKey:            'local-emulator-unused',
    authDomain:        'localhost',
    projectId:         'demo-shipeast',
    storageBucket:     'demo-shipeast.appspot.com',
    messagingSenderId: '000000000000'
  }

  // staging: filled in by P0-01 once `shipeast-staging` exists. Generate with
  // `firebase apps:sdkconfig web` against that project and paste the block
  // here — do not hand-write it. A typo'd projectId either fails opaquely or,
  // worse, resolves to a real project that is not the intended one.
};

/** Hostname → environment. Hosts not listed resolve to `prod` (see above). */
const HOSTS = {
  'shipeast-staging.web.app':      'staging',
  'shipeast-staging.firebaseapp.com': 'staging',
  localhost:                       'local',
  '127.0.0.1':                     'local'
};

/* An explicit `?env=` overrides the hostname map.

   This exists so local development is possible before `shipeast-staging`
   exists: localhost maps to staging, which has no config yet, so the panel
   would otherwise refuse to start. `?env=prod` lets a developer opt into
   production consciously — and the banner below then shows a red warning,
   because reaching production from a dev machine is worth being loud about.

   An override is safe precisely because it is deliberate. A silent default to
   production is not, which is why the hostname map has no such fallback for
   hosts it recognises. */
function resolveEnv() {
  let override = '';
  try {
    override = new URL(location.href).searchParams.get('env') || '';
  } catch { /* no URL/location (e.g. a test harness) — fall through */ }
  if (override) return override;

  const host = (typeof location !== 'undefined' && location.hostname) || '';
  return HOSTS[host] || 'prod';
}

const requested = resolveEnv();

/** True when production was reached from a host that is not a production host. */
export const FORCED_PROD =
  requested === 'prod' && HOSTS[(typeof location !== 'undefined' && location.hostname) || ''] != null;

// Fail loudly rather than silently falling back to production. A developer who
// asked for staging and got production without noticing is the worst outcome
// this file can produce.
if (!CONFIGS[requested]) {
  const msg =
    `Admin panel: environment "${requested}" has no Firebase config in config.js. ` +
    'Refusing to start rather than defaulting to production.';
  document.addEventListener('DOMContentLoaded', function () {
    document.body.innerHTML =
      '<div style="font:15px/1.6 system-ui;padding:40px;max-width:640px;margin:0 auto;color:#b42318">' +
      '<h1 style="font-size:20px;margin:0 0 12px">Configuration error</h1><p>' + msg + '</p></div>';
  });
  throw new Error(msg);
}

export const SE_ENV = requested;
export const firebaseConfig = CONFIGS[requested];

/** Ports the emulator suite binds, mirroring the `emulators` block in the
    repo-root firebase.json. Read by app.js; exported here so there is one
    place to change them. */
export const EMULATORS = {
  auth:      9099,
  firestore: 8080,
  storage:   9199,
  functions: 5001
};

/* True only for the local preview harness. app.js redirects every SDK at the
   emulator suite when this is set — a redirect that must never be reachable
   from a deployed panel, hence keying it off SE_ENV rather than sniffing the
   hostname a second time. */
export const USE_EMULATORS = SE_ENV === 'local';

/* ── Non-production banner ──────────────────────────────────────
   Self-contained: inline styles, injected at runtime, and rendered only when
   the environment is not production. Production is visually untouched, and
   this needs no change to index.html or styles.css.                        */
if (SE_ENV !== 'prod' || FORCED_PROD) {
  const paint = function () {
    const bar = document.createElement('div');
    bar.setAttribute('role', FORCED_PROD ? 'alert' : 'status');
    bar.textContent = FORCED_PROD
      ? 'PRODUCTION — ' + firebaseConfig.projectId + ' · live customer data, from a non-production host'
      : SE_ENV.toUpperCase() + ' — ' + firebaseConfig.projectId + ' · not production data';
    bar.style.cssText = [
      'position:sticky', 'top:0', 'z-index:9999', 'padding:6px 16px',
      'background:' + (FORCED_PROD ? '#b42318' : '#b54708'), 'color:#fff',
      'text-align:center', 'font:600 12px/1.5 system-ui,sans-serif', 'letter-spacing:.04em'
    ].join(';');
    document.body.prepend(bar);
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', paint);
  } else {
    paint();
  }
  console.info(
    '[ShipEast Admin] environment:', SE_ENV, firebaseConfig.projectId,
    FORCED_PROD ? '(forced via ?env=prod)' : ''
  );
}
