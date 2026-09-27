# The Portable App Design System

**A complete, brand-agnostic mobile design system, extracted from a shipped Flutter product.**

Give this file a primary colour and it produces a full app: ~70 colour tokens, a
type ladder, a motion system, and 20 components — all of which agree with each
other, because all of them are derived from the same three or four numbers.

This is not a mood board and not a list of preferences. Every number in here is
in production, and most of them are here because the obvious alternative was
tried first and looked wrong. Where that is true, the reason is written down —
**the reason is the important part**, because it is what lets you apply the rule
correctly in a situation this document did not anticipate.

- **To build a new app:** don't read this first. Open `PROMPT.md`, fill in the
  brief, and hand both files to Claude. This file is the reference Claude works
  from.
- **To understand or amend the system:** read this top to bottom. §9 is the
  highest-value section.

---

## 0. The five ideas

Everything below is downstream of these. If you remember nothing else:

1. **One hue, everywhere.** Surfaces are not white and text is not grey — both
   are the brand hue at 3–12% saturation. The brand colour then belongs to the
   same family as the thing it sits on, instead of floating on a white sheet.
   This single decision is most of why the result looks designed.

2. **Three tiers of the brand, and they are not interchangeable.** The
   *identity* tone is the loud one and never carries small white text. The
   *action* tone is one step darker and is the only one that does. The *shell*
   is deeper still and paints large permanent surfaces under warm-white text.
   Using the wrong tier is the most common way to break this system.

3. **Flat. No gradients, ever.** Depth is hairlines and layered
   tinted shadows. A gradient fill is the single loudest "this was generated"
   tell in modern UI, and removing it was the biggest quality jump this system
   ever made.

4. **One typeface, and hierarchy comes from the weight ladder.** Two families —
   a display face and a UI face — put a visible seam through every screen: two
   different ideas of what a letter is, read as two products glued together.

5. **Two surfaces per screen.** A flat brand **cap** says where you are; a
   tinted **sheet** lifted over it holds the task. The cap never scrolls, the
   sheet always does. Every screen. This is what makes an app read as software
   rather than as a pile of separately-designed pages.

---

## 1. Inputs

The whole system needs one required input.

| Input | Required | What it does |
|---|---|---|
| `PRIMARY` | **yes** | A hex colour. Becomes the identity tone and seeds the ramp, the neutrals, the shadows, the dark theme, and the accents. |
| `SECONDARY` | no | A hex colour. Takes over the informational role, the second category hue, and chart series 2. Defaults to the blue in §2.7. |
| `APP_NAME` | yes | Used in the wordmark and the strapline lockup. |
| `WORDMARK_SPLIT` | no | If the name is two words joined (`ShipEast`, `PayFast`), the second half renders in the accent tone. Omit for single words. |

Everything else in this document is computed. Do not invent extra colours.

---

## 2. Palette derivation

Work in HSL. Convert `PRIMARY` to `H`, `S`, `L` once; every token below is an
offset from those three numbers, so the palette is reproducible and any change
to `PRIMARY` moves the whole system together.

> **This section is executable.** `derive_palette.py` in this folder is the
> reference implementation — it emits the full table with measured contrast, or
> a ready-to-paste `ds_colors.dart`. Run it rather than doing this by hand:
>
> ```
> ./derive_palette.py "#F72B54"                 # table + gates
> ./derive_palette.py "#F72B54" --dart          # ds_colors.dart
> ```
>
> If the script and this prose ever disagree, **the script is right** — it
> measures contrast where the prose only asserts it.

### 2.1 Normalise first

```
H, S, L = hsl(PRIMARY)
```

Route on lightness. The input is not always usable as the identity tone:

| Input | What it becomes | Why |
|---|---|---|
| `L < 42%` | The input is already dark enough to be the **action** tone. Compute the ramp from `Li = L + 10`, giving plates and accents something brighter to use. | A dark forest green cannot also be the tone you paint a 58dp icon plate with. |
| `L > 72%` | Keep the input for the logo, but compute from `Li = 62%`. | Too light to anchor anything; used as-is it would leave the whole app washed out. |
| otherwise | `Li = L`. The input is the identity tone. | The normal case. |

Then check saturation: **if `S < 25%`** the brand is near-neutral (a charcoal, a
slate). The tinted neutrals in §2.4 would read as a second colour rather than as
warmth — **halve every saturation in that table**, and let the semantic tones
(§2.6) carry the colour in the app.

### 2.2 The three tiers

The core of the palette. Each tier has one job, and each is **walked to a
contrast gate** rather than set to a fixed lightness.

| Token | Start at | Job | Gate |
|---|---|---|---|
| `identity` | `hsl(H, S, Li)` | Large fills, icon plates, accents, focus rings, selected states, the logo. | none — but **never small white text on it** |
| `action` | `hsl(H−1, S−4, Li−10)` | Buttons, links, active controls, cursors, progress. | **white on it ≥ 4.5:1** — lower `L` by 1pp until it passes |
| `shell` | `hsl(H−2, S−7, Li−20)` | Big permanent brand surfaces: caps, splash, auth hero, hero slabs. | **`shellInk` on it ≥ 7:1** — lower `L` until it passes |

**Walk to the gate; do not trust the starting number.** HSL lightness is not
perceptual lightness — a green at `L=47%` and a blue at `L=47%` have very
different luminance. A fixed offset that passes on one hue fails on another, so
the offsets above are only where the search starts.

**Why three tiers and not one.** A field of the bright identity tone vibrates
and is unreadable under body copy; a single darkened tone is muddy as an accent.
Three tiers is what lets the brand be loud where loud works and calm where it
doesn't.

**The luminous-hue escape hatch.** For a yellow, lime, amber or bright cyan
`PRIMARY`, reaching 4.5:1 against white means dropping so much lightness that
the hue becomes a different colour — yellow turns brown. **Trigger: the search
above had to go more than 14pp below `Li`.** When it does, stop and do what a
real yellow button does:

- Keep the fill **bright**: `action = hsl(H−1, S−4, max(Li, 52))`.
- Put **dark ink** on it: `actionOn = hsl(H, 70%, 14%)`, darkened until it
  clears 4.5:1 against the fill.
- On this path there are effectively **two tiers, not three** — `identity` and
  `action` land close together, and what distinguishes them is the ink on top,
  not a second hue.
- `shell` still goes deep and still carries warm white. A mustard brand's shell
  reads as a rich bronze. That is correct, not a failure.

### 2.3 The brand ramp

Constant hue, varying lightness. Nine steps, each with a real job — do not add
more, and do not use a step for a job it isn't listed for.

| Step | HSL | Job |
|---|---|---|
| `b50` | `H, 100%, 95%` | Wash. Must stay visible against the tinted page ground. |
| `b100` | `H, 100%, 92%` | Hover tint, badges, the accent-on-shell (`shellMark`). |
| `b200` | `H, 97%, 88%` | Disabled fill for a primary button. |
| `b300` | `H, 95%, 78%` | Subtle accents, decorative rules. |
| `b400` | `H, S+1, Li+9` | Brand text **on dark**. Gate: ≥ 4.5:1 on `darkBg` — **raise** `L` until it passes. |
| `b500` | `= identity` | See §2.2. |
| `b600` | `= action` | See §2.2. |
| `b700` | `H, 88%, 38%` | Brand-coloured **text on a brand tint**. Gate: ≥ 4.5:1 on `brandSoft` — lower `L` until it passes. |
| `b800` | `H, 85%, 29%` | Deep. |
| `b900` | `H, 82%, 20%` | Ramp floor. |

Two more, both keyed to the shell:

| Token | HSL | Job |
|---|---|---|
| `shellInk` | `H, 100%, 98%` | Warm white **on** the shell. Never pure `#FFF` — a neutral white on a saturated ground reads as a hole punched in it. |
| `shellMark` | `H, 100%, 89%` | The accent half of the wordmark when it sits on the shell, and cap badges. |

And one soft surface, a quieter step than `b50`, which you are allowed to set
body text on:

| Token | HSL | Job |
|---|---|---|
| `brandSoft` | `H, 100%, 97%` | Secondary-button fill, tinted panels, notice blocks. |

### 2.4 Tinted neutrals

**The part people skip, and the part that does the most work.** These are not
greys. Each carries the brand hue at low saturation, drifting slightly cooler as
it darkens.

The four with a gate are **starting points** — darken by 1pp until the gate
passes, exactly as in §2.2. This is not optional: at a fixed `L=58%`, `ink400`
measures 3.02:1 on a red-tinted surface and 2.79:1 on a green-tinted one. Same
number, one passes and one fails.

| Token | Start at | Job | Gate (on `surface0`) |
|---|---|---|---|
| `ink900` | `H−15, 11%, 18%` | Primary text. | **≥ 12:1** |
| `ink700` | `H−20, 10%, 25%` | Headings, body, field labels. | **≥ 9:1** |
| `ink500` | `H−15, 8%, 44%` | Secondary text, captions. | **≥ 4.5:1** |
| `ink400` | `H−16, 9%, 58%` | Placeholder, disabled, inactive nav. | **≥ 3:1** |
| `ink300` | `H−12, 13%, 76%` | Muted icons, carets. | — |
| `ink200` | `H−8, 20%, 88%` | **Hairlines, borders, dividers, skeletons.** | — |
| `ink100` | `H−5, 25%, 92%` | Inset divider inside a row group. | — |
| `surface50` | `H−8, 46%, 95%` | **Page ground** — the tinted sheet. | — |
| `surface0` | `H, 100%, 98%` | **Cards, panels, bars.** | — |
| `surfaceRaised` | `#FFFFFF` | Pure white, reserved: a focused field, a pill lifted off a card. | — |
| `field` | `H, 62%, 96%` | A sunken well you type into. | — |

The hue drift (`H−5` to `H−20`) is polish; holding every neutral at exactly `H`
also works and is easier to reason about. The **saturations are not optional** —
that column is the whole effect.

Note the ordering that surprises people: `surface0` (cards) is **lighter** than
`surface50` (the page). Cards lift off the ground by being brighter, not by
casting a shadow.

### 2.5 Shadow ink

```
shadowInk = hsl(H−4, 62%, 27%)
```

Shadows are cast in a deep, half-saturated version of the brand hue — never
neutral black. Over a tinted ground a black shadow turns grey and fights the
palette. See §4.3 for the layer recipes that use it.

### 2.6 Semantic tones

These are **fixed**, not derived. Green must read as green regardless of the
brand. They are muted rather than fluorescent so they sit down in a tinted world.

| Role | Base | `Tint` (badge) | `Ink` (text on tint) | `Soft` (surface) |
|---|---|---|---|---|
| success | `#1C8252` | `#E4F6EC` | `#196B45` | `#EFF8F2` |
| warning | `#D37A0D` | `#FCEFDC` | `#9E5B0A` | `#FDF4E7` |
| danger | `#A51D2F` | `#FCE6E9` | `#821725` | `#FDEFF1` |
| info | `#1F6BC1` | `#E6F0FB` | `#1A579E` | `#EFF4FC` |
| star (ratings only) | `#E8A317` | — | — | — |

Plus `warningOn = #3D2A05`, dark ink for the rare solid-warning fill.

**Watch the amber.** `warningInk` is `#9E5B0A` (4.87:1). The value that *looks*
right — `#AD640B`, one step lighter — measures **4.19:1 and fails AA**. Amber is
the tone where "it looks dark enough" is most often wrong, because the hue is
luminous. Measure it; don't eyeball it.

**The collision rule, and it matters.** A semantic tone must be instantly
distinguishable from the brand, or "delete" stops reading as dangerous. Check
**hue and lightness together** — a deep maroon sits only a few degrees from a
bright pink brand and still reads as clearly different, because the ~19pp
lightness gap does the work. Warn only when the hue gap is under 30° **and** the
lightness gap is under 15pp.

- **Brand is red/pink** → `danger` shifts to the deep maroon above. It is
  deliberately *not* the brand red. (This is the case in the source product.)
- **Brand is green** → shift `success` toward teal (`#0F7B7B`) and lean on the
  check glyph to carry the meaning.
- **Brand is blue** → shift `info` toward slate-cyan (`#1E6E7A`), or drop the
  info tone entirely and use `warning` for advisories.
- **Brand is orange/amber** → shift `warning` toward a browner amber and make
  sure `star` differs from both.

Test it by squinting at a danger button next to a primary button. If you have to
look twice, shift further.

### 2.7 Secondary

If `SECONDARY` is supplied it replaces `info` above (derive its `Tint`/`Ink`/`Soft`
with the same lightness targets: 94%, 36%, 96%), and it becomes the second
category hue and chart series 2. It does **not** get buttons — the app has one
action colour, and a second one just makes both weaker.

If `SECONDARY` is not supplied, everything works; the blue above fills the role.

### 2.8 Dark theme

Surfaces stay brand-hued. A neutral-grey dark theme next to a tinted light theme
reads as two different apps.

| Token | HSL |
|---|---|
| `darkBg` | `H, 13%, 7%` |
| `darkCard` | `H, 13%, 13%` |
| `darkCardRaised` | `H, 11%, 17%` |
| `darkTextHi` | `= surface50` |
| `darkTextLo` | `H, 8%, 63%` |
| `darkBorder` | `H, 9%, 22%` |
| `brandOnDark` | `= b400` |

### 2.9 Contrast gates — all must pass

Run these before writing a single component. A failure here is cheap; a failure
after thirty screens is not.

| Pair | Minimum | Why |
|---|---|---|
| white on `action` | 4.5:1 | Every primary button. |
| `shellInk` on `shell` | 7:1 | Long text on the cap. |
| `ink900` on `surface0` | 12:1 | Body copy. |
| `ink500` on `surface0` | 4.5:1 | Captions. |
| `ink400` on `surface0` | 3:1 | Placeholders, inactive nav. |
| `b700` on `brandSoft` | 4.5:1 | Secondary button label. |
| `b400` on `darkBg` | 4.5:1 | Brand text in dark mode. |
| `successInk` on `successSoft` | 4.5:1 | Text in a success notice. |
| `warningInk` on `warningSoft` | 4.5:1 | See the amber warning in §2.6. |
| `dangerInk` on `dangerSoft` | 4.5:1 | Text in an error notice. |
| `infoInk` on `infoSoft` | 4.5:1 | Text in an info notice. |

`derive_palette.py` checks all twelve and exits non-zero on any failure, so it
can go straight into CI.

### 2.10 Worked example

`PRIMARY = #F72B54` → `hsl(348, 93%, 57%)`. The **derived** column is what the
script emits; the **shipped** column is the hand-tuned palette in the real
product, for comparison.

| Token | Derived | Measured | Shipped |
|---|---|---|---|
| `identity` | `#F72B54` | — | `#F72B54` |
| `action` | `#E20D3C` | white **4.82:1** | `#E30D3B` |
| `shell` | `#A50D30` | `shellInk` **7.28:1** | `#B00D33` |
| `b400` | `#FA5677` | on dark **5.99:1** | `#FA5775` |
| `b700` | `#B60C2E` | on soft **6.17:1** | `#B60C31` |
| `ink900` | `#33292D` | **13.14:1** | `#33292E` |
| `ink500` | `#79676F` | **4.94:1** | `#79676F` |
| `ink400` | `#9E8A93` | **3.02:1** | `#9C8B93` |
| `surface0` | `#FFF5F7` | — | `#FFF6F8` |
| `surface50` | `#F8ECF0` | — | `#F8ECF0` |
| `shadowInk` | `#701A31` | — | `#6E1A30` |

Across all 28 comparable tokens the mean per-channel difference is **2.4/255**
and the worst is 11/255 (`shell`, where walking to the gate lands slightly
deeper than the hand-picked value — which is the safe direction). In other
words: the rules re-derive a palette that took months of tuning, from one hex.

The same rules have been checked against **twelve** brand colours spanning red,
cobalt, emerald, amber, violet, teal, hot pink, lime, sky, and two near-neutral
greys. All twelve pass all twelve gates.

---

## 3. Typography

### 3.1 One face

**Figtree** by default — a warm geometric sans whose heavy weights hold their
counters at display sizes and whose 400 is quiet enough for body copy, so it
carries both jobs alone. Substitutes that behave the same way: Plus Jakarta Sans,
Manrope, Outfit, General Sans.

**Bundle the font files. Do not fetch them at runtime.** A user opening the app
on a bad connection otherwise sees the platform fallback face on first launch,
and the app never renders as designed offline. Ship six weights:
Regular 400, Medium 500, SemiBold 600, Bold 700, ExtraBold 800, Black 900.

### 3.2 The weight ladder

Hierarchy is carried by weight, not by swapping families. The ladder **is** the
system:

| Weight | Used for |
|---|---|
| **800** | Display, page titles, big figures — the things allowed to be loud. |
| **700** | Card / sheet / section titles (≥ `title`). The heaviest a heading gets. |
| **600** | All emphasis below title: buttons, labels, tabs, badges, eyebrows. |
| **500** | Secondary values — one step below normal emphasis. |
| **400** | Body, descriptions, help text. |
| 900 | The signed-out hero line, and nothing else. |

### 3.3 The scale

Sizes in logical pixels; `height` is a line box in px, not a multiplier.

| Role | Size | Line | Weight | Tracking | Default colour |
|---|---|---|---|---|---|
| `display` | 32 | 38 | 800 | −0.7 | `ink900` |
| `h1` | 26 | 32 | 800 | −0.6 | `ink900` |
| `h2` | 22 | 28 | 800 | −0.5 | `ink900` |
| `section` | 19 | 24 | 800 | −0.4 | `ink900` |
| `h3` | 18 | 24 | 700 | −0.3 | `ink900` |
| `title` | 16 | 22 | 700 | −0.2 | `ink900` |
| `body` | 15 | 22 | 400 | 0 | `ink700` |
| `bodyS` | 13 | 18 | 400 | 0 | `ink500` |
| `label` | 12 | 16 | 600 | +0.3 | `ink900` |
| `eyebrow` | 11 | 14 | 600 | +0.7 | `ink500` |

Note `section` (19/800) is heavier than `h3` (18/700) despite being barely
larger. That is intentional: an in-page section heading is doing storefront work
and needs to shout a little; `h3` is a card title and should not.

**`hero(size)`** — the signed-out headline only. Weight 900, `height = size ×
1.05`, tracking `= −size × 0.028`. The tight leading is the point: a two-line
headline at that size wants its lines locked into a single shape, and the
default ~1.19 pulls them into two separate sentences.

### 3.4 Figures

Prices, stats, timers, countdowns and any number that updates in place get
**tabular figures** (`FontFeature.tabularFigures()`). Without it a total shifts
sideways as digits change and the layout looks broken.

---

## 4. Space, radius, depth

### 4.1 Spacing — strict 4pt grid

`4, 8, 12, 16, 20, 24, 32, 40, 48, 64`. Nothing between them.

- **Screen gutter: 20.** Every screen, both edges.
- **Card padding: 16.** Panel padding: 14.

### 4.2 Radius

| Token | Value | Applied to |
|---|---|---|
| `xs` | 8 | Small chips, icon plates, tiny controls |
| `sm` | 12 | Inputs, list rows |
| `md` | 16 | **Cards, panels, tiles, notices, toasts** |
| `lg` | 22 | Large cards, hero slabs |
| `xl` | 28 | Sheet tops, the cap/sheet seam |
| `full` | 999 | **Buttons**, chips, pills, avatars, FAB |

**Buttons are pills.** Next to a pill chip, a pill tab and a pill toggle, a
rounded-rectangle button is the odd one out.

### 4.3 Elevation

Layered shadows in `shadowInk` (§2.5). Each level pairs a **tight contact
shadow** with a **wider soft pool**, and the pool carries a negative spread so it
stays under the element instead of haloing sideways. Written as
`rgba(shadowInk, α) blur / spread / y-offset`:

| Level | Layers | Used for |
|---|---|---|
| `e0` | none | **The default.** Cards are flat. |
| `e1` | `.05 2/0/1` + `.07 6/−2/2` | A pill lifted off a card. |
| `e2` | `.05 2/0/1` + `.08 12/−3/6` + `.09 28/−10/14` | Bottom nav, docked bars, a toggle puck. |
| `e3` | `.06 4/0/2` + `.11 24/−6/12` + `.15 56/−18/28` | Toasts, popovers. |
| `e4` | `.07 8/0/4` + `.15 40/−8/20` + `.24 88/−28/48` | Modals. Rare. |
| `lift` | `rgba(action, .20) 18/−4/8` | **The one hero action on a screen.** |
| `liftHue(c)` | `rgba(c, .18) 18/−4/8` | A selected category tile, a status slab. |

`lift` replaced a 24%-opacity coloured halo. The halo was the loudest
generated-UI tell in the product; this reads as a lift, not a glow. Do not
increase the opacity.

**`hairline` = 1px `ink200` border.** This, not a shadow, is how a resting
surface gets an edge.

---

## 5. Motion

### 5.1 Tokens

| Token | ms | Used for |
|---|---|---|
| `instant` | 100 | Press feedback (scale), shadow swap. |
| `fast` | 180 | Hovers, small state changes, nav icon lift. |
| `base` | 240 | Toasts, switchers, most transitions. |
| `slow` | 360 | Spring toggles, progress-connector fills. |
| `deliberate` | 520 | Rare, celebratory. |

| Curve | Cubic | Used for |
|---|---|---|
| `emphasized` | `(0.2, 0.0, 0.0, 1.0)` | Default for everything. |
| `decelerate` | `(0.0, 0.0, 0.0, 1.0)` | Entering elements. |
| `accelerate` | `(0.4, 0.0, 1.0, 1.0)` | Exiting elements. |
| `easeOutBack` | platform | Only where a control should feel physical (a switch puck). |

### 5.2 Press feedback — the signature

Every tappable surface responds. The amount scales inversely with size, so the
feedback feels like the same amount of give everywhere:

| Element | Scale | Haptic |
|---|---|---|
| Button | **0.97** | `lightImpact` |
| Toggle slab | 0.98 | `mediumImpact` |
| Card | **0.985** | `selectionClick` |
| Nav tab, chip | none | `selectionClick` |

Duration `instant`, curve `emphasized`. A pressed element also drops its shadow
to `e0` — pressing pushes it toward the page.

### 5.3 Entrances

- **Toast:** slide from `Offset(0, −1.2)` + fade, `base`, `decelerate`.
- **Status word changes:** `AnimatedSwitcher` — fade + slide up from `dy 0.35`,
  `base`, in `decelerate` / out `accelerate`. Text that changes meaning morphs;
  it never hard-cuts.
- **Splash:** one 1100ms controller, staggered by intervals — mark fades
  `0→0.5`, lifts 20→0 over `0→0.6`, scales 0.94→1 over `0→0.7`, wordmark
  `0.34→0.85`, strapline `0.55→1`, all `easeOutCubic`. Hold 2200ms total, then a
  260ms route fade. **One controller with intervals, not five controllers.**
- **Lists:** no stagger. A per-row entrance animation is charming once and
  irritating by the third visit.

### 5.4 Reduced motion — non-negotiable

Read `MediaQuery.disableAnimations` at every call site. When set: scale
feedback becomes 1.0, durations become `Duration.zero`, springs collapse to a
cross-fade. Haptics stay — they are not motion.

---

## 6. Icons

**One façade class. Every screen imports icons from it and nowhere else.** A
single `DsIcons` file with `static const` entries gives the app one vocabulary
and exactly one place to swap the underlying family.

Default family: the platform's **rounded/outlined** set (Material rounded in
Flutter) — it ships with the framework, so there is no external dependency and
no version-skew risk, and it reads as one cohesive, friendly family.

Convention: the plain name is the **outlined** variant, `nameFill` is the
**filled** one. Filled is for active nav and selected states only.

Sizes: `14` inside a chip · `18` in a list row · `20` in a field or cap button ·
`24` in nav · `26` on a category plate · `38` in an empty-state medallion.

---

## 7. Screen architecture

### 7.1 The cap and the sheet

**Every signed-in screen is these two surfaces, in this order.** Before this
rule, thirteen screens each invented their own header — some a hero, some a
white app bar, some nothing — and the app read as pages built by different
people on different days.

```
┌─────────────────────────┐
│  CAP — flat `shell`     │   Back control (40dp translucent circle)
│                         │   Title (h1, shellInk) + optional subtitle
│  [back]                 │   Optional trailing widget
│  Title              (x) │   Optional capBottom: search / tabs / filters
│  subtitle               │   Never scrolls. Sized by content.
│  [ search field       ] │
├──╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴──┤   ← radius `xl` (28) top corners
│                         │
│  SHEET — `surface50`    │   Always scrolls. Holds the task.
│                         │   Shadow cast UPWARD onto the cap.
│   ┌───────────────┐     │
│   │ card surface0 │     │
│   └───────────────┘     │
│                         │
├─────────────────────────┤
│  bottomBar (surface0)   │   Docked, outside the scroll, above safe area
└─────────────────────────┘
```

**The sheet's upward shadow is the whole trick:** `rgba(shadowInk×deeper, 0.22)`,
blur 28, offset `(0, −8)`. Without it the sheet looks like a region where the
colour stops. With it, it looks like a card lying on the brand.

Cap padding: `gutter / 6 if back else 12 / gutter / 22 (16 if capBottom)`.

### 7.2 The auth cap is sized against the viewport

Auth screens use the same composition with two differences: the sheet is
`surface0` (not `surface50`), and **the cap has a minimum height of
`viewportHeight × 0.285 − safeAreaTop`.**

Sized by its own content the cap came out around a fifth of the screen, leaving
the form reading as the page and the brand as a band stuck on top of it. Holding
the seam near 28% gives the title red to sit *in* rather than red to sit *on*.

It is a **minimum**, so nothing ever clips: a wrapped title, a large system text
size, or a short phone all push straight past it.

Two responsive steps down, not one:
- `compact` — `viewInsets.bottom > 120` (keyboard up): cap floor drops to 0,
  subtitle hides, title drops to 22. On a small phone a fixed hero pushes the
  last field under the keyboard.
- `tight` — `height < 720`, no keyboard: keep the subtitle, but cut vertical
  padding. Title 26. Otherwise the button at the end of a four-field form ends up
  flush against the bottom edge.

Animate the collapse with `AnimatedSize`, 180ms, `easeOut`.

### 7.3 Controls that live on the shell

Anything on the cap has to survive on a saturated ground. The rule: **a
translucent well, not a bare glyph** — legible without punching a white hole in
the brand.

| Control | Resting | Selected/active |
|---|---|---|
| Cap button | 40dp circle, `white @ 14%`, icon 20 `shellInk` | — |
| Cap chip | pill, `white @ 14%`, border `white @ 18%` | solid `shellInk`, label + icon in `shell` |
| Cap tabs | track `black @ 12%`, padding 4 | selected pill `shellInk`, label `shell` w700 |
| Cap field | 48dp **solid white** pill, radius full | — |
| Cap badge | `shellMark` pill, 1.5px `shell` border | — |

The field is the one thing on the cap that goes fully opaque: you are about to
type into it, so it must read as a real input, not as a tinted region.

### 7.4 Bottom navigation

Height 62 + safe area. `surface0`, 1px `ink200` top border, `e2` shadow.
Icon 24, outlined → filled on selection, lifting `dy −0.06` over `fast`/
`emphasized`. Label in `eyebrow` at tracking 0.3. Active `action`, inactive
`ink400`. `selectionClick` on tap.

Use the **action** tone here, not identity — this is a control.

---

## 8. Component catalogue

Exact geometry. Where a number looks arbitrary it was arrived at by looking at
the thing on a real phone.

### Button

Pill, flat, four variants, three sizes.

| Size | Height | Font | Icon |
|---|---|---|---|
| large | 50 | 16 / w600 | 20 |
| medium | 44 | 15 / w600 | 19 |
| small | 36 | 13 / w600 | 17 |

Icon size is `font + 4`, gap 8. Full-width by default; when not, horizontal
padding 20.

| Variant | Fill | Text | Border | Shadow |
|---|---|---|---|---|
| `primary` | `action` | white | — | `lift` at rest, `e0` pressed |
| `secondary` | `brandSoft` | `b700` | — | none |
| `ghost` | transparent | `ink700` | 1.5px `ink200` | none |
| `destructive` | `dangerSoft` | `danger` | — | none |

Disabled: whole button at `opacity 0.6`, primary fill → `b200`.
Loading: a 20dp spinner, `strokeWidth 2.4`, in the foreground colour, replacing
the label — the button keeps its width so the layout doesn't jump.

**One filled `primary` button per screen.** Everything else is a `secondary`, a
`ghost`, or plain text. A screen with three filled buttons has no primary action.

### Card

Radius `md`. Default: `surface0` fill, `hairline` border, `e0` shadow. Padding 16.
Press: scale 0.985 / `instant`, shadow → `e0`, `selectionClick`.

A card that passes an explicit colour (a status card, a hero) skips the hairline.

**Cards are flat by default and that is deliberate.** Every card sits inside the
sheet, which is already a lifted surface; stacking shadows on a raised surface is
what makes screens read as a pile of receipts. Pass a shadow only for something
that genuinely floats.

### Panel

The plainer sibling: radius `md`, padding 14, `surface0`, 1px `ink200`, no press
state. Use for a block of read-only detail.

### RowGroup + Row

A list of related rows as **one** surface, not a stack of cards.

- Group: radius `md`, clipped, `surface0`, 1px `ink200`.
- Divider between rows: 1px `ink100`, **inset 54 from the left** so it starts
  after the icon plate.
- Row: padding `14 / 12`. A 34dp icon plate at radius `xs` filled `tone @ 10%`
  with an 18dp icon in `tone`; gap 12; label `title` at 15; optional subtitle
  `bodyS` in `ink400`, 1px below; optional right-hand value in `bodyS` `ink500`;
  trailing caret 18 in `ink300` when the row is tappable and has no other
  trailing widget.
- `danger` rows tint the plate and the label in `danger`.

### Stat tile

Radius `md`, `surface0`, hairline, padding `12 / 13`. Icon 18 in its hue, gap 10,
value in **tabular** `h2` at 21, gap 1, label `bodyS` `ink500`. Three fit a phone
row.

### Chip

Pill, padding `12 / 7`. Icon 14, gap 6, label at `label` weight 600.
Default `surfaceRaised` on `ink700`. A status chip is `tint` fill + `Ink` text.
Selected adds a 1.5px `identity` border.

### Category tile

A 58×58 plate at radius `md`, icon 26, gap 8, label at 11.5.

- Unselected: `tint` fill, 1px `hue @ 14%` border, icon in `hue`, label `ink500`
  w600.
- Selected: solid `hue` fill, white icon, `liftHue(hue, .20)`, label `ink900`
  w700.
- 160ms `easeOut`.

**Lay these out in equal-width slots** (one `Expanded` per tile) and clamp the
label to one line. The label is wider than the plate, so a content-sized tile in
a `spaceBetween` row runs off the edge of a 320dp screen.

### Text field

Radius `sm`. The field is a **sunken well that lifts to white on focus** — a real
change of surface, not just a recoloured border.

| State | Fill | Border |
|---|---|---|
| rest | `field` | 1.5px `ink200` |
| focus | `surfaceRaised` | 2px `action` + ring: `action @ 12%`, blur **0**, spread 3 |
| error | `field` | 2px `danger` |
| disabled | `surface50` | 1.5px `ink200` |

140ms transition. Content padding 14 on all sides; a leading icon sits at left 14
/ right 10, size 20, `ink400` → `action` on focus. Cursor in `action`.

Label above: `label` style in `ink700`, 7dp gap.
Error below: 6dp gap, a 14dp warning glyph, gap 5, message in `bodyS` `danger`.
Password fields get a reveal toggle: 20dp eye glyph, `ink400`, padding right 12.

The focus ring uses **blur 0 with spread** — a real ring, not a glow. A blurred
focus shadow reads as the halo this system removed everywhere else.

### Toast

Replaces every snackbar. Enters from the **top**, at `safeAreaTop + 10`, inset by
the gutter.

`surface0`, radius `md`, `e3`, clipped. Left edge: a **5dp colour rail** in the
tone. Then a 34dp tinted circle with a 19dp glyph, padding 10. Then the message
in `body` w500 `ink900`, padding `0 / 12 / 14 / 12`.

Slide + fade in over `base`/`decelerate`. Auto-dismiss at 2600ms; tap dismisses
early. Four kinds: `success`, `error`, `info`, `brand` (the default).

### Bottom sheet

Top radius `xl`, barrier `ink900 @ 45%`, `surface0`.
Grab handle: 40×4, `ink200`, radius 2, margin `10` top / `6` bottom.
Bottom padding must include `safeAreaBottom + 20`.

**Confirm sheets replace alert dialogs.** Handle, 12 gap, `h2` title centred, 8
gap, message in `body` `ink500` centred, 22 gap, primary (or destructive) button,
10 gap, ghost cancel.

### Empty state

A layered medallion, not a flat grey glyph: a 116dp circle in `tint`, containing
a 74dp circle in `hue @ 14%`, containing a 38dp icon in `hue`.
Then 20 gap, `h3` title centred, 6 gap, `body` `ink500` centred, 20 gap, an
optional **medium, non-expanded** button.

Padding `gutter / 40`.

### Skeleton

Blocks in `ink200` (`darkCardRaised` in dark) at radius `xs`, laid out in the
shape of the content that is coming.

A single shimmer wrapper **breathes the whole subtree's opacity** between 1.0 and
0.5 on a 1200ms triangle wave. Not a shader sweep: the pulse is cheaper to
composite and renders correctly on a tinted placeholder in either theme.

### Section title

`section` style, with an optional action on the right that is **text plus a
caret**, in `action`, at `label` size — never a second button.

### Notice

The one shape for "read this before you continue". Radius `md`, padding 13,
`Soft` fill, a 17dp glyph in `Ink` tone, gap 10, message in `bodyS` `Ink` at
line-height 1.45. Factories: `.info`, `.warning`, `.danger`.

### Money line

Label left, value right, vertical padding 3. Value always **tabular**. `strong`
promotes both to `title` and the value to `ink900`. Used by every subtotal in the
app so a total looks identical in a cart, at checkout and on a receipt.

### Step tracker

Vertical. A completed node is solid `success`; the active node is a `brandSoft`
disc inside an `identity` ring with a slowly breathing centre dot; pending nodes
are `ink200`.

The 2.5dp connector **fills over `slow`** rather than snapping, so a step
advancing while the screen is open reads as forward motion.

### Wordmark and lockup

If `WORDMARK_SPLIT` is set, the name renders in one face and two tones: the first
half in `ink900` (or `shellInk` on the shell), the second in `identity` (or
`shellMark` on the shell).

Built from the `display` style with only size and tracking overridden, so the
mark is demonstrably the same face and weight as the headline beneath it.
Tracking `= −size × 0.032`, height 1.1 — tightening as the mark grows is what
keeps it looking drawn rather than typed.

The **lockup** adds the legal entity name 3dp beneath at 11.5 / w500 / tracking
0.1 in `ink500`. Tucked tight so it reads as part of the signature, not as the
first line of copy.

---

## 9. Anti-patterns

**The highest-value section in this document.** Each of these was in the product
and was removed. The reason matters more than the rule.

1. **No gradients.** Anywhere. Not on buttons, headers, cards, tiles or splash.
   *Why:* the single loudest "generated UI" tell. Removing every gradient was
   the biggest quality jump this system ever made. The one exception is a
   **legibility scrim** over a photo or map — that is a function, not a
   decoration.

2. **No coloured glow halos.** The `lift` shadow at 20% is the ceiling.
   *Why:* a pill that grows a neon halo and drops it again on every tap is
   distracting to actually use, and it is the second-loudest generated tell.

3. **No shadows on cards.** Flat plus a hairline.
   *Why:* the cards sit on a sheet that is already lifted. Stacking shadows on a
   raised surface makes a screen read as a pile of receipts.

4. **Never two typefaces.** One family, hierarchy from the weight ladder.
   *Why:* a display/UI split puts a visible seam through every screen — two
   different ideas of what a letter is, reading as two products glued together.
   This system went through three pairings before landing on one face.

5. **Never more than one filled button per screen.** Other affordances are
   words. *Why:* three filled buttons means no primary action.

6. **Never size a hero or cap by its own content.** Size it against the
   viewport, as a minimum. *Why:* content-sized, it collapses to a band stuck on
   top of the page.

7. **Never use the identity tone for small white text.** That is what the action
   tone exists for. *Why:* it fails contrast, and it is the failure most likely
   to survive review because it looks fine on the designer's bright screen.

8. **Never use pure `#FFFFFF` on a brand surface.** Use `shellInk`.
   *Why:* neutral white on a saturated ground reads as a hole punched in it.

9. **Never use neutral-grey text or neutral-black shadows.** Both must carry the
   brand hue. *Why:* grey next to a tinted surface reads as dirt.

10. **Never let a docked bar's safe-area inset be painted in the sheet's
    colour.** Paint it in the bar's colour. *Why:* the bar ends up sitting on a
    stripe of a slightly different tone and reads as a rendering fault.

11. **Never stagger list-item entrance animations.** *Why:* charming once,
    irritating by the third visit.

12. **Never fetch the font at runtime.** Bundle it. *Why:* first launch on a bad
    connection renders in the fallback face, and offline it never renders as
    designed at all.

13. **Never hardcode a hex outside the tokens file.** Not once. *Why:* the one
    hardcoded hex is the one that doesn't move when the brand changes, and it is
    always found by a client rather than by you.

14. **Never let a content-sized tile sit in a `spaceBetween` row.** Equal-width
    slots, clamped labels. *Why:* the longest label runs off a 320dp screen.

15. **Never skip the reduced-motion check.** *Why:* it is one line at each call
    site and it is an accessibility requirement, not a nicety.

---

## 10. Copy

The visual system falls apart under bad copy, so it is part of the system.

- **Titles are labels, not sentences.** "Order history", not "Here are your
  past orders".
- **One quiet line under a title, or none.** Never pad a subtitle to fill space.
- **A row's second line says what the row does, never restates the label.**
- **Sentence case everywhere** except `eyebrow` and status words, which are the
  only place caps are allowed.
- **Errors say what to do, not what failed.** "Check your connection and try
  again", not "Network request failed".
- **Empty states name the thing that is missing and offer the action that
  fixes it.**
- **Never use exclamation marks** outside a genuine celebration (order
  delivered, payout arrived).
- **Numbers are formatted at the edge**, never mid-sentence as raw values.

---

## 11. Accessibility

Treat these as build gates, not review notes.

- Every contrast pair in §2.9 passes.
- Minimum tap target **44×44**, including icon-only cap buttons (40dp visual +
  padding to 44).
- Reduced motion honoured at every animated call site (§5.4).
- Every icon-only control has a semantic label.
- The layout survives a system text scale of **1.3×** without clipping — this is
  what the viewport-relative cap minimum and the two-step auth collapse are for.
- Colour is never the only signal: status carries a glyph and a word, not just a
  tone.
- Dark theme is a real theme, derived per §2.8 — not an inverted light theme.

---

## 12. File layout and build order

```
lib/
  theme/
    ds_colors.dart      ← every colour. The only file with hex in it.
    ds_typography.dart  ← the scale + the weight ladder
    ds_spacing.dart     ← spacing, radius, elevation
    ds_motion.dart      ← durations, curves, reduced-motion helper
    ds_icons.dart       ← the icon façade
    ds_brand.dart       ← app name, version, wordmark, lockup
    app_theme.dart      ← assembled ThemeData, light + dark
  widgets/
    ds_button.dart  ds_card.dart  ds_chip.dart  ds_text_field.dart
    ds_page.dart        ← cap+sheet scaffold, sheet, cap controls,
                          section title, bottom bar, panel, row group,
                          row, stat, notice, money line
    ds_auth_scaffold.dart  ds_bottom_sheet.dart  ds_toast.dart
    ds_empty_state.dart    ds_skeleton.dart
  screens/
```

**Build in this order, and do not start a screen until the layer above it is
done.** Building screens first and extracting components later is how you get
thirteen headers.

1. **Palette.** Derive it, print the full table with every contrast ratio, get it
   approved. Nothing else starts until this passes §2.9.
2. **Token files.** All five. Bundle the font.
3. **`app_theme.dart`.** Light and dark.
4. **Chrome:** page scaffold, sheet, cap controls, bottom nav.
5. **Core components:** button, card, text field, chip, toast.
6. **Everything else** in the catalogue, as needed.
7. **Screens.** By now a screen is composition, not design.

---

## 13. Verification checklist

Run before calling any screen done.

- [ ] `grep` for `Color(0x` / `#` outside the colours file returns **nothing**.
- [ ] `grep` for `Gradient` returns nothing except a photo scrim.
- [ ] No `TextStyle(fontFamily:` outside the typography file; no second family
      anywhere.
- [ ] Every spacing value is on the 4pt grid.
- [ ] Every screen uses the cap+sheet scaffold, or documents why not.
- [ ] Exactly one filled primary button per screen.
- [ ] Every tappable surface has press feedback and a haptic.
- [ ] Every animated call site checks reduced motion.
- [ ] Every list has a skeleton state and an empty state.
- [ ] Every async action has a loading state on the control that triggered it.
- [ ] Every error path shows a toast or an inline error, never a bare exception.
- [ ] All §2.9 contrast gates pass.
- [ ] Renders correctly at 320dp wide and at 1.3× text scale.
- [ ] Dark theme checked on every screen.
- [ ] Font loads with the network off.

---

## Appendix A — token source (Flutter)

Parameterised. Replace every `<...>` with the derived value from §2, and `Ds`
with your prefix if you want one.

**`ds_colors.dart` does not need to be written by hand** —
`./derive_palette.py "#YOURHEX" --dart` emits it complete, commented and gate-
checked. The version below is the shape it produces, for reference.

<details>
<summary><code>ds_colors.dart</code> — generated, shown for reference</summary>

```dart
import 'package:flutter/material.dart';

/// Design system — colour tokens. THE ONLY FILE IN THE APP WITH A HEX IN IT.
///
/// Three ideas carry the palette:
///  1. THREE-TIER BRAND. [identity] is bright and never carries small white
///     text — large fills, plates, accents, focus rings. [action] takes white
///     on it — buttons, links, active states. [shell] paints big permanent
///     brand SURFACES under warm-white ink.
///  2. TINTED NEUTRALS. Surfaces are not white and text is not grey; both are
///     the brand hue at 3-12% saturation, so the brand belongs to the same
///     family as its background.
///  3. NO GRADIENTS. Depth is hairlines + tinted shadows, never a sheen.
class DsColors {
  DsColors._();

  // ── Brand ramp ──────────────────────────────────────────────────────────
  static const Color b50  = Color(<b50>);   // wash
  static const Color b100 = Color(<b100>);  // hover tint, badges
  static const Color b200 = Color(<b200>);  // disabled fill
  static const Color b300 = Color(<b300>);  // subtle accents
  static const Color b400 = Color(<b400>);  // brand text ON DARK
  static const Color b500 = Color(<b500>);  // IDENTITY
  static const Color b600 = Color(<b600>);  // ACTION
  static const Color b700 = Color(<b700>);  // brand text on a brand tint
  static const Color b800 = Color(<b800>);
  static const Color b900 = Color(<b900>);

  /// Large fills, icon plates, accents, focus rings. NOT small white text.
  static const Color identity = b500;
  /// Primary buttons, links, active states. White on it clears AA.
  static const Color action = b600;
  /// Brand-coloured text sitting on [brandSoft].
  static const Color brandInk = b700;

  // ── The shell: big FLAT brand surfaces ──────────────────────────────────
  static const Color shell     = Color(<shell>);
  static const Color shellInk  = Color(<shellInk>);  // warm white ON the shell
  static const Color shellMark = Color(<shellMark>); // accent on the shell

  /// Legibility scrim over photos/maps. The ONLY gradient in the system.
  static const LinearGradient inkScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00<darkBgRGB>), Color(0xB8<darkBgRGB>)],
  );

  // ── Semantic ────────────────────────────────────────────────────────────
  static const Color success     = Color(0xFF1C8252);
  static const Color successTint = Color(0xFFE4F6EC);
  static const Color successInk  = Color(0xFF196B45);
  static const Color successSoft = Color(0xFFEFF8F2);
  static const Color warning     = Color(0xFFD37A0D);
  static const Color warningTint = Color(0xFFFCEFDC);
  static const Color warningInk  = Color(0xFFAD640B);
  static const Color warningSoft = Color(0xFFFDF4E7);
  static const Color warningOn   = Color(0xFF3D2A05);
  static const Color danger      = Color(<danger>); // must NOT read as brand
  static const Color dangerTint  = Color(<dangerTint>);
  static const Color dangerInk   = Color(<dangerInk>);
  static const Color dangerSoft  = Color(<dangerSoft>);
  static const Color info        = Color(<info>);   // = SECONDARY if supplied
  static const Color infoTint    = Color(<infoTint>);
  static const Color infoInk     = Color(<infoInk>);
  static const Color infoSoft    = Color(<infoSoft>);
  static const Color star        = Color(0xFFE8A317); // ratings only

  /// A quieter step than the *Tint badges — a legitimate SURFACE for text.
  static const Color brandSoft = Color(<brandSoft>);

  // ── Tinted neutrals ─────────────────────────────────────────────────────
  static const Color ink900        = Color(<ink900>); // primary text
  static const Color ink700        = Color(<ink700>); // headings / body
  static const Color ink500        = Color(<ink500>); // secondary text
  static const Color ink400        = Color(<ink400>); // placeholder / disabled
  static const Color ink300        = Color(<ink300>); // muted icons
  static const Color ink200        = Color(<ink200>); // HAIRLINES / borders
  static const Color ink100        = Color(<ink100>); // inset divider
  static const Color surface50     = Color(<surface50>); // page ground
  static const Color surface0      = Color(<surface0>);  // cards
  static const Color surfaceRaised = Color(0xFFFFFFFF);  // focused field, pill
  static const Color field         = Color(<field>);     // sunken well

  // ── Dark theme ──────────────────────────────────────────────────────────
  static const Color darkBg         = Color(<darkBg>);
  static const Color darkCard       = Color(<darkCard>);
  static const Color darkCardRaised = Color(<darkCardRaised>);
  static const Color darkTextHi     = surface50;
  static const Color darkTextLo     = Color(<darkTextLo>);
  static const Color darkBorder     = Color(<darkBorder>);
  static const Color brandOnDark    = b400;
}
```
</details>

<details>
<summary><code>ds_typography.dart</code></summary>

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ds_colors.dart';

/// Design system — typography.
///
/// ONE FACE. Hierarchy is carried by the WEIGHT LADDER, not by swapping
/// families — a display/UI split puts a visible seam through every screen.
///
///   800  display, page titles, big figures
///   700  card / sheet / section titles (>= [title])
///   600  ALL emphasis below title: buttons, labels, tabs, badges, eyebrows
///   500  secondary values
///   400  body, descriptions, help text
class DsType {
  DsType._();

  static const _ink = DsColors.ink900;
  static const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

  static TextStyle _f({
    required double size,
    required double height,
    required FontWeight weight,
    Color? color,
    double? spacing,
  }) => GoogleFonts.<font>(
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color ?? _ink,
      );

  static TextStyle get display =>
      _f(size: 32, height: 38, weight: FontWeight.w800, spacing: -0.7);
  static TextStyle get h1 =>
      _f(size: 26, height: 32, weight: FontWeight.w800, spacing: -0.6);
  static TextStyle get h2 =>
      _f(size: 22, height: 28, weight: FontWeight.w800, spacing: -0.5);
  static TextStyle get section =>
      _f(size: 19, height: 24, weight: FontWeight.w800, spacing: -0.4);
  static TextStyle get h3 =>
      _f(size: 18, height: 24, weight: FontWeight.w700, spacing: -0.3);
  static TextStyle get title =>
      _f(size: 16, height: 22, weight: FontWeight.w700, spacing: -0.2);
  static TextStyle get body =>
      _f(size: 15, height: 22, weight: FontWeight.w400, color: DsColors.ink700);
  static TextStyle get bodyS =>
      _f(size: 13, height: 18, weight: FontWeight.w400, color: DsColors.ink500);
  static TextStyle get label =>
      _f(size: 12, height: 16, weight: FontWeight.w600, spacing: 0.3);
  static TextStyle get eyebrow => _f(
        size: 11, height: 14, weight: FontWeight.w600,
        spacing: 0.7, color: DsColors.ink500,
      );

  /// The signed-out hero line, and only that. Weight 900 with leading locked
  /// near 1.05 so a two-line headline reads as one shape, not two sentences.
  static TextStyle hero(double size) => _f(
        size: size,
        height: size * 1.05,
        weight: FontWeight.w900,
        spacing: -size * 0.028,
      );

  /// Prices, stats, timers — anything whose digits change in place.
  static TextStyle tabular(TextStyle base) => base.copyWith(fontFeatures: _tnum);
}
```
</details>

<details>
<summary><code>ds_spacing.dart</code></summary>

```dart
import 'package:flutter/material.dart';
import 'ds_colors.dart';

class DsSpacing {
  DsSpacing._();
  // Strict 4pt grid.
  static const double x1 = 4,  x2 = 8,  x3 = 12, x4 = 16, x5 = 20;
  static const double x6 = 24, x8 = 32, x10 = 40, x12 = 48, x16 = 64;

  static const double gutter = 20;  // every screen, both edges
  static const double cardPad = 16;
}

/// Corner radii. BUTTONS ARE PILLS — next to a pill chip, a pill tab and a
/// pill toggle, a rounded-rectangle button is the odd one out.
class DsRadius {
  DsRadius._();
  static const double xs = 8, sm = 12, md = 16, lg = 22, xl = 28, full = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius inputRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(full));
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// Layered shadows in the BRAND HUE, never neutral black — over a tinted
/// ground a black shadow turns grey and fights the palette. Each level pairs
/// a tight contact shadow with a wider soft pool; the pool's negative spread
/// keeps it under the element instead of haloing sideways.
class DsElevation {
  DsElevation._();

  // <sr>,<sg>,<sb> = shadowInk from §2.5
  static const List<BoxShadow> e0 = [];

  static const List<BoxShadow> e1 = [
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .05), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .07), blurRadius: 6, spreadRadius: -2, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> e2 = [
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .05), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .08), blurRadius: 12, spreadRadius: -3, offset: Offset(0, 6)),
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .09), blurRadius: 28, spreadRadius: -10, offset: Offset(0, 14)),
  ];

  static const List<BoxShadow> e3 = [
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .06), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .11), blurRadius: 24, spreadRadius: -6, offset: Offset(0, 12)),
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .15), blurRadius: 56, spreadRadius: -18, offset: Offset(0, 28)),
  ];

  static const List<BoxShadow> e4 = [
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .07), blurRadius: 8, offset: Offset(0, 4)),
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .15), blurRadius: 40, spreadRadius: -8, offset: Offset(0, 20)),
    BoxShadow(color: Color.fromRGBO(<sr>,<sg>,<sb>, .24), blurRadius: 88, spreadRadius: -28, offset: Offset(0, 48)),
  ];

  /// The lift under the ONE hero action per screen. A restrained brand-tinted
  /// drop that reads as a lift, not a glow. Do not raise the opacity.
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color.fromRGBO(<ar>,<ag>,<ab>, 0.20),
        blurRadius: 18, spreadRadius: -4, offset: Offset(0, 8)),
  ];

  static List<BoxShadow> liftHue(Color c, {double opacity = 0.18}) => [
        BoxShadow(color: c.withValues(alpha: opacity),
            blurRadius: 18, spreadRadius: -4, offset: const Offset(0, 8)),
      ];

  /// The resting-card edge. This, not a shadow, is how a surface gets defined.
  static Border hairline = Border.all(color: DsColors.ink200, width: 1);
}
```
</details>

<details>
<summary><code>ds_motion.dart</code></summary>

```dart
import 'package:flutter/material.dart';

/// Design system — motion. Every transition, press and entrance pulls from
/// here so the whole app moves with one rhythm.
class DsMotion {
  DsMotion._();

  static const Duration instant    = Duration(milliseconds: 100);
  static const Duration fast       = Duration(milliseconds: 180);
  static const Duration base       = Duration(milliseconds: 240);
  static const Duration slow       = Duration(milliseconds: 360);
  static const Duration deliberate = Duration(milliseconds: 520);

  static const Cubic emphasized = Cubic(0.2, 0.0, 0.0, 1.0); // default
  static const Cubic decelerate = Cubic(0.0, 0.0, 0.0, 1.0); // entering
  static const Cubic accelerate = Cubic(0.4, 0.0, 1.0, 1.0); // exiting

  /// Check this at EVERY animated call site.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}
```
</details>

---

## Appendix B — porting off Flutter

The system is expressed in Flutter above, but nothing in it is Flutter-specific.

- **React Native / SwiftUI / Compose:** map §2 to a constants module, §3 to text
  styles, §8 to components. The geometry tables transfer unchanged.
- **Web / CSS:** emit §2 as custom properties on `:root`, with a
  `prefers-color-scheme: dark` block for §2.8. The elevation recipes are
  `box-shadow` lists verbatim. `emphasized` is
  `cubic-bezier(0.2, 0, 0, 1)`. `prefers-reduced-motion` replaces §5.4. Buttons
  get `border-radius: 999px`. **Add hover states** — the mobile system has none
  because phones have no cursor: hover lifts a card's background to
  `surfaceRaised` and darkens `action` by 4pp lightness; never move an element on
  hover.
- **Figma:** §2 → colour styles named for their **job**, not their value
  (`action`, not `red-600`). §3 → text styles. §4.3 → effect styles.
