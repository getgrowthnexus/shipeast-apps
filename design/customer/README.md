# ShipEast Customer — design-system mirror

An editable HTML mirror of every screen in the customer app, built to be pushed
into a [claude.ai/design](https://claude.ai/design) project so the UI can be
redesigned there and ported back into Flutter.

It exists because **Claude Design is not Figma and does not need repo access**.
A design project is a bag of HTML/CSS files; `/design-sync` uploads them through
your own claude.ai login. Nobody has to own or connect this GitHub repo.

```text
src/                 the source you edit
  se.css             every token and component, transcribed from the Dart
  icons.svg          79 glyphs, extracted from the font the APK ships
  pages/*.html       one file per card — foundations, components, screens
tool/
  all.sh             the whole loop, in order
  extract_icons.py   SeIcons -> SVG sprite, straight out of MaterialIcons-Regular.otf
  build.py           src/ -> build/, everything inlined, one self-contained file per card
  shoot.mjs          build/ -> shots/, plus shots/frames/ for the phone frames alone
  compare.py         each frame beside the Flutter screenshot of the same screen
build/               generated — this is what gets uploaded
shots/               generated — verification images
```

## The loop

```bash
cd design/customer
./tool/all.sh          # re-shoot the app, rebuild, re-render, re-compare
```

Then type `/design-sync`. It reads the pin in `.design-sync/config.json`, so it
already knows the target project and the bundle directory — it will show you the
exact set of paths it is going to write and upload only after you approve.

`/design-sync` is **user-invocable only** — Claude cannot call it for you, so
this last step is always yours.

Synced project: **ShipEast Customer** —
<https://claude.ai/design/p/4af9d86c-07c4-482f-a50a-5575b9a7693f>

Note this repo is deliberately off the converter's path: `/design-sync` ships a
compiled **React** library, and this design system is Flutter. See
`.design-sync/NOTES.md` for why, and what the trade costs.

## Why every page is self-contained

`build.py` inlines the stylesheet, the Figtree webfont and just the icons that
page uses, so a card cannot lose its styling to a serving rule we do not control.
The trade is duplication; the ceiling is 256 KB per file and the heaviest page
(welcome, which carries the courier silhouette) lands at 144 KB.

## The rule this mirror lives by

Every value in `se.css` is transcribed from the Dart that ships:

| Mirror | Source of truth |
| --- | --- |
| colour tokens | `customer_app/lib/theme/se_colors.dart` |
| type ladder | `customer_app/lib/theme/se_typography.dart` |
| space, radius, elevation | `customer_app/lib/theme/se_spacing.dart` |
| components | `customer_app/lib/widgets/se_*.dart` |
| icons | `customer_app/lib/theme/se_icons.dart` → the SDK's `MaterialIcons-Regular.otf` |

**When the mirror and the Dart disagree, the Dart is right and the mirror is a
bug.** `tool/compare.py` is what catches that: it lays each mirrored screen next
to the Flutter screenshot of the same screen, both at 412×892 @2x, so a
difference in the image is a difference in the design rather than an artefact of
scaling.

## Coverage

All 22 routes, plus the states a screen only shows when something is missing or
still loading:

- **Signed out** — splash, welcome, sign in, sign up
- **Main tabs** — home, search, orders, alerts, profile
- **Browse** — all merchants (loaded / loading / empty), merchant menu
- **Ordering** — cart (filled / empty), checkout, payment, order confirmed,
  track order, rate driver
- **Account** — saved addresses (list / empty / add sheet), shop & deliver,
  help & support, privacy & security, coming soon, toasts
- **Foundations** — colour, typography, space & radius & elevation, icons, brand
- **Components** — buttons, fields & chips, surfaces & rows, merchant listings,
  page chrome & nav, states & feedback

## Bringing changes back

A redesign done in Claude Design comes back as HTML and CSS. Port it by finding
the token or widget in the table above, changing it there, then running
`./tool/all.sh` — if the comparison sheets line up again, the app and the design
system agree.
