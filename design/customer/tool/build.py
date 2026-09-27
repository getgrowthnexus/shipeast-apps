#!/usr/bin/env python3
"""Assemble the Claude Design bundle from the sources in `src/`.

Every page is emitted as ONE self-contained HTML file: stylesheet, icon sprite
and the Figtree webfont are all inlined. That is deliberate. A design project is
a bag of files whose serving rules are not ours to assume, and a card that
silently loses its stylesheet looks like a design bug rather than a plumbing
one. Figtree is 20 KB and the sprite 37 KB, so a page lands near 90 KB — well
inside the 256 KB per-file ceiling `DesignSync` enforces.

    python3 tool/build.py            # -> build/

Each fragment in `src/pages/` starts with an HTML comment holding its card
metadata, which becomes the `@dsCard` marker the Design System pane groups on:

    <!-- card: Home | group: Screens | desc: The signed-in landing screen -->
"""

import base64
import io
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = Path(__file__).resolve().parents[1] / "src"
OUT = Path(__file__).resolve().parents[1] / "build"
FONT = ROOT / "admin_panel/assets/fonts/figtree-latin.woff2"
RIDER = ROOT / "customer_app/assets/brand/rider.png"

CARD_RE = re.compile(
    r"<!--\s*card:\s*(?P<name>[^|]+?)\s*\|\s*group:\s*(?P<group>[^|]+?)\s*"
    r"(?:\|\s*desc:\s*(?P<desc>.+?)\s*)?-->",
    re.S,
)

DOC = """<!-- @dsCard group="{group}" -->
<title>{name} — ShipEast Customer</title>
<style>
{css}
</style>
{sprite}
{body}
"""


def font_face() -> str:
    """Figtree, inlined. One variable face covering 300-900 — the app ships the
    same file, so the weight ladder renders at the weights it was designed at
    rather than at whatever the browser can synthesise."""
    b64 = base64.b64encode(FONT.read_bytes()).decode()
    return (
        "@font-face{font-family:'Figtree';font-style:normal;"
        "font-weight:300 900;font-display:block;"
        f"src:url(data:font/woff2;base64,{b64}) format('woff2');}}"
    )


def rider_mask() -> str:
    """The welcome screen's rider, as an ALPHA MASK rather than an image.

    The source art is a flat white silhouette on transparency, so the colour
    channels carry no information at all — only the alpha does. Flattening RGB
    to a constant takes a 147 KB PNG down to ~56 KB of lossless WebP, and the
    page paints it with `mask-image` over a solid fill, which means the
    silhouette recolours from a token instead of being repainted.

    The silhouette has to stay in the ALPHA channel, not become a grayscale
    image: `mask-mode: match-source` reads a raster mask's alpha, so a
    fully-opaque grey image masks nothing and paints a solid rectangle.
    """
    from PIL import Image  # local: only the build needs Pillow

    src = Image.open(RIDER)
    w, h = src.size
    width = 700  # the welcome screen never paints it wider than ~520 CSS px
    mask = Image.merge(
        "RGBA", (Image.new("L", (w, h), 255),) * 3 + (src.getchannel("A"),)
    ).resize((width, round(h * width / w)), Image.LANCZOS)
    buf = io.BytesIO()
    mask.save(buf, "WEBP", lossless=True, quality=100)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode()


def subset_sprite(sprite: str, body: str) -> str:
    """Keep only the symbols a page actually references.

    The full sprite is 79 glyphs and 37 KB. Most pages use a handful, and every
    page carries its own copy of everything, so shipping the whole set on each
    one is what would push a screen with a photograph over the 256 KB ceiling.
    """
    used = set(re.findall(r'href="#(i-\w+)"', body))
    symbols = [
        s for s in re.findall(r"<symbol .*?</symbol>", sprite, re.S)
        if (m := re.search(r'id="([^"]+)"', s)) and m.group(1) in used
    ]
    if not symbols:
        return ""
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" style="display:none">'
        + "".join(symbols)
        + "</svg>"
    )


def main() -> None:
    css = (SRC / "se.css").read_text().replace("/* @font-face-inject */", font_face())
    sprite = (SRC / "icons.svg").read_text().strip()
    assets = {"{{asset:rider}}": rider_mask()}

    pages = sorted((SRC / "pages").glob("*.html"))
    if not pages:
        sys.exit("no pages in src/pages/")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    # `styles.css` at the bundle root is the contract with the design agent:
    # a rendered design receives only this file's transitive @import closure, so
    # the whole token system has to be reachable from here. There are no
    # @imports — it is one file — and the font is inlined, so the closure is
    # exactly this.
    (OUT / "styles.css").write_text(css)

    # The sentinel fences the Design app's manifest build against a half-applied
    # upload: it is written first, then re-written last, and the app rebuilds its
    # card index from the `@dsCard` markers when it sees the file change.
    (OUT / "_ds_needs_recompile").write_text("1\n")

    index = []
    for page in pages:
        raw = page.read_text()
        m = CARD_RE.search(raw)
        if not m:
            sys.exit(f"{page.name}: missing `<!-- card: … | group: … -->` header")
        body = CARD_RE.sub("", raw, count=1).strip()
        for token, uri in assets.items():
            body = body.replace(token, uri)
        name = m.group("name")
        group = m.group("group")
        doc = DOC.format(
            group=group, name=name, css=css,
            sprite=subset_sprite(sprite, body), body=body,
        )
        (OUT / page.name).write_text(doc)
        index.append((group, name, page.name, len(doc)))

    # The README is what the design agent reads before it builds anything: the
    # hand-written conventions header, then a generated index of what shipped.
    header = ROOT / ".design-sync/conventions.md"
    body = ["\n## Cards in this project\n"]
    for group in dict.fromkeys(g for g, *_ in index):
        body.append(f"\n### {group}\n")
        for g, name, fname, _ in index:
            if g == group:
                body.append(f"- **{name}** — `{fname}`")
    (OUT / "README.md").write_text(
        (header.read_text() if header.exists() else "") + "\n".join(body) + "\n"
    )

    biggest = max(index, key=lambda r: r[3])
    print(f"built {len(index)} pages -> {OUT}")
    print(f"largest: {biggest[2]} at {biggest[3] / 1024:.0f} KB (ceiling 256 KB)")
    if biggest[3] > 256 * 1024:
        sys.exit("a page exceeded the 256 KB per-file ceiling")

    for group in dict.fromkeys(g for g, *_ in index):
        names = [n for g, n, *_ in index if g == group]
        print(f"  {group}: {len(names)}")


if __name__ == "__main__":
    main()
