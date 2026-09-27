# design-sync notes — ShipEast

## Why this repo does not use the converter

`/design-sync`'s converter ships a customer's compiled **React** `dist/` so the
design agent can build with their real components. This repo has no React, no
Storybook and no component package:

- `customer_app/` — Flutter (Dart). The design system proper: `lib/theme/se_*.dart`
  and `lib/widgets/se_*.dart`.
- `admin_panel/` — vanilla ES modules + hand-written CSS, no build step.
- `driver_app/` — Flutter.
- `dist/` at repo root is **release APKs**, not a JS build.

So the bundle is produced by `design/customer/tool/build.py` instead: a
self-contained HTML card per screen/component/token page, plus `styles.css`
carrying the real token system. The design agent gets the vocabulary and the
visual truth, but not typed components to compose — that is the accepted
trade, taken deliberately rather than by building a third parallel copy of the
design system in React.

## Verification

`design/customer/tool/compare.py` lays every mirrored screen beside the Flutter
screenshot of the same screen (both 412x892 @2x). Median drift at last sync was
6.8/255, under 10 on 23 of 28 screens. Re-run the whole loop with
`cd design/customer && ./tool/all.sh`.

## Gotchas found while building this

- `FakeViewPadding` in `customer_app/test/preview/harness.dart` takes **physical**
  pixels. Passing logical values gave every screenshot a 19dp status bar instead
  of 38. Fixed; do not "simplify" it back.
- CSS `mask-image` reads a raster mask's **alpha**, not its luminance. The
  welcome screen's courier must keep the silhouette in the alpha channel or it
  paints a solid rectangle.
- Repeating a data URI for the `-webkit-mask-image` prefix doubles page weight
  and blew the 256 KB ceiling. It is emitted once, onto a `--rider` custom
  property.
- Do not run `dart format` on `customer_app/test/preview/previews.dart` — the
  file predates the current tall-style formatter and reformatting it produces a
  ~1300-line diff that buries real changes.
