# ShipEast — Design Elevation Plan (60% → 100%)

**Author:** Design + Engineering lead (acting)
**Date:** 2026-07-20
**Applies to:** `customer_app` (Flutter), `driver_app` (Flutter), `admin_panel` (vanilla HTML/CSS/JS)
**Companion docs:** `full-audit-customer.md`, `full-audit-driver.md`, `full-audit-admin.md`

---

## 0. The thesis — why we look like a prototype, and how we fix it

Functionally the three apps are ~90% wired. **Visually they read as a v1 prototype**, and the audits confirm why:

- One flat brand red (`#C8102E`) painted on everything — buttons, headers, chips, icons — with no ramp, no depth, no gradient. Flat red on flat white = "template."
- Four fonts fighting each other (Montserrat Black, Nunito, Inter, Dancing Script) with **styles re-declared inline in every screen** — no single source of truth.
- **Emoji used as icons** in the admin panel; generic stock `Icons.*` in Flutter. This is the single biggest "prototype tell."
- Fake, hand-painted maps and confetti; hardcoded ETAs; `alert()`/`confirm()` dialogs; text-spinner loaders; snackbars instead of toasts.
- No elevation system, no motion system, no skeletons, no empty-state art, no dark mode.

**FoodPanda / Uber Eats / Bolt feel "real" because of a small number of things done consistently:** a disciplined color *ramp* + one signature gradient, a two-font system on a strict scale, a single premium icon family, layered soft shadows, real maps, and motion that responds to every touch. This plan installs exactly those, as **one shared design language ("ShipEast Design System" — SEDS)** expressed natively in each app.

**Guardrail from the client:** red `#C8102E` stays the primary. Where flat red fails contrast or feels cheap, we use an **approved red-family gradient** (never a random new hue) — realism first.

### Design principles (the bar for every screen)
1. **Depth over flatness** — every surface sits on a defined elevation tier; primary actions glow.
2. **One accent, spent well** — red leads; gold (ratings/premium) and ocean-teal (live/tracking/info) are the *only* supporting hues, used sparingly.
3. **Motion confirms every touch** — nothing changes state without a transition; 60fps, reduced-motion-safe.
4. **Real over decorative** — real maps, real icons, real skeletons. Kill the fakes.
5. **Consistency is the product** — the same button, card, and chip everywhere, from one token file.

---

## 1. ShipEast Design System (SEDS) — the shared foundation

This is the canonical spec. Sections 2–4 apply it per app. All values are final decisions.

### 1.1 Brand & logo
- **Wordmark:** `Ship` in ink-900 + `East` in brand red, single weight, custom logotype (retire the Dancing Script script look from all UI — it reads as a placeholder). Tagline lockup: "Couriers & Bearer Services · Jamaica" in a caption style.
- **App icon / splash:** deliver a proper adaptive icon on the **Ember gradient** (see 1.2) with a mark derived from a stylized parcel + motion streak. Splash = gradient ground, centered mark, single hairline progress. No stock motorcycle CustomPaint.

### 1.2 Color system

**Primary red ramp** (replaces the single `#C8102E`):

| Token | Hex | Use |
|---|---|---|
| `red/50` | `#FFF1F3` | tint backgrounds, selected chip fill |
| `red/100` | `#FFE0E5` | hover tint, badges |
| `red/200` | `#F7B9C2` | disabled-on-tint |
| `red/300` | `#EE8492` | subtle accents |
| `red/400` | `#E1495F` | gradient lift, focus rings on dark |
| `red/500` | `#C8102E` | **brand core** (unchanged) |
| `red/600` | `#A80D26` | pressed / hover on solid |
| `red/700` | `#86091E` | text-on-tint, deep |
| `red/800` | `#5F0615` | gradient tail |
| `red/900` | `#3D0410` | on-dark surfaces |

**Signature gradients** (the "realism" upgrade — use for heroes, primary CTAs, FAB, splash):
- **Ember** (default brand gradient): `linear-gradient(135deg, #E11D34 0%, #C8102E 52%, #9A0B22 100%)`
- **Sunset** (energy moments: order confirmed, promo, driver-earnings win): `linear-gradient(135deg, #FF6A3D 0%, #E11D34 55%, #C8102E 100%)` — the warm coral lift gives contrast and "speed/heat" without leaving the red family.
- **Ink scrim** (over photos/maps for legibility): `linear-gradient(180deg, rgba(20,18,15,0) 0%, rgba(20,18,15,.72) 100%)`

**Supporting hues** (the *only* two — used sparingly, never as a second brand color):
| Token | Hex | Use |
|---|---|---|
| `gold/500` | `#F5A524` | rating stars, "premium", earnings highlight |
| `gold/tint` | `#FEF3E2` | gold chip fill |
| `ocean/500` | `#0E9488` | live tracking, map route line, info state, links where red clashes |
| `ocean/tint` | `#E5F6F4` | info chip fill |

**Semantic:**
| Token | Hex | Tint |
|---|---|---|
| success | `#16A34A` | `#E6F6EC` |
| warning | `#F59E0B` | `#FEF3E2` |
| danger | `#D92D20` | `#FDECEA` |
| info | `#0E9488` | `#E5F6F4` |

> Note: destructive `danger` (`#D92D20`, orange-red) is deliberately distinct from brand `red/500` (`#C8102E`, crimson) so "delete" never reads as "brand."

**Neutrals — warm-biased** (a chosen off-white/ink, not cold `#F5F5F7`; reads premium):
| Token | Hex | Use |
|---|---|---|
| `ink/900` | `#1C1A17` | primary text, near-black surfaces |
| `ink/700` | `#3A362F` | headings on light |
| `ink/500` | `#6B6459` | secondary text |
| `ink/400` | `#938C7F` | placeholder, disabled text |
| `ink/300` | `#C7C0B4` | icons-muted |
| `ink/200` | `#E4E0D9` | dividers/borders |
| `ink/100` | `#ECEAE6` | strong divider |
| `surface/50` | `#FAF9F7` | app background (warm paper) |
| `surface/0` | `#FFFFFF` | cards |

**Dark theme tokens** (ship as a defined layer — top-tier apps have it; phase after core):
| Role | Light | Dark |
|---|---|---|
| bg | `#FAF9F7` | `#141310` |
| card | `#FFFFFF` | `#201E1A` |
| card-raised | `#FFFFFF` | `#2A2823` |
| text-hi | `#1C1A17` | `#F5F2EC` |
| text-lo | `#6B6459` | `#A49E92` |
| border | `#E4E0D9` | `#33302A` |
| brand-on-dark | `#C8102E` | `#F04A5E` (lift for contrast/AA) |

**Contrast rule:** any red text/icon on a light tint uses `red/700`; red on white for body text is avoided (use `ink` + red only for interactive). All text pairs must pass WCAG AA (4.5:1 body, 3:1 large).

### 1.3 Typography

**Decision: consolidate 4 families → 2.** Retire Montserrat, Nunito, Dancing Script.
- **Display / UI:** **Plus Jakarta Sans** (geometric-humanist, premium, friendly — de-genericizes from Montserrat). Weights 800/700/600.
- **Body / data:** **Inter** (proven legibility at small sizes; pairs cleanly with Jakarta). Weights 400/500/600 + `tabular-nums` for all prices, stats, timers.
- Flutter: `GoogleFonts.plusJakartaSans*` + `GoogleFonts.inter*`. Web: `@font-face` self-host (don't rely on the CDN silently failing).

**Type scale** (mobile-first; line-height in parens):
| Role | Size/LH | Weight | Family |
|---|---|---|---|
| Display | 32 / 38 | 800 | Jakarta |
| H1 | 26 / 32 | 700 | Jakarta |
| H2 | 22 / 28 | 700 | Jakarta |
| H3 | 18 / 24 | 700 | Jakarta |
| Title | 16 / 22 | 600 | Jakarta |
| Body | 15 / 22 | 400 | Inter |
| Body-S | 13 / 18 | 400 | Inter |
| Label | 12 / 16 | 600 | Inter, +0.4 tracking |
| Eyebrow | 11 / 14 | 700 | Inter, +0.8 tracking, UPPERCASE |

Headings get `text-wrap: balance` (web) / `softWrap` tuned (Flutter). Base body bumps **14 → 15** for a premium reading feel. Prices/timers always `tabular-nums`.

### 1.4 Spacing, radius, elevation

**Spacing** — strict 4pt grid: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`. Screen gutter = 20. Card padding = 16–20. No off-grid values.

**Radius** — standardize the current 11–14 chaos:
`xs 8` (small chips) · `sm 12` (inputs, list rows) · `md 16` (cards) · `lg 20` (large cards, sheets) · `xl 28` (hero, bottom-sheet top) · `full 999` (pills, avatars, FAB).

**Elevation** — layered, warm-tinted shadows (never single flat `0 1px 6px black`):
| Tier | Shadow | Use |
|---|---|---|
| e0 | none + `1px` `ink/200` border | flat list rows, inputs |
| e1 | `0 1px 2px rgba(28,26,23,.04), 0 2px 6px rgba(28,26,23,.06)` | resting cards |
| e2 | `0 4px 12px rgba(28,26,23,.08), 0 2px 4px rgba(28,26,23,.05)` | raised cards, dropdowns |
| e3 | `0 10px 28px rgba(28,26,23,.12)` | bottom sheets, FAB, popovers |
| e4 | `0 20px 48px rgba(28,26,23,.18)` | modals |
| glow | `0 8px 22px rgba(200,16,46,.30)` | **primary CTA / FAB** (makes red float — key premium cue) |

### 1.5 Iconography — the biggest single upgrade

**Decision: one icon family everywhere = Phosphor Icons** (rounded, friendly, distinctive, MIT).
- Flutter: `phosphor_flutter` package. Regular weight default; **Fill** variant for active nav/selected states. 24px standard, 20px inline, 28px feature. Stroke color = `ink/500` inactive, `red/500` / gradient active.
- Web (admin): inline **Phosphor SVG sprite** (`<symbol>` set). **Delete every emoji icon.** 1.75px stroke, `currentColor`.
- Category glyphs (Food/Grocery/Pharmacy/Packages) get **custom duotone treatment** on soft-tinted circular chips (56px): tint fill from a per-category hue, glyph in the deep tone. Category hues: Food `red`, Grocery `success`, Pharmacy `ocean`, Packages `gold`.

### 1.6 Illustration & imagery

- **Empty states, onboarding, success, errors:** one cohesive **flat-geometric SVG set**, 2-tone (red/coral + cream ground) with a subtle grain, ~200×200 dp. No more one-off `CustomPaint`. (Asset list in §7.)
- **Merchant / food imagery:** enforce `16:9` hero + `1:1` thumb, `cached_network_image` with a **branded blur-up placeholder** (tinted shimmer, not gray box) and a gradient+glyph fallback when a URL is missing.
- **Scrims:** every image with text over it gets the **Ink scrim** for legibility.
- **Photography direction (for merchant onboarding guidance):** warm, top-down or 45°, real food, consistent crop.

### 1.7 Motion system (the "smoothness")

**Durations:** `instant 100` · `fast 180` · `base 240` · `slow 360` · `deliberate 520` (ms).
**Easing:** standard `cubic-bezier(.2,0,0,1)` (emphasized) · decelerate `cubic-bezier(0,0,0,1)` (enter) · accelerate `cubic-bezier(.4,0,1,1)` (exit) · spring for interactive controls.

**Standard interactions (apply globally):**
- **Button/card press:** scale `0.97` + shadow drop, 100ms; release spring-back.
- **List entrance:** fade + 12dp slide-up, 40ms stagger (Flutter: `flutter_animate`; web: IntersectionObserver + CSS).
- **Page transitions:** shared-axis (X for lateral, Z for drill-in) / fade-through for tab switch.
- **Skeletons:** shimmer sweep (replace ALL text spinners + gray boxes). 1200ms loop.
- **Toasts:** slide-in from top with icon + color rail (replace snackbars AND `alert()`/`confirm()`).
- **Numbers:** count-up on stat cards / earnings (600ms decelerate).
- **Status stepper:** animated fill between steps + pulsing "current" node.
- **Pull-to-refresh:** branded custom indicator (parcel spinner).
- Respect `prefers-reduced-motion` / platform "reduce motion": disable transforms, keep opacity only.

---

## 2. Customer app (`customer_app`) — plan

**Current:** `lib/theme/app_theme.dart` is 16 lines (colors + bare `ColorScheme.fromSeed`); every screen re-declares `GoogleFonts.*`, button styles, and `BoxDecoration` inline (audit §6). Light-only. Fake map, hardcoded ETAs, snackbar favourites.

### 2.1 Foundation refactor (do first — unblocks everything)
Create a real token + component layer:
```
lib/theme/
  ├── se_colors.dart      // full ramps, gradients, semantic, neutrals, dark
  ├── se_typography.dart  // Jakarta+Inter text styles on the scale
  ├── se_spacing.dart     // spacing/radius/elevation constants
  ├── se_theme.dart       // ThemeData (light + dark) built from the above
  └── se_motion.dart      // durations, curves
lib/widgets/
  ├── se_button.dart      // Primary (gradient+glow), Secondary, Ghost, Destructive
  ├── se_card.dart        // elevation-aware card
  ├── se_chip.dart        // pill / category chip
  ├── se_text_field.dart  // unified input (16 radius, focus ring)
  ├── se_app_bar.dart     // two header variants (gradient hero / white+back)
  ├── se_bottom_sheet.dart
  ├── se_toast.dart       // replaces all snackbars
  ├── se_skeleton.dart    // upgrade ShimmerBox → tinted, shaped skeletons
  ├── se_empty_state.dart // SVG + copy + CTA
  └── se_stat_tile.dart
```
Then **delete all inline style duplication** screen-by-screen, replacing with the widgets above. This is the highest-ROI task and the audit's #1 debt.

Add deps: `phosphor_flutter`, `flutter_animate`, `flutter_svg`, `google_maps_flutter` (or `mapbox_maps_flutter`), `shimmer` (or hand-rolled).

### 2.2 Screen-by-screen upgrades
- **Splash / Welcome:** Ember-gradient ground, real animated wordmark, retire the CustomPaint motorcycle → adopt the branded onboarding SVG. Hairline progress. Make Terms/Privacy actually tappable.
- **Login / Register:** unified `se_text_field` (16dp radius, focus ring, inline validation states), gradient primary button with glow, real social-button styling. Give "Forgot password" and Google real states (functional wiring is in the audits' P1, but style them properly now).
- **Home:** the flagship. Ember-gradient header with layered depth (avatar ring, greeting on scrim). Replace the fake search bar with a real tappable pill that has an icon + subtle inner shadow. **Category chips → 56dp duotone SVG tiles** (per-category hue). Merchant cards: 16:9 hero, blur-up placeholder, rating pill (gold star), delivery-time + fee chips, favourite heart with **real fill toggle + haptic**. Section headers with working "See all". Skeletons on load, staggered entrance.
- **Search:** live results with the same merchant card; add menu-item results; empty/no-result states use SVG art.
- **Merchant menu:** parallax hero + ink scrim, sticky category tabs, item cards with qty steppers that animate, floating cart bar (gradient + glow) that slides up with count + total, "start new order" as `se_bottom_sheet`.
- **Cart / Checkout:** clean summary card with tabular prices, animated qty, address selector as radio cards with selected-state ring; wire special instructions visibly.
- **Payment:** method rows with real brand marks, promo field with success/gold animation, total card, place-order → confirm bottom sheet with gradient CTA.
- **Order confirmed:** keep confetti but **refine** (physics + brand colors), Sunset-gradient success header, animated checkmark, order chip, real ETA (computed), track CTA.
- **Order status:** **replace the fake `_MapGridPainter` with a real map** (custom red/cream style JSON, live driver marker + route via `ocean/500` polyline). Animated status stepper. Driver card with call button that actually dials (`tel:`). Honest ETA from data.
- **Order history:** filter tabs as segmented control, order cards with status badges (semantic tints), empty-state art per tab.
- **Profile:** gradient header, avatar with edit ring, stat tiles (count-up), menu list with Phosphor icons + chevrons, sign-out as destructive-ghost.
- **Notifications / Help / Privacy / Saved addresses / Coming soon:** apply the shared header + card + empty-state + toast system uniformly; fix the stale "Version 1.0.0" (single source).

---

## 3. Driver app (`driver_app`) — plan

**Current:** `lib/app_theme.dart` already richer (has heading/body/button styles + input decoration) but Material 2 (`useMaterial3:false`), Montserrat Black + Nunito, flat cards, custom bar chart, `_showComingSoon` dialogs, no map. This app is the closest to the system already — mostly a re-skin + tokenization.

### 3.1 Foundation
- Migrate `app_theme.dart` to the SEDS token structure (mirror the customer app's `se_*` files so the two Flutter apps share **identical** tokens — copy the files verbatim; consider a shared package `packages/se_design` later).
- Switch to **Material 3** (`useMaterial3:true`) for modern component defaults; re-verify the custom widgets.
- Swap Montserrat/Nunito → Jakarta/Inter. Adopt Phosphor icons. Add `flutter_animate`, `flutter_svg`, maps.

### 3.2 Screen upgrades
- **Dashboard:** Ember-gradient header, the **online/offline toggle becomes a hero control** (large, satisfying spring + haptic + color/gradient shift, status text morphs ONLINE↔OFFLINE↔DELIVERING). Stats strip → `se_stat_tile` with count-up. Active-order card raised (e2) with route line. Quick actions as Phosphor tiles.
- **New order (incoming):** full-bleed **Sunset gradient** urgency screen; the 60s ring becomes a smooth sweeping conic countdown that shifts amber→danger; large Accept (gradient+glow) / Reject; pickup→delivery route mini-map preview.
- **Pickup / Delivery confirmation:** animated step banners, itemized cards, the **photo picker as a polished camera tile** with preview + retake; delivery note field; "Mark delivered" → success sheet with **count-up earnings** on Sunset gradient.
- **History:** segmented tabs, order cards with commission vs total (tabular), semantic status badges, empty-state art (esp. the always-empty "Cancelled" tab).
- **Earnings:** rebuild the `_BarChartPainter` chart to design-grade (area-fill option, faint grid, emphasized max bar, gold accent, count-up totals, tab cross-fade). Payout card styled as a real "next payout" ledger card (label honesty per audit).
- **Profile:** gradient header, avatar edit ring, real stat tiles. Replace the bogus completion metric visually with a real "Rating" ring + trips. Coming-soon dialogs → styled `se_empty_state` sheets.
- **Pending approval:** animate the 3-step tracker; (functional live-status listener is in the audit P1 — style it as an animated progress that advances on approval).

---

## 4. Admin panel (`admin_panel`) — plan

**Current:** single 1,566-line `index.html`, vanilla, competent but "v1 baseline" (audit §6): flat white cards w/ 3px red top-border, **emoji icons**, CSS-bar charts, text-spinner loaders, `alert()`/`confirm()`, no dark mode. This is where the "prototype" read is strongest for a back-office.

### 4.1 Foundation
- Add a proper `:root` **token block** matching SEDS (ramps, gradients, semantic, neutrals, spacing, radius, elevation, motion vars) + a `[data-theme="dark"]` override. Style everything through vars.
- Self-host **Plus Jakarta Sans + Inter** via `@font-face` (stop depending on the Google CDN silently).
- Add an **inline Phosphor SVG `<symbol>` sprite**; replace **every emoji** with `<svg><use>`.
- Split the monolith is optional; at minimum extract `styles.css`, `app.js`, `icons.svg` for maintainability (no build step required).

### 4.2 Component & page upgrades
- **Login:** keep the ink→red radial ground but upgrade card to e4 + gradient submit button + Jakarta logotype.
- **Shell:** sidebar gets refined active state (gradient left-rail indicator + fill icon), smooth collapse, section labels. Topbar: real avatar, live date, theme toggle, breadcrumb.
- **Stat cards:** replace 3px top-border with a **left accent rail + tinted icon chip**, count-up values, `tabular-nums`, e1 → e2 on hover, mini-sparkline where a trend exists.
- **Tables:** sticky header, zebra-on-hover, semantic status pills, avatar cells, right-aligned tabular numbers, **skeleton rows** on load (replace the text spinner), and empty-state art per table.
- **Side panels / modals:** slide-in with scrim, e4, animated status-flow stepper (ocean fill).
- **Toasts:** build a toast system; **remove every `alert()`/`confirm()`** → styled confirm dialogs + success/error toasts.
- **Charts:** upgrade the hand-rolled CSS bars into a cohesive mini-chart language (rounded bars w/ gradient, faint gridline, hover tooltip, emphasized max, gold accent for revenue). Fix the **fabricated driver rating breakdown** to render real aggregates (or clearly label "sample" until data exists — audit §7.6).
- **Dark mode:** full token-driven dark theme for the whole panel (default off; toggle in topbar).
- **Notifications page:** phone-mock preview restyled; keep the honest "log — no push delivery yet" note visible (audit §5) until FCM lands.

---

## 5. Cross-cutting workstreams

1. **Real map** (customer order-status + driver route/new-order preview): pick `google_maps_flutter` or `mapbox_maps_flutter`, author a **custom style JSON** (warm cream land, muted roads, red POI, ocean-teal route). This kills the single most damaging fake in the product.
2. **Skeletons everywhere** — one shimmer primitive per platform; no more spinners or gray boxes.
3. **Toast/dialog system** — one per platform; retire snackbars and `alert/confirm`.
4. **Empty-state + illustration set** — shared SVG library used by all three apps.
5. **Icon migration** — Phosphor everywhere; emoji fully removed from admin.
6. **Dark mode** — token layer in all three; ship customer + admin first.

---

## 6. Phased delivery (sequenced for visible wins fast)

| Phase | Scope | Outcome |
|---|---|---|
| **P0 — Tokens & primitives** | SEDS token files (all 3 apps), fonts swapped, Phosphor installed, button/card/input/toast/skeleton primitives, elevation + motion constants | Instant consistency; everything downstream is a re-compose |
| **P1 — Hero surfaces** | Customer Home + Merchant + Order-status(real map); Driver Dashboard + New-order; Admin shell + tables + charts | The screens users see most look "real" |
| **P2 — Full sweep** | Every remaining screen re-composed onto primitives; empty states + skeletons + toasts everywhere; emoji purge | No prototype surfaces remain |
| **P3 — Depth** | Dark mode (customer + admin), refined motion (staggers, count-ups, page transitions), branded app icon/splash, pull-to-refresh | International-tier polish |
| **P4 — Illustration & imagery** | Full SVG illustration set, merchant image placeholders/scrims, category glyphs | Cohesive brand world |

Each phase is shippable. P0+P1 alone move the needle from "prototype" to "credible product."

---

## 7. Asset manifest (SVGs / graphics to produce)

**Shared illustrations (2-tone red/coral + cream):** onboarding-hero, empty-cart, empty-orders, empty-search, empty-notifications, no-connection/error, order-success, generic-empty.
**Category duotone glyphs:** food, grocery, pharmacy, packages.
**Icon set:** Phosphor (regular + fill) — no bespoke production needed beyond the category glyphs.
**Brand:** app icon (adaptive), splash mark, wordmark lockup, favicon (admin).
**Map:** custom map style JSON (warm/cream), driver marker, pickup/dropoff pins.
**Placeholders:** branded blur-up shimmer tile, merchant fallback (gradient + glyph).

---

## 8. Verification / acceptance checklist ("done" bar)

A screen passes only when:
- [ ] Every color comes from a SEDS token (no raw hex in screens).
- [ ] Only Jakarta + Inter render; prices/stats use `tabular-nums`.
- [ ] Every icon is Phosphor; **zero emoji** as UI icons (admin).
- [ ] Every surface uses a defined elevation tier; primary CTA has the red glow.
- [ ] Radius ∈ {8,12,16,20,28,full}; spacing on the 4pt grid.
- [ ] Loading = skeleton (never a bare spinner/gray box); empty = SVG + copy + CTA.
- [ ] Feedback = toast (never a raw snackbar / `alert` / `confirm`).
- [ ] Press/enter/exit motion present, 60fps, reduced-motion honored.
- [ ] No fake data surfaced as real (map, ETAs, rating breakdown) — either real or honestly labeled.
- [ ] AA contrast on all text; dark theme (where shipped) has equal care.
- [ ] Customer & driver Flutter apps share **identical** token values.

---

*This plan is design + system scope only; functional gaps (FCM, real map data wiring, acceptOrder transaction, security rules, etc.) are tracked in the three `full-audit-*.md` docs and referenced where they intersect the UI.*
