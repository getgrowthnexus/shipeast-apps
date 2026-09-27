#!/usr/bin/env python3
"""Lay every mirrored screen beside the Flutter screenshot of the same screen.

This is the gate that keeps the design system honest. The mirror is hand-written
CSS; the only thing stopping it drifting from the app is looking at the two
together, so this builds one contact sheet per screen and one index of the lot.

    flutter test test/preview/shot_test.dart   # in customer_app/, first
    python3 tool/build.py && node tool/shoot.mjs
    python3 tool/compare.py

Both sides are captured at 412x892 @2x, so a difference in the output is a real
difference in the design rather than an artefact of scaling.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FRAMES = HERE.parent / "shots/frames"
FLUTTER = ROOT / "customer_app/build/shots"
OUT = HERE.parent / "shots/compare"

# mirror frame -> flutter shot. A mirror page holding several frames numbers
# them, so the empty and loading faces line up against their own screenshots.
PAIRS = [
    ("screen-01-splash", "splash"),
    ("screen-02-welcome", "welcome"),
    ("screen-03-login", "login"),
    ("screen-04-register", "register"),
    ("screen-05-home", "home"),
    ("screen-06-search", "search"),
    ("screen-07-orders", "orders"),
    ("screen-08-alerts", "alerts"),
    ("screen-09-profile", "profile"),
    ("screen-10-all-merchants-1", "all-merchants"),
    ("screen-10-all-merchants-2", "all-merchants-loading"),
    ("screen-10-all-merchants-3", "all-merchants-empty"),
    ("screen-11-merchant-menu", "menu"),
    ("screen-12-cart-1", "cart"),
    ("screen-12-cart-2", "cart-empty"),
    ("screen-13-checkout", "checkout"),
    ("screen-14-payment", "payment"),
    ("screen-15-order-confirmed", "confirmed"),
    ("screen-16-track", "track"),
    ("screen-17-rate-driver", "rate"),
    ("screen-18-saved-addresses-1", "saved-addresses"),
    ("screen-18-saved-addresses-2", "saved-addresses-empty"),
    ("screen-18-saved-addresses-3", "address-sheet"),
    ("screen-19-overseas", "overseas"),
    ("screen-20-help-support", "help"),
    ("screen-21-privacy-security", "privacy"),
    ("screen-22-coming-soon", "coming-soon"),
    ("screen-23-toasts-2", "toasts"),
]

GAP, PAD, LABEL = 24, 20, 34
BG, INK = (244, 239, 241), (110, 95, 102)


def main() -> None:
    if not FLUTTER.exists():
        sys.exit(
            f"no Flutter screenshots at {FLUTTER}\n"
            "run `flutter test test/preview/shot_test.dart` in customer_app/ first"
        )
    OUT.mkdir(parents=True, exist_ok=True)

    made, missing = [], []
    for mirror_name, flutter_name in PAIRS:
        mirror = FRAMES / f"{mirror_name}.png"
        shot = FLUTTER / f"{flutter_name}.png"
        if not mirror.exists() or not shot.exists():
            missing.append(
                f"{mirror_name} ({'mirror' if not mirror.exists() else 'shot'})"
            )
            continue

        a, b = Image.open(shot).convert("RGB"), Image.open(mirror).convert("RGB")
        # The Flutter shot is the reference; scale the mirror to its height so
        # any size difference shows up as a width difference, not a squash.
        if b.height != a.height:
            b = b.resize((round(b.width * a.height / b.height), a.height), Image.LANCZOS)

        w = PAD * 2 + a.width + GAP + b.width
        h = PAD * 2 + LABEL + a.height
        sheet = Image.new("RGB", (w, h), BG)
        sheet.paste(a, (PAD, PAD + LABEL))
        sheet.paste(b, (PAD + a.width + GAP, PAD + LABEL))

        d = ImageDraw.Draw(sheet)
        d.text((PAD, PAD + 6), f"FLUTTER — {flutter_name}", fill=INK)
        d.text((PAD + a.width + GAP, PAD + 6), f"MIRROR — {mirror_name}", fill=INK)

        sheet.save(OUT / f"{flutter_name}.png")
        made.append(flutter_name)

    print(f"{len(made)} comparisons -> {OUT.relative_to(ROOT)}")
    if missing:
        print("MISSING:", ", ".join(missing), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
