#!/usr/bin/env python3
"""Pull the customer app's icon set out of the Flutter SDK as real SVG paths.

The app draws icons from `MaterialIcons-Regular.otf` through the `SeIcons`
facade. A design mirror that hand-picks lookalike icons would drift from the
build the first time someone swapped a glyph, so the outlines are taken from
the very font the APK ships:

    lib/theme/se_icons.dart   ->  `Icons.<material_name>`
    SDK `codepoints`          ->  material_name -> U+XXXX
    MaterialIcons-Regular.otf ->  glyph outline -> SVG path

Output is one `<symbol>` sprite keyed by the SEDS name (`SeIcons.caretRight`
becomes `#i-caretRight`), so the HTML refers to icons by the same vocabulary the
Dart does.

Material's em box is 1000 units with the baseline at y=0 and the glyph drawn
above it, while SVG's y axis runs downward from the top. The transform below is
the whole conversion: flip y, then drop the box so a 24x24 viewBox frames the
glyph the same way Flutter's `Icon(size: 24)` does.
"""

import re
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

SDK = Path("/workspaces/flutter-sdk/bin/cache/artifacts/material_fonts")
ROOT = Path(__file__).resolve().parents[3]
SE_ICONS = ROOT / "customer_app/lib/theme/se_icons.dart"
OUT = Path(__file__).resolve().parents[1] / "src/icons.svg"

# Material draws on a 1000-unit em with a 100-unit descent below the baseline.
UPM = 1000
DESCENT = 100
VIEW = 24


def se_icon_map() -> dict[str, str]:
    """`SeIcons.name` -> material icon name, straight out of the facade."""
    text = SE_ICONS.read_text()
    pairs = re.findall(
        r"static const IconData (\w+)\s*=\s*Icons\.(\w+);", text
    )
    if not pairs:
        sys.exit("no icons parsed from se_icons.dart — did the facade change?")
    return dict(pairs)


def codepoints() -> dict[str, int]:
    out = {}
    for line in (SDK / "codepoints").read_text().splitlines():
        if not line.strip():
            continue
        name, code = line.split()
        out[name] = int(code, 16)
    return out


def main() -> None:
    icons = se_icon_map()
    codes = codepoints()
    font = TTFont(SDK / "MaterialIcons-Regular.otf")
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()

    scale = VIEW / UPM
    symbols, missing = [], []

    for se_name, mat_name in sorted(icons.items()):
        # An unsuffixed `Icons.foo` is the baseline variant, and that is how the
        # codepoints table spells it — `foo_baseline`.
        code = codes.get(mat_name) or codes.get(f"{mat_name}_baseline")
        if code is None or code not in cmap:
            missing.append(f"{se_name} ({mat_name})")
            continue
        pen = SVGPathPen(glyphs)
        glyphs[cmap[code]].draw(pen)
        d = pen.getCommands()
        if not d:
            missing.append(f"{se_name} ({mat_name}) — empty outline")
            continue
        # Flip the y axis and lift the glyph off the baseline into the box.
        transform = (
            f"scale({scale:.6g} {-scale:.6g}) "
            f"translate(0 {-(UPM - DESCENT)})"
        )
        symbols.append(
            f'<symbol id="i-{se_name}" viewBox="0 0 {VIEW} {VIEW}">'
            f'<g transform="{transform}"><path d="{d}"/></g></symbol>'
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" style="display:none">\n'
        + "\n".join(symbols)
        + "\n</svg>\n"
    )
    print(f"wrote {len(symbols)} icons -> {OUT.relative_to(ROOT)}")
    if missing:
        print("MISSING:", ", ".join(missing), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
