# ShipEast Customer — how to build with this design system

**What this is.** The shipping app is **Flutter**, not React. This project is a
faithful HTML/CSS mirror of it, so there is no component bundle to import and no
props API. You build screens by writing HTML with the classes below, all of
which are defined in `styles.css`. Read `styles.css` before styling anything —
it is the whole system, ~700 lines, and it is authoritative.

## Setup

No provider, no wrapper, no JS. Link `styles.css` and you have the system.

Every screen lives inside a **phone frame** and is built from exactly two
surfaces — this is not decoration, it is the app's one structural rule:

```html
<div class="phone">
  <div class="cap has-back">        <!-- flat brand red. never scrolls -->
    <div class="cap-btn"><svg class="i"><use href="#i-arrowLeft"/></svg></div>
    <div class="cap-row">
      <div>
        <div class="cap-title">Saved addresses</div>
        <div class="cap-sub">3 addresses saved</div>
      </div>
    </div>
  </div>
  <div class="sheet">               <!-- blush card lifted over the red -->
    <div class="sheet-body pad">…the task…</div>
    <div class="bottom-bar"><button class="btn btn--primary">Save</button></div>
  </div>
</div>
```

`.phone` is 412×892. Add `has-back` to `.cap` when there is a back button,
`has-bottom` when the cap carries a search field or tabs. Omit `.pad` on
`.sheet-body` when a child needs to bleed to the edge.

Icons are an inline SVG sprite: `<svg class="i"><use href="#i-NAME"/></svg>`.
79 glyphs, all listed on the **Icons** card.

## The styling idiom

**CSS custom properties for values, semantic classes for parts.** There is no
utility system — do not write `p-4`, `text-sm` or `bg-red-500`, none of them
exist. Layout glue uses the small helper set at the bottom of `styles.css`
(`.hstack`, `.stack`, `.grow`, `.pad`, `.ell`, `.g12`, `.mt16`…).

### Colour — the one rule that governs everything

A **two-tier red**. Get this wrong and the whole thing looks off-brand:

| Token | Use |
| --- | --- |
| `--brand` `#F72B54` | **Identity.** Large fills, icon plates, accents, focus rings. **Never** carries small white text |
| `--brand-action` `#E30D3B` | **Action.** Buttons, links, active states. The only red allowed under white labels |
| `--shell` `#B00D33` | **Surface.** The cap, splash, auth hero. Warm white sits on it |
| `--shell-ink` / `--shell-mark` | Text and accent text **on** `--shell` |
| `--brand-ink` `#B60C31` | Red text sitting on a red tint |

Surfaces are **blush, never white**: `--surface-50` (the sheet's ground),
`--surface-0` (cards), `--surface-raised` (white — only a focused field or a
pill on the cap), `--field` (the well you type into). Text runs `--ink-900`
through `--ink-100`. Semantic: `--success`, `--warning`, `--danger`, `--info`,
each with a `-tint`, `-ink` and `-soft` variant. `--danger` is a deep maroon on
purpose — a destructive action must not look like the primary one. `--star` is
the only gold, and it is for ratings only.

**There are no gradients in this brand.** Depth is rose-black shadow
(`--e1`…`--e4`, `--glow`) plus hairline rings. Never add a sheen.

### Type — one face, hierarchy by weight

Figtree only. `.t-display` `.t-h1` `.t-h2` `.t-h3` `.t-section` `.t-title`
`.t-body` `.t-bodyS` `.t-label` `.t-eyebrow`. The ladder is 800 display / 700
card + section titles / 600 all emphasis below that / 400 body. Add `.tnum` to
anything that counts or costs.

### Space and radius

4pt grid: `--x1`…`--x16`, `--gutter` (20px, every screen edge). Radius
`--r-xs` 8 · `--r-sm` 12 · `--r-md` 16 · `--r-lg` 22 · `--r-xl` 28 ·
`--r-full`. **Buttons are pills.**

### The parts

`.btn` with `.btn--primary` `.btn--secondary` `.btn--ghost` `.btn--destructive`,
sized `.btn--md` `.btn--sm`, `.btn--auto` for intrinsic width. **One filled pill
per screen — every other affordance is words.**

`.panel` (flat card, hairline, never a shadow) · `.row-group` + `.row` (related
rows as ONE surface) · `.section-title` · `.money` / `.money--strong` ·
`.notice` (+`--warning` `--danger` `--success`) · `.stat` · `.field` (+`--focus`
`--error` `--multi` `--disabled`) · `.chip` · `.cat` · `.mcard` (browse) ·
`.mrow-card` (scan) · `.menu-item` · `.qty` · `.empty` · `.skel`+`.shimmer` ·
`.toast` · `.spine` · `.navbar` · `.modal`+`.scrim`.

Cards in the sheet are **flat and hairlined**. The sheet is already a lifted
surface; stacking shadows on it is what made the old screens look like a pile of
receipts.

## Where the truth lives

- `styles.css` — every token and part. Read it first.
- The **Foundations** cards — colour, typography, space/radius/elevation, icons,
  brand — carry the reasoning and the contrast ratios.
- The **Components** cards — each shows every state with a spec table.
- The **Screens** cards — all 22 routes, plus their loading, empty and sheet
  faces. Copy from the nearest one rather than starting blank.

## A worked example

```html
<div class="panel">
  <div class="hstack g12">
    <div class="plate"><svg class="i"><use href="#i-plane"/></svg></div>
    <div class="grow">
      <div class="t-title">Send to family back home</div>
      <div class="t-bodyS mt2">We shop in Jamaica and deliver to them.</div>
    </div>
    <svg class="i ink-300" style="width:20px;height:20px">
      <use href="#i-caretRight"/></svg>
  </div>
</div>
```

## Copy rules that are easy to get wrong

- The "overseas" flow is **local shop-and-deliver**: someone abroad pays, we buy
  in Jamaica and deliver to their family here. Nothing is shipped, nothing
  crosses a border. Never write shipping language into it.
- Money is whole Jamaican dollars, integer. Never a float, never cents.
- A status names the actual state ("Order Picked Up"), never the coarse bucket
  and never the raw database value.
