#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Local preview harness — all three apps, one fake backend, no APK.
#
# Starts:
#   4000  Firebase Emulator UI      (inspect/edit the fake database)
#   5100  customer_app  (Flutter web, debug)
#   5200  driver_app    (Flutter web, debug)
#   5300  admin_panel   (static, served as-is)
#   8080/9099/9199/5001  firestore / auth / storage / functions emulators
#
# ## Why localhost and not the Codespaces public URL
#
# connectFirestoreEmulator() in the Firebase SDK hardcodes plain HTTP — there
# is no ssl option. Codespaces' *.app.github.dev URLs are HTTPS-only on 443, so
# a browser tab opened there loads the app fine and then cannot reach the
# database at all. Open the codespace in the VS Code desktop app instead: it
# forwards these ports to real localhost, everything speaks http, and it works.
#
# ## What this preview does NOT show
#
# Push notifications (FCM on web needs a service worker and a VAPID key this
# project has never registered — main.dart skips it on web), camera capture
# (image_picker falls back to a file dialog), Android keyboard insets, and the
# system back button. It is a faithful check of layout, copy, flow and every
# Firestore read and write. It is not a check of how the app feels on a phone.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/workspaces/flutter-sdk/bin:$PATH"
PROJECT="demo-shipeast"
LOGS="$ROOT/.dev-logs"
mkdir -p "$LOGS"

if ! command -v flutter >/dev/null; then
  echo "flutter not on PATH. Expected the SDK at /workspaces/flutter-sdk." >&2
  exit 1
fi
if [ ! -d "$ROOT/tools/node_modules" ]; then
  echo "▸ Installing tool dependencies (first run only)"
  ( cd "$ROOT/tools" && npm install --silent )
fi

# Kill the whole process group on exit, so Ctrl-C does not leave four
# orphaned servers holding the ports for the next run.
pids=()
cleanup() {
  echo ""
  echo "Stopping…"
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait_for() { # port, label, timeout-seconds
  local port=$1 label=$2 limit=${3:-120} n=0
  until curl -sf -o /dev/null "http://localhost:$port" 2>/dev/null; do
    n=$((n + 1))
    if [ "$n" -ge "$((limit * 2))" ]; then
      echo "  $label did not come up on :$port — see $LOGS" >&2
      return 1
    fi
    sleep 0.5
  done
  echo "  $label ready on :$port"
}

echo "▸ Firebase emulators (project $PROJECT)"
firebase emulators:start --project "$PROJECT" --only auth,firestore,storage,functions \
  >"$LOGS/emulators.log" 2>&1 &
pids+=($!)
wait_for 4000 "emulator UI" 180

echo "▸ Seeding"
FIRESTORE_EMULATOR_HOST=localhost:8080 \
FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
GCLOUD_PROJECT="$PROJECT" \
  node "$ROOT/tools/seed_emulator.mjs" \
  || { echo "  seeding failed — see above" >&2; exit 1; }

echo "▸ Admin panel"
# Pinned in tools/package.json and invoked from node_modules rather than via
# `npx --yes`, which downloads on first run — a download that is both a silent
# network dependency and slow enough to trip the readiness check below.
"$ROOT/tools/node_modules/.bin/http-server" "$ROOT/admin_panel" \
  -p 5300 -c-1 --silent >"$LOGS/admin.log" 2>&1 &
pids+=($!)

# --dart-define is what switches dev/dev_emulators.dart on. Without it the web
# build refuses to start at all (firebase_options.dart throws), which is the
# interlock that stops a web build ever reaching production.
DEFINES=(--dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=localhost)

echo "▸ customer_app (first build takes a few minutes)"
( cd "$ROOT/customer_app" && flutter run -d web-server \
    --web-hostname 0.0.0.0 --web-port 5100 "${DEFINES[@]}" ) \
  >"$LOGS/customer.log" 2>&1 &
pids+=($!)

echo "▸ driver_app"
( cd "$ROOT/driver_app" && flutter run -d web-server \
    --web-hostname 0.0.0.0 --web-port 5200 "${DEFINES[@]}" ) \
  >"$LOGS/driver.log" 2>&1 &
pids+=($!)

wait_for 5300 "admin panel" 30
wait_for 5100 "customer app" 600
wait_for 5200 "driver app" 600

cat <<EOF

  ─────────────────────────────────────────────────
   Customer      http://localhost:5100
   Driver        http://localhost:5200
   Admin panel   http://localhost:5300
   Database UI   http://localhost:4000
  ─────────────────────────────────────────────────

   admin@shipeast.test  / shipeast123   (admin panel)
   marcia@example.com   / shipeast123   (customer)
   delroy@example.com   / shipeast123   (driver, approved)
   anita@example.com    / shipeast123   (driver, pending)

   Logs in .dev-logs/. Ctrl-C stops everything.
   Data is in-memory — it resets every time this script runs.

EOF

wait
