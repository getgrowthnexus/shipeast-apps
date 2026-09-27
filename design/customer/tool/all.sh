#!/usr/bin/env bash
# The whole loop, in order. Run from design/customer/.
#
#   ./tool/all.sh
#
# 1. re-photograph the real app          (the reference the mirror is judged against)
# 2. re-extract the icon sprite          (in case SeIcons gained or swapped a glyph)
# 3. build the self-contained bundle     (what /design-sync uploads)
# 4. render every page                   (catches a broken card before it ships)
# 5. lay each screen beside its shot     (the only thing that catches drift)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(cd ../.. && pwd)

export PATH="$PATH:/workspaces/flutter-sdk/bin"
( cd "$ROOT/customer_app" && flutter test test/preview/shot_test.dart )

python3 tool/extract_icons.py
python3 tool/build.py

# Playwright is a local instrument rather than a dependency; find it wherever
# a previous `npx playwright` left it.
NPX_PW=$(find "$HOME/.npm/_npx" -maxdepth 3 -name playwright -type d 2>/dev/null | head -1)
NODE_PATH="${NPX_PW%/playwright}" node tool/shoot.mjs

python3 tool/compare.py
