# ShipEast Admin — Design Restyle Spec

**Status:** approved-pending · **Author:** design audit, 2026-07-30
**Scope:** `admin_panel/` only. Customer and driver apps are untouched.

This is the single source of truth for the restyle. Every agent reads this file
first and takes values from it verbatim. **No agent invents a colour, a size, or
a spacing value.** If a value you need is not in §2, stop and ask.

---

## 1. What the audit found

Measured, not guessed. Reproduce with the scripts in §9.

### 1.1 The brand red in the code is not the brand red

| | hex | HSL | note |
|---|---|---|---|
| Logo artwork (`assets/shipeasr-orignal-logo.png`) | `#FF0043` | 344, 100%, 50% | 519,357 px — the dominant fill |
| App icon (`assets/icon.png`) | `#F82C53` | 349, 94%, 57% | diagonal gradient `#F93455`→`#EF194A` |
| **`--brand` shipped in `styles.css`** | **`#C8102E`** | **350, 85%, 42%** | **15 L-points darker, 9–15 S-points duller** |

`#C8102E` reads as wine/maroon. The brand is a hot crimson-rose. Every red in
the panel descends from the wrong anchor — `--red-50…900`, `--grad-ember`,
`--grad-sunset`, `--brand-text`, `theme-color`, and 10 hardcoded hex values in
`app.js`.

### 1.2 The neutrals fight the red

Every neutral is warm khaki — `--bg` hsl(**40**, 23%, 97%), `--border`
hsl(**38**, 17%, 87%), `--ink-500` hsl(**37**, 9%, 38%), `--band` hsl(**40**,
29%, 94%). A yellow-undertone beige under a hue-347 rose is a mud pairing: the
two undertones cancel. This is the "not clean" complaint. foodpanda and Zomato
both run cool/neutral greys under their pinks for exactly this reason.

### 1.3 Text is simultaneously too harsh and illegible

| role | value | on white | verdict |
|---|---|---|---|
| `--text-hi` | `#1C1A17` | **17.36:1** | harsher than GitHub (15.8), Linear (14.3), Material (16.1) — above *all* benchmarks |
| `--text-lo` | `#6B6459` | 5.85:1 | thin for body |
| `--text-mute` | `#938C7F` | **3.33:1** | **fails WCAG AA** |
| `--text-mute` on `--band` | | **2.96:1** | **fails badly** |

`--text-mute` carries stat-card labels, stat sub-text, breadcrumb, date, bell
subtitles, side-panel section titles, every `.fr label`, mobile table column
labels and empty-state copy. So the *secondary* layer of the whole panel is
unreadable while the *primary* layer vibrates.

### 1.4 Weight is the real source of "harsh"

89 `font-weight` declarations: **700 → 29×, 800 → 25×**. 54 of 89 are ≥700.
`font-weight:400` appears **twice**. When everything is bold, nothing is
emphasised and the page shouts. This — not absolute size — is why it reads harsh.

### 1.5 The type scale is not a scale

**24 distinct font sizes**, including five half-pixel values (9.5, 10.5, 11.5,
12.5, 13.5px) that exist only as manual nudges. A scale *is* declared
(`.t-display`…`.t-eyebrow`) but almost nothing uses it — components each declare
their own size inline.

### 1.6 The 4pt grid is nominal, not real

`--s1…--s16` exist, but raw off-grid px are used ~100 times alongside them:
`10px`×16, `5px`×15, `14px`×15, `13px`×11, `3px`×10, `9px`×6, `7px`×5, `11px`×3,
`15px`×4, `18px`×1. Spacing feels arbitrary because it is.

### 1.7 Too much gloss, too many accents

- **Gradients at 11 use sites** — primary buttons, sidebar mark, nav rail, stat
  rails, toggle, side-panel avatar, phone badge, promo card, zone bars, progress
  fills, login hairline. The icon the brand is built on is **flat** (≈5%
  gradient variance). Gradient-everything is the "AI-coded" tell.
- **`--glow: 0 6px 16px rgba(200,16,46,.20)`** — a coloured halo on buttons,
  avatars and toggles. Visual noise.
- **Five accent hues** (red, gold `#F5A524`, teal `#0E9488`, green `#16A34A`,
  amber warning) plus four category colours. Zomato/foodpanda run one brand hue
  plus 2–3 semantics.
- **`--danger #D92D20` is hue 4** — only ~17° from the brand red. Destructive
  and primary actions are confusable.

---

## 2. The new system — LOCKED VALUES

All contrast figures below are computed and verified (§9). Do not alter.

### 2.1 Red ramp — anchored to the real brand

`--red-500` is the app-icon red to within 1 HSL point. This is the identity tier.

```
--red-50:  #FFF0F3    hsl(348,100%,97%)
--red-100: #FFE0E7    hsl(348,100%,94%)
--red-200: #FEC3CF    hsl(348, 96%,88%)
--red-300: #FC92A6    hsl(349, 94%,78%)
--red-400: #FA5775    hsl(349, 94%,66%)
--red-500: #F72B54    hsl(348, 93%,57%)   ← IDENTITY. == icon.png
--red-600: #E30D3B    hsl(347, 89%,47%)   ← ACTION. white-on = 4.79:1 AA
--red-700: #B60C31    hsl(347, 88%,38%)   ← text-on-tint. 6.16:1 on red-50
--red-800: #890B28    hsl(346, 85%,29%)
--red-900: #5C0A1F    hsl(345, 80%,20%)
```

**The two-tier rule.** Neither true brand red carries white text at AA
(`#FF0043` = 3.94:1, `#F82C53` = 3.83:1). This is why the previous author
darkened to `#C8102E` and lost the brand. The professional fix is the two-tier
pattern Zomato ships (bright `#E23744` brand / `#CB202D` action):

- **`--red-500` = identity.** Large fills, icon plates, rails, accent bars,
  logo lockup, illustration, focus rings, chart fills. Never carries small
  white text.
- **`--red-600` = action.** Primary buttons, links, active states, anything
  with white text on it. 4.79:1 — passes AA.
- **`--red-700` = red text on a red tint.** Badges, chips.

### 2.2 Neutral ramp — rose-tinted slate

Hue slides 340→325 as it darkens (deeper neutrals carry more of the brand's
undertone). Saturation stays 8–24% — these read as grey, not pink.

```
--n-0:   #FFFFFF
--n-50:  #FBF9F9    page background
--n-100: #F7F3F4    band / track / sunken surface
--n-200: #EBE5E7    border
--n-300: #D6CCD0    border-strong / track fill
--n-400: #9C8B93    disabled ink            3.22:1
--n-500: #79676F    tertiary ink            5.27:1 card · 4.79:1 band  ← was 3.33 FAIL
--n-600: #5C4D54    secondary ink           7.94:1 card · 7.22:1 band
--n-700: #463940
--n-800: #33292E    primary ink            14.02:1 card · 12.74:1 band  ← was 17.36
--n-900: #1F191C    sidebar / dark card
--n-950: #140F12    dark bg
```

### 2.3 Semantics

`warning` **never** takes white text (no usable amber reaches 4.5:1 with
white). Use tint + deep ink, or a solid fill with `#3D2A05` ink (4.28:1).

```
--success:      #1C8252   white-on 4.81:1     --success-tint: #ECF9F2   deep #196B45 → 6.01:1
--warning:      #D37A0D   dark ink only       --warning-tint: #FDF3E2   deep #AD640B → 4.15:1
--danger:       #A51D2F   white-on 7.46:1     --danger-tint:  #FDEDEF   deep #821725 → 8.83:1
--info:         #1F6BC1   white-on 5.34:1     --info-tint:    #EDF5FD   deep #1A579E → 6.58:1
```

**Danger is deliberately a deep desaturated maroon**, 19 L-points below
`--red-500`. It reads *grave*, not *primary* — which is what makes a destructive
button distinguishable from a brand button in an all-red panel.

**Retired:** `--gold-500`, `--ocean-500` as decorative accents. Gold survives
only for star ratings (`--star: #E8A317`). Teal is folded into `--info`.

### 2.4 Dark theme

Brand **lifts** on dark, it does not darken.

```
--bg: #140F12   --card: #221B1F   --card-raised: #2D2529   --band: #2D2529
--text-hi:   #FBF9F9   16.09:1
--text-lo:   #D6CCD0   10.77:1
--text-mute: #9C8B93    5.25:1
--brand-text: --red-400 #FA5775   5.37:1   (red-500 is only 4.36:1 — too low for text)
--brand-fill: --red-600            (buttons keep white text at 4.79:1)
--border: #3A3035   --border-strong: #4A3E44   --sidebar-bg: #0E0A0C
```

### 2.5 Type scale — 10 sizes, down from 24

Keep both self-hosted families; the pairing is sound and the `.woff2` files
already ship. Fix the *application*, not the fonts.

- **Plus Jakarta Sans** — display and headings **only**. Weights 600/700.
  **800 is retired** — it is the single biggest cause of the harsh feel.
- **Inter** — everything else. 400 body / 500 UI + emphasis / 600 strong.

| token | size | line-height | family / weight | tracking | used for |
|---|---|---|---|---|---|
| `--fs-micro` | 11px | 1.27 | Inter 600 | +0.05em | eyebrows, uppercase labels, badges |
| `--fs-caption` | 12px | 1.33 | Inter 500 | 0 | meta, sub-text, hints |
| `--fs-dense` | 13px | 1.45 | Inter 400 | 0 | table cells, side-panel rows |
| `--fs-body` | 14px | 1.5 | Inter 400 | 0 | **base** |
| `--fs-body-lg` | 15px | 1.5 | Inter 500 | 0 | lede, emphasis |
| `--fs-title` | 17px | 1.3 | Jakarta 600 | −0.01em | card titles, modal sub-heads |
| `--fs-h3` | 20px | 1.25 | Jakarta 700 | −0.015em | section heads, modal titles |
| `--fs-h2` | 24px | 1.2 | Jakarta 700 | −0.02em | page titles |
| `--fs-h1` | 30px | 1.15 | Jakarta 700 | −0.02em | display |
| `--fs-stat` | 26px | 1.05 | Jakarta 700 | −0.02em | stat values (tabular) |

**Banned:** all half-pixel sizes; any size not in this table; `font-weight:800`;
`letter-spacing` values other than `−0.02em`, `−0.015em`, `−0.01em`, `0`,
`+0.05em`.

Body base moves 15px → **14px** and table cells hold at 13px. Rationale: 15px
body beside 13px cells was an unowned mismatch; 14/13 is the standard admin
density (GitHub 14, Stripe 14, Linear 13).

### 2.6 Spacing — strict 4pt, plus semantic roles

```
--sp-1: 4px    --sp-2: 8px    --sp-3: 12px   --sp-4: 16px   --sp-5: 20px
--sp-6: 24px   --sp-7: 32px   --sp-8: 40px   --sp-9: 48px   --sp-10: 64px
--sp-half: 2px          /* hairline optical nudges ONLY */
```

Agents use the **semantic** tokens, not the raw scale. This is what keeps five
parallel agents consistent:

```
--pad-page-y: 24px     --pad-page-x: 20px    (→ 32px at ≥1280, 16px at ≤600)
--pad-card: 20px                             (→ 24px at ≥1280, 16px at ≤600)
--pad-card-head-y: 14px
--pad-cell-y: 12px     --pad-cell-x: 12px
--pad-btn-y: 10px      --pad-btn-x: 18px
--pad-input-y: 11px    --pad-input-x: 14px
--gap-section: 24px    /* between cards / major blocks */
--gap-field: 16px      /* between form rows */
--gap-inline: 8px      /* icon↔label, button clusters */
--gap-tight: 4px
--h-control: 40px      --h-control-lg: 48px   --h-topbar: 64px
--sidebar-w: 248px
```

**Banned:** any raw px in `padding`/`margin`/`gap` other than `1px` borders and
`--sp-half`. No `3px`, `5px`, `7px`, `9px`, `10px`, `11px`, `13px`, `14px`,
`15px`, `18px` literals.

### 2.7 Radius — even 2px rhythm

```
--r-xs: 6px    --r-sm: 8px    --r-md: 10px   --r-lg: 14px   --r-xl: 18px
--r-full: 999px
```

Nudged up from the odd 5/7/9/12/16 to echo the icon's friendly squircle without
returning to pill-everything. Circles and pills keep `--r-full`.

### 2.8 Elevation — flat, neutral, no coloured halo

```
--e1: 0 1px 2px rgba(31,25,28,.05)
--e2: 0 2px 4px rgba(31,25,28,.06), 0 4px 12px rgba(31,25,28,.05)
--e3: 0 8px 24px rgba(31,25,28,.10)
--e4: 0 16px 40px rgba(31,25,28,.16)
```

**`--glow` is deleted.** Every use site becomes `--e1` or `--e2`, or nothing.

### 2.9 Flatness — the 2D rule

`assets/icon.png` is a **flat** saturated crimson field with a bold white glyph
and generous inset. That is the design language: flat, confident, two-tone.

Gradients are removed from **9 of 11** use sites and replaced with solid
`--red-600` (action) or `--red-500` (identity). Gradient survives in exactly two
places, where it carries meaning:

1. `#login-page` canvas bloom — atmospheric, behind the card.
2. `.pc-prev` promo preview — it depicts a marketing coupon.

`--grad-ember` and `--grad-sunset` are deleted as general-purpose fills.

---

## 3. Architecture change (Phase 0)

`styles.css` is 1613 lines and five agents cannot safely edit one file
concurrently. Split it — a pure mechanical move, **zero visual change**:

```
css/tokens.css       fonts, :root, [data-theme=dark], reset, type utilities, .ic
css/shell.css        login, sidebar, topbar, bell, .pw, side panel, modals, toasts, overlays
css/components.css   cards, stat cards, tables, badges, buttons, forms, selects, tabs,
                     toggle, skeletons, empty states, uploader, emoji picker, fieldsets,
                     stars, credential box
css/pages.css        charts, zone/payment bars, phone mock, promo preview, notices,
                     helper, menu-item cards, category icons, usage bars
css/responsive.css   every media query + prefers-reduced-motion
```

Load order in `index.html` **is** the cascade order — five `<link>` tags in the
sequence above. HTTP/2 on Firebase Hosting multiplexes; no runtime cost.

`styles.css` is deleted once the split verifies.

---

## 4. Phases

Phase 1 blocks everything. Phase 2 is the parallel wave. Phases 3–4 are
sequential because they depend on the finished class surface.

### Phase 0 — Foundation *(solo, sequential)*
1. Branch `feat/admin-brand-2026`.
2. Split `styles.css` → `css/*.css` per §3. Move rules verbatim; change nothing.
3. Update `<link>` tags in `index.html`.
4. Verify: rule count before == after; all 10 pages render identically in both
   themes. Commit as a pure refactor.

### Phase 1 — Token layer *(solo, sequential, blocks all)*
Rewrite `css/tokens.css` to §2.1–2.8.

**Compatibility aliasing is mandatory.** Keep every old token name alive as an
alias onto the new value, so the panel keeps rendering while Phase 2 migrates
use sites:

```css
--brand:        var(--red-600);
--brand-text:   var(--red-700);
--text-hi:      var(--n-800);
--text-lo:      var(--n-600);
--text-mute:    var(--n-500);
--border:       var(--n-200);
--bg:           var(--n-50);
--card:         var(--n-0);
--band:         var(--n-100);
--track:        var(--n-100);
--ink-900:      var(--n-800);   /* …and the rest of --ink-* */
--s1…--s16:     → --sp-* equivalents
--glow:         var(--e2);      /* neutralised, not yet deleted */
--grad-ember:   var(--red-600); /* flattened via alias — instant de-gloss */
--grad-sunset:  var(--red-600);
```

Aliases are deleted in Phase 4. This single step already lands ~70% of the
colour correction across the whole panel with no other file touched.

### Phase 2 — Parallel restyle *(5 agents, concurrent, disjoint files)*

| agent | owns | must not touch |
|---|---|---|
| **A · Shell** | `css/shell.css` | any other file |
| **B · Components** | `css/components.css` | any other file |
| **C · Pages** | `css/pages.css` | any other file |
| **D · Markup** | `index.html` | any `css/*`, `app.js` |
| **E · Rendered** | `app.js` | any `css/*`, `index.html` |

Ownership is exclusive — one writer per file, so there is no read-modify-write
race. Each agent's brief is §5–§7.

### Phase 3 — Responsive & density *(solo, after Phase 2)*
Rewrite `css/responsive.css`. Depends on the final class surface, so it cannot
run in parallel. Also removes the **duplicated mobile-table block** — §1 of
`styles.css` currently defines "MOBILE TABLES → COLLAPSIBLE CARDS" at line 1287
*and* "MOBILE TABLES → STACKED CARDS" at line 1418; the second silently
overrides the first, which is why expanded rows behave oddly. Keep the
collapsible version, delete the duplicate.

### Phase 4 — Sweep & verify *(solo)*
1. Delete every Phase-1 alias; fix whatever breaks.
2. Grep gates (must all return zero):
   `#C8102E` · `#E1495F` · `#FFF1F3` · `#86091E` · `#F04A5E` · `grad-ember` ·
   `grad-sunset` · `--glow` · `font-weight:800` · `[0-9]\.5px` ·
   `--ink-` · `--s[0-9]`
3. Re-run the contrast verifier (§9) against the final token file.
4. Manual pass: 10 pages × 2 themes × 3 viewports (390 / 900 / 1440).
5. `theme-color` meta → `#E30D3B`.

---

## 5. Per-page work — element by element

Every page shares the same skeleton, so fix it once in the shared components and
the whole panel moves. Listed page-by-page so nothing is missed.

### 5.0 Shared chrome *(Agent A + B)*

**Sidebar** (`.sidebar`, `.sb-logo`, `.sb-mark`, `.ni`, `.sb-sec`, `.ni-badge`)
- `--sidebar-bg` → `--n-900` `#1F191C` (light) / `#0E0A0C` (dark).
- `.slt span` red → `--red-400` (needs to read on near-black: 5.37:1).
- `.sb-mark` gradient → flat `--red-600`, drop `--glow`.
- `.ni` 14px/500 → `--fs-body` 14px/500, padding `12px var(--s5)` →
  `var(--sp-3) var(--sp-5)`.
- `.ni::before` rail gradient → flat `--red-500`, width 3px → `--sp-half`×2.
- `.ni.active` background `rgba(240,74,94,.13)` → `rgba(250,87,117,.14)`;
  icon → `--red-400`.
- `.ni-badge` retint: brand → `--red-600`; drop the `box-shadow` ring halo;
  `data-tone` gold/ocean → `--warning`/`--info`.
- `.sb-sec` 10px/700/+0.8px → `--fs-micro` 11px/600/+0.05em, opacity → a real
  colour (`--n-500` at sidebar scope) so it is not a transparency guess.

**Topbar** (`.topbar`, `.tb-bc`, `.tb-date`, `.ab`, `.av`, `.an`, `.iconbtn`)
- `min-height:68px` → `--h-topbar` 64px.
- `.tb-bc` 12px/700/+0.5px/uppercase → `--fs-micro`; `em` → `--red-600`.
- `.tb-date` `--text-mute` at 3.33:1 → `--n-500` 5.27:1.
- `.av` teal gradient → flat `--n-700` with `--n-0` initial. The original
  comment's intent (the only red dot up here is the unread badge) is correct
  and is preserved — but teal is retired, so it becomes neutral.
- `.an` 13.5px → `--fs-caption` 12px/500.
- `.iconbtn` 38px → `--h-control` 40px, `--r-sm`.

**Activity bell** (`.bell-*`)
- `.bell-badge` → `--red-600`, keep `--r-full`.
- `.bell-menu` `--r-md`, `--e3`; `.bell-hd` 14px/800 → `--fs-title` 17px/600.
- `.bell-sub` 11px → `--fs-caption` 12px, `--n-500`.
- `.bell-dot` tones → red-500 / warning / info / success.
- `.bell-empty` icon 30px → 28px, `--success`.

**Page wrapper & title** (`.pw`, `.pg-hdr`, `.pg-title`)
- `.pw` padding → `--pad-page-y --pad-page-x`; `max-width:1560px` → `1440px`
  (1560 is wider than the content ever needs and leaves stat cards stretched).
- `.pg-hdr` `margin-bottom:var(--s5)` → `--gap-section` 24px.
- `.pg-title` — **drop the band-and-border treatment.** A page title does not
  need a plate; it needs air. Becomes `--fs-h2` 24px Jakarta 700 −0.02em,
  `--n-800`, no background, no border, no left rail. The `clamp()` stays for
  "Shop & Deliver Requests" but retargets `clamp(20px, 1.1rem + .9vw, 24px)`.

**Cards** (`.card`, `.card-title`, `.card-note`, `.card.danger-zone`)
- `--card-pad` → `--pad-card`; `margin-bottom` → `--gap-section`.
- `border-radius` `--r-md` 10px; `--e1`.
- `.card-title` 15px/800 → `--fs-title` 17px Jakarta **600**; band stays
  `--n-100`; padding → `var(--pad-card-head-y) var(--pad-card)`.
- `.card-note` 11px → `--fs-caption` 12px/500 `--n-500`.
- `.danger-zone` → `--danger-tint` bg, `--red-200`→`#F3C6CB` border,
  `.card-title` ink → `#821725` (8.83:1).

**Tables** (`.tbl-wrap`, `thead th`, `td`, `.cell-*`)
- `thead th` 11px/800/+0.7px → `--fs-micro` 11px/**600**/+0.05em, ink `--n-600`
  (7.22:1 on band — was `--text-lo` on band at an unverified value).
- `td` 13px → `--fs-dense` 13px/1.45, ink `--n-800`; padding →
  `var(--pad-cell-y) var(--pad-cell-x)`.
- `.cell-id` → `--red-600`.
- `.cell-mute` → `--n-500`. `.cell-strong` → 600 not 700.
- `tbody tr:hover td` → `--n-50`.
- `max-height:min(64vh,640px)` → `min(68vh,720px)`.

**Badges** (`.bdg`, `.bg-*`)
- `padding:4px 10px` → `var(--sp-1) var(--sp-3)`; 11px/700 → `--fs-micro` 600.
- Retint all six against §2.3 verified tint/deep pairs.
- `.bg-brand` → `--red-50` bg, `--red-700` ink (6.16:1).

**Buttons** (`.btn`, `.btn-primary|outline|ghost|danger|success`, `.btn-sm`, `.aicon`)
- `.btn` `padding:10px var(--s5)` → `var(--pad-btn-y) var(--pad-btn-x)`;
  14px/600 → `--fs-body` 14px/600; `--r-sm` 8px; `min-height:--h-control`.
- `.btn-primary` gradient+glow → **flat `--red-600`, `--e1`**;
  hover `--red-700`; active `--red-800`. No coloured shadow.
- `.btn-outline` hover → `--red-600` border/ink, `--red-50` bg.
- `.btn-danger` → `--danger` `#A51D2F`, hover `#821725`.
- `.btn-success` → `--success` `#1C8252`.
- `.aicon` 32px → `--h-control` 40px on desktop rows, `--r-xs`.
- `.form-actions` `margin-top:var(--s5)` → `--gap-section`.

**Forms** (`.fg`, `.fr`, inputs, `select`, `.srch`, `.fset`, `.up-*`, `.emoji-*`)
- `.fr label` 11px/700/+0.6px/uppercase `--text-mute` (**3.33:1, fails**) →
  `--fs-micro` 11px/600/+0.05em, ink **`--n-600`** (7.94:1).
- inputs `padding:12px 14px` → `var(--pad-input-y) var(--pad-input-x)`;
  14px → `--fs-body`; `--r-sm`; `min-height:--h-control`.
- focus ring `0 0 0 3px var(--red-50)` → `0 0 0 3px rgba(227,13,59,.16)` +
  `--red-600` border. Tint-as-ring was invisible on the old near-white bg.
- `select` chevron stroke `%236B6459` → `%235C4D54`; dark `%23A49E92` →
  `%23D6CCD0`.
- `.fset` bg `--bg` → `--n-50`; `.fset-title` 11px/800 → `--fs-micro` 600.
- `.fr-hint` 11.5px → `--fs-caption` 12px, `--n-500`.
- `.up-drop` `min-height:104px` → `112px`; hover `--red-50` + `--red-500` border.
- `.emoji-opt` `--r-xs`; selected → `--red-500` border, `--red-50` bg.

**Tabs / segmented / period** (`.tabs`, `.tab`, `.pbs`, `.pb`)
- `.tabs` track `--n-100`, border `--n-200`, `--r-md`, `padding:var(--sp-1)`.
- `.tab` `padding:8px 16px` → `var(--sp-2) var(--sp-4)`; 13px/600 →
  `--fs-dense` 13px/500; ink `--n-600`.
- `.tab.active` → `--n-0` pill, ink `--red-600`, weight 600 (not 700), `--e1`.
- `.tab b` count: inactive `--n-200`/`--n-600`; active `--red-50`/`--red-700`.
- `.pb.active` flat `--red-600` + white — already flat, just retint.

**Toggle** (`.tgl`, `.ts`) — 44×25 → **44×24** (even). Off `--n-300`;
on **flat `--red-600`**, no `--glow`. Knob 19px → 18px, travel 19px → 20px.

**Side panel** (`.spanel`, `.sp-*`)
- `.sp-hd-title` 19px/800 → `--fs-h3` 20px Jakarta 700.
- `.sp-hd-sub` 11px/700 → `--fs-micro` 600 `--n-500`.
- `.sp-sec-title` → `--fs-micro` 600 `--n-600`.
- `.sp-lbl` 13px `--text-lo` → `--fs-dense` `--n-600`; `.sp-val` → `--n-800` 500.
- `.sp-val.money` 19px/800 `--brand` → `--fs-h3` 20px Jakarta 700 `--red-600`.
- `.sp-avatar` gradient+glow → **flat `--red-600`**, no shadow; 60px, 22px→20px.
- `.sf-*` stepper: `--ocean-500` → `--success`; `.sf-lbl` 9px → `--fs-micro` 11px.

**Modals** (`.mbg`, `.mbox`, `.m-title`, `.m-body`, `.m-ico`, `.m-actions`)
- `.mbox` `--r-lg` 14px, `padding:var(--sp-6)`, `--e4`.
- `.m-title` 20px/800 → `--fs-h3` 20px Jakarta 700.
- `.m-body` 14px `--text-lo` → `--fs-body` `--n-600`, line-height 1.5.
- `.m-ico` 52px → 48px, `--r-md`.

**Toasts** (`.toast`) — `--r-sm`; `.toast-msg` 13.5px → `--fs-dense` 13px/400,
`--n-800`; left rails → §2.3 semantics.

**Skeletons / empty states** — `.sk` base `--n-200`, shimmer
`rgba(255,255,255,.75)`. `.empty-title` 16px/800 → `--fs-title` 17px/600;
`.empty-copy` 13.5px → `--fs-body` 14px `--n-600`; `.empty svg` 150px → 128px.

### 5.1 Login *(Agent A)*
- `#login-page` scope overrides: repoint every pinned hex to the new tokens
  (`--brand: --red-600`, `--red-50: #FFF0F3`, `--danger: #A51D2F`, neutrals to
  `--n-*`). Keep the card authored light in both themes — that reasoning holds.
- Canvas: `background-color:#131110` → `--n-950` `#140F12`. Grid hairline
  `rgba(245,242,236,.038)` → `rgba(251,249,249,.04)`.
- `::before` bloom: restate on the new red —
  `rgba(247,43,84,.40)` → `rgba(227,13,59,.16)` → `rgba(137,11,40,.05)` → 0.
- `.lc` `--r-lg` 14px, `padding:var(--sp-7) var(--sp-7) var(--sp-6)`, `--e4`.
- `.lc::before` hairline: `--grad-sunset` → **flat `--red-500`**, 3px → `--sp-half`.
- `.lc-title` 26px/800 → `--fs-h2` 24px Jakarta 700.
- `.lc-lede` 15px `--ink-500` → `--fs-body-lg` 15px `--n-600`.
- `.lc-eyebrow` → `--fs-micro` 600 `--n-500`.
- `.lf label` → `--fs-micro` 600 `--n-600`.
- `.lf-box` `--r-sm` 8px; focus → `--red-600` + `rgba(227,13,59,.16)` ring.
  Keep the padding-compensation trick — it prevents a 0.5px jump.
- `.btn.lc-cta` 50px → `--h-control-lg` 48px, `--r-sm`, 16px Jakarta **600**.
- `#l-err` → `--danger-tint` bg, `#821725` ink, `--danger` inset rail.
- `.l-foot` → `--fs-caption` 12px `--n-500`.

### 5.2 Dashboard *(A + B + E)*
- 4× `.sc` stat cards. `--r-md`; `padding:var(--pad-card)` with the left rail
  inset via `padding-left:var(--sp-6)`.
- `.sc::before` rail gradient → **flat**: default `--red-500`;
  `.ac-gold`→`--warning`, `.ac-ocean`→`--info`, `.ac-success`→`--success`.
  Width 4px → `--sp-1`.
- `.sc-chip` 40px `--r-sm`, `--red-50` bg / `--red-700` ink; tone variants to
  the §2.3 tint/deep pairs.
- `.sc-lbl` 11px/700/+0.8px `--text-mute` (**3.33:1**) → `--fs-micro` 600
  +0.05em **`--n-500`** (5.27:1).
- `.sc-val` 28px/800/−0.6px → `--fs-stat` 26px Jakarta **700** −0.02em.
  `.sc-val.sm` 23px → 22px.
- `.sc-sub` 12px → `--fs-caption` `--n-500`.
- `.sg` gap `--s4` → `--gap-field` 16px; `margin-bottom` → `--gap-section`.
- `sparkline()` in `app.js` — callers pass `#C8102E`/`#E1495F`; change to
  `--red-500` `#F72B54`, area gradient opacity `.28` → `.20`.
- "Recent Orders" card + 7-col table → shared table rules.

### 5.3 Orders *(B + E)*
- `.tabs` filter bar + `.srch` + 9-col table.
- `.srch` `--r-md`, `padding:var(--pad-input-y) var(--pad-input-x)`,
  `--fs-body`; focus ring per §5.0.
- `badge(s)` / `typeBadge(t)` in `app.js` — audit the status→class map so every
  order status lands on a §2.3 pair. Cancelled must read `--danger`, not brand.
- `.cell-actions` gap `6px` → `--gap-tight` 4px… use `--sp-2` 8px for 40px
  targets.
- Order side panel: `.sf` stepper + `.sp-proof` (`--r-md`, `--n-200` border).

### 5.4 Drivers *(B + D + E)*
- `.sg` stats (JS `statCard()`), 9-col roster, `.tgl` per row.
- `#modal-driver`: two `.fset` groups, `.inline-field` + Generate,
  `.fr-hint`×4, `.cred-box` handover.
- `.cred-row span` 10.5px/800 → `--fs-micro` 600; `.cred-row b` 13px mono →
  `--fs-dense`.
- Rating `.stars` → `--star: #E8A317`; `.off` → `--n-300`.
- Remove `style="margin-top:10px"` (line 726) → class.

### 5.5 Merchants *(B + D + E)*
- 3-up `.sg`, 9-col table, `.cat-ico` + `.thumb` in `.cell-media`.
- `.cat-ico` tints → `c-food` red-50/red-700, `c-grocery` success,
  `c-pharmacy` info, `c-packages` warning, `c-other` `--n-100`/`--n-600`.
- `#modal-merchant`: 3× `.fset`, `.emoji-picker`, `#m-image-drop` uploader,
  `.up-preview`/`.up-progress`/`.up-bar-fill` (→ `--red-600`).
- `.mi-form` / `.mi-card` / `.mi-price` (→ `--red-600`) menu editor.

### 5.6 Customers *(B + E)*
- 3-up `.sg`, `.srch`, `#customers-cap` notice, 7-col table.
- `tr.row-muted` opacity .55 → **.6** plus the explicit Disabled badge.
- `.notice` → `--warning-tint` bg, `#AD640B` ink (4.15:1), `--r-sm`,
  `padding:var(--sp-3) var(--sp-4)`, `--fs-caption`.

### 5.7 Shop & Deliver *(B + E)*
- 3-up `.sg`, 7-filter `.tabs`, `.srch`, 9-col table.
- `inquiryBadge(s)` → §2.3 pairs.
- Longest page title in the panel — verify the retargeted `clamp()` at 390px.

### 5.8 Notifications *(A + C + D)*
- `.nl` 2-col grid, gap → `--gap-section`.
- Compose card: `.notice` warning, `select`, 2 fields, `textarea`,
  `.form-actions`.
- `.phone-mock` — `#141310` → `--n-950`; `border-radius:38px` → 36px;
  `.ph-screen` 26px → 24px, bg `--n-50`.
- `.ph-badge` gradient → **flat `--red-600`**, `--r-xs`.
- `.ph-app` `#86091E` → `--red-700` `#B60C31`; `.ph-title` 13px Jakarta 700 →
  600; `.ph-msg` 11px → `--fs-caption` 12px `--n-600`.
- `.ph-filler div` `#ECEAE6` → `--n-200`.
- `.nh-item` history rows: `.nh-ico` → `--red-50`/`--red-700`;
  `.nh-title` 13.5px → `--fs-dense`; `.nh-meta` 12px → `--fs-caption` `--n-500`.

### 5.9 Promo Codes *(C + D)*
- `.pl` 2-col; create form `.mg` 6 fields + date + `.form-actions`; 7-col table.
- `.pc-prev` — **keeps its gradient** (§2.9). Restate on the new red:
  `linear-gradient(135deg,#F72B54 0%,#E30D3B 55%,#B60C31 100%)`. `--r-lg` 14px.
- `.pc-code` 30px/800/+4px → `--fs-h1` 30px Jakarta 700 +2px tracking.
- `.pc-disc` 15px → `--fs-body-lg`; `.pc-valid`/`.pc-foot` → `--fs-caption`,
  opacity → explicit `rgba(255,255,255,.78)` / `.56`.
- `.helper` → `--n-50` bg, `--n-200` border, `--fs-caption`; `b` → `--fs-micro`
  600 `--n-500`.
- `.usage-track` → `--n-200`; fills → §2.3.
- Remove `style="text-transform:uppercase"` (line 459) → class.

### 5.10 Analytics *(C + E)*
- `.pbs` period selector in `.pg-hdr`; 4× `.sg`; `.ag` 2×2 card grid.
- `#barGrad` / `#barGradMax` defs in `app.js` → flat `--red-500` / `--red-600`
  fills (drop the gradient entirely; `rx:5` → `rx:6`).
- `.bar-lbl` 11px `--text-mute` → `--n-500`; `.bar-val` 11px/700 →
  `--fs-micro` 600 `--n-800`.
- `.chart .grid-line` → `--n-200`. `.chart` height 190px → 192px (grid).
- `.chart-tip` → `--n-900` bg, `--n-50` ink, `--r-xs`, `--fs-caption`.
- `.zr`/`.zn`/`.zt`/`.zf` zone bars: `.zf` gradient → flat `--red-500`;
  `.zn` 13px → `--fs-dense` `--n-800`; `.zt` track → `--n-200`.
- `.prow`/`.ptrack`/`.pfill` payment split: `.pfill.brand` → flat `--red-500`,
  `.pfill.gold` → `--warning`.
- `#top-merch` table — note it is a bare `<table>` with **no `.tbl-wrap`**, so
  it has no sticky header and no mobile card fold. Wrap it.

### 5.11 Settings *(C + D)*
- `.ag` 2-col: Package Delivery + Danger Zone.
- Pricing form: `textarea#pr-bands`, `#pr-preview`, 2× `.mg`, `.form-actions`.
- Replace 4 inline `style="max-width:none…"` (lines 551, 562, 595, 658) with a
  `.prose` class — `max-width:none`, `--fs-body`, `--n-600`, line-height 1.55.
- `code` element has **no styling at all** — add: `--n-100` bg, `--r-xs`,
  `2px 6px`, `--fs-caption`, mono, `--n-700`.
- Danger Zone per §5.0. `#modal-wipe`: remove inline styles on lines 653/658.

---

## 6. Agent briefs — Phase 2

Every agent: read §2 first, take values verbatim, touch only your file, do not
change behaviour or DOM structure unless your brief says so, and leave the
Phase-1 aliases alone.

**Agent A — Shell** (`css/shell.css`)
§5.0 sidebar/topbar/bell/page-wrapper/side-panel/modals/toasts + §5.1 login +
§5.8 layout. Watch: the login scope pins themed tokens deliberately — repoint
them, don't delete them.

**Agent B — Components** (`css/components.css`)
§5.0 cards/tables/badges/buttons/forms/tabs/toggle/skeletons/empty +
the shared surfaces behind §5.2–5.7. This is the highest-leverage file.
Watch: `.card-title ~ .tbl-wrap` corner-squaring selectors must keep working
after the radius change; `.btn.lc-cta` specificity exists because the BUTTONS
block would otherwise win on source order — that ordering now spans two files,
so verify it still holds.

**Agent C — Pages** (`css/pages.css`)
§5.8 phone mock, §5.9 promo preview + helper + usage, §5.10 charts/bars,
§5.11 prose + `code`, category icons, menu-item cards, emoji picker, notices.

**Agent D — Markup** (`index.html`)
- `theme-color` → `#E30D3B`.
- Remove all 8 inline `style=` attributes → classes (lines 459, 551, 562, 595,
  653, 658, 722, 726). Keep the two `.ph-filler` widths — those are data.
- Wrap `#top-merch` in `.tbl-wrap`.
- `.pg-title` is an `<h1>` on all 10 pages — correct; leave the tags.
- Do **not** restructure pages or rename ids: `app.js` binds to them.

**Agent E — Rendered** (`app.js`)
- 10 hardcoded hex → tokens: `#C8102E`, `#E1495F`, `#FFF1F3`, `#FFE0E5`,
  `#F7B9C2`, `#FF6A3D`, `#F5A524`, `#E11D34`. (`#add`, `#ABCD1234` are not
  colours — leave them.)
- `sparkline()` colour + area opacity (§5.2).
- `#barGrad`/`#barGradMax` → flat fills (§5.10).
- `statCard()`, `badge()`, `typeBadge()`, `inquiryBadge()` → verified class pairs.
- 5 inline `font-size` in generated markup → classes.
- Prefer `getComputedStyle` on a token or a CSS class over any literal, so the
  dark theme follows automatically.

---

## 7. Verification gates

Nothing merges until all pass.

1. **Grep gates** — Phase 4 step 2 list returns zero hits.
2. **Contrast** — §9 script over the final `tokens.css`; every text pair ≥4.5:1,
   primary ink 12.5–14.5:1.
3. **Type** — no size outside §2.5; no `font-weight:800`; no half-pixel sizes.
4. **Spacing** — no banned raw px in padding/margin/gap.
5. **Manual** — 10 pages × light+dark × 390/900/1440px. Login, both modals,
   side panel, confirm dialog, wipe dialog, toasts, empty states, skeletons.
6. **Behaviour unchanged** — `[hidden]` still wins, mobile table rows still
   collapse, sticky headers still stick, autofill still holds the field.

---

## 8. Deliberate non-goals

- No copy changes, no layout restructuring, no new features.
- No font-family change — the pairing is sound and the files already ship.
- Customer and driver apps are out of scope. The token names here are chosen to
  port later, but that is a separate piece of work.

---

## 9. Reproducing the numbers

```python
import colorsys
def rgb(x): x=x.lstrip('#'); return tuple(int(x[i:i+2],16) for i in (0,2,4))
def lum(hx):
    f=lambda c:(c/255)/12.92 if c/255<=.03928 else (((c/255)+.055)/1.055)**2.4
    r,g,b=rgb(hx); return .2126*f(r)+.7152*f(g)+.0722*f(b)
def cr(a,b):
    l1,l2=lum(a),lum(b); hi,lo=max(l1,l2),min(l1,l2); return round((hi+.05)/(lo+.05),2)
def hsl(hx):
    r,g,b=[v/255 for v in rgb(hx)]; h,l,s=colorsys.rgb_to_hls(r,g,b)
    return (round(h*360),round(s*100),round(l*100))
```

Brand extraction: `PIL.Image.open('assets/icon.png').convert('RGBA')`, count
opaque pixels, take the mode.
