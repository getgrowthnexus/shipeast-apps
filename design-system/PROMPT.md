# Build Prompt

**How to use this:** fill in the brief below, then give Claude this file,
`DESIGN-SYSTEM.md`, and `derive_palette.py`. Say: *"Build this app. Follow
DESIGN-SYSTEM.md exactly."*

If you only remember one thing: **give Claude the primary colour and let it
derive the rest.** Handing over a full palette you picked yourself is the main
way this goes wrong — the palette in the spec works because every value is
computed from one hue, and a hand-picked set of colours won't be.

---

## Part 1 — The brief (fill this in)

```
APP_NAME:
WORDMARK_SPLIT:      (e.g. Ship|East — the second half renders in the accent
                      tone. Leave blank for a single-word name.)
LEGAL_NAME:          (as registered, for the signed-out lockup)
TAGLINE:             (one short line, under the wordmark)

PRIMARY:             #      ← REQUIRED. The one input the palette derives from.
SECONDARY:           #      ← optional. Becomes the informational tone.

PLATFORM:            Flutter (Android + iOS)   |  other:
BACKEND:             Firebase                  |  other:

WHAT THE APP DOES:
  (2–4 sentences. Who opens it, and what they are trying to get done.)

USER ROLES:
  (e.g. customer / driver / admin — one app each, or one app with role
   switching. Say which.)

SCREENS:
  (List them. Rough is fine — Claude will propose the rest.)

MUST-HAVE FEATURES:

EXPLICITLY OUT OF SCOPE:
```

---

## Part 2 — Instructions to Claude

You are building a mobile app for a client. `DESIGN-SYSTEM.md` is the design
system: a complete, brand-agnostic system extracted from a shipped product. It
is not a suggestion. Follow it exactly.

### The one rule that matters

**Derive the palette; do not invent colours.** §2 of the spec turns a single
hex into ~70 tokens through explicit HSL rules, with contrast gates. Run those
rules. Do not substitute your own taste for them at any point, and do not add a
colour that isn't in the derived set.

### Stop and get approval after step 1

**Step 1 — Derive and present the palette. Then stop.**

Run the reference implementation:

```bash
./derive_palette.py "<PRIMARY>" [--secondary "<SECONDARY>"]
```

It prints every token with its hex, its HSL, and its job, then measures all
twelve contrast gates and exits non-zero if any fails. Show the user that
output. Do not hand-derive the palette when the script is available, and do not
adjust a value it produced because you prefer a different one.

Flag anything the script noted, in plain language:
- a dark, light or desaturated `PRIMARY` that got rerouted (§2.1);
- a hue that could not carry white text and took the bright-fill/dark-ink path
  (§2.2) — say so plainly, because it changes how every button looks;
- a `danger`/`success`/`info` collision warning (§2.6) — resolve it and say what
  you shifted and why.

Then **stop and ask for approval.** Do not write a single line of app code
before the palette is signed off. A palette correction after thirty screens is
expensive; here it costs one message.

Once approved, generate the tokens file rather than typing it:

```bash
./derive_palette.py "<PRIMARY>" --dart > lib/theme/ds_colors.dart
```

### Then build in this order

Do not start a layer until the one above it is finished. Building screens first
and extracting components later is exactly how you end up with thirteen
different headers.

2. **Token files** — all five, per Appendix A. Bundle the font files in the
   repo; do not fetch them at runtime.
3. **`app_theme.dart`** — light and dark, both real.
4. **Chrome** — the cap+sheet page scaffold, the sheet, the cap controls, the
   bottom nav.
5. **Core components** — button, card, text field, chip, toast.
6. **The rest of the catalogue** in §8, as the screens need them.
7. **Screens.** By this point a screen should be composition, not design. If you
   find yourself making a visual decision inside a screen file, the component
   layer is missing something — go back and add it there.

### Non-negotiables

Read §9 in full. The short version, all of which are hard failures:

- No gradients. Anywhere. (One exception: a legibility scrim over a photo.)
- No glow halos. The `lift` shadow at 20% opacity is the ceiling.
- Cards are flat with a hairline. No shadow.
- One typeface. Hierarchy comes from the weight ladder.
- One filled primary button per screen.
- No hardcoded hex outside the colours file. Not one.
- Every tappable surface: press feedback + haptic.
- Every animated call site: check reduced motion.
- Text is never neutral grey and shadows are never neutral black — both carry
  the brand hue.

### How to write it

- **Comment the "why", not the "what".** `// 58dp plate` is noise.
  `// Equal-width slots: the label is wider than the plate, so a content-sized
  tile in a spaceBetween row runs off a 320dp screen` is the comment that stops
  the next person from undoing the fix. The spec is full of these — carry that
  standard into the code.
- **Every screen gets a skeleton state, an empty state, and an error state.**
  Not later. A screen without all three is not finished.
- **Every async action shows loading on the control that triggered it.**
- Format numbers at the edge, never mid-logic.
- Match the existing file's naming and structure once there is an existing file.

### Before you say it's done

Run the §13 checklist and report the result honestly, including anything that
fails. Specifically:

```
grep -rn "Color(0x" lib/ --include=*.dart | grep -v ds_colors.dart   # must be empty
grep -rn "Gradient"  lib/ --include=*.dart                            # scrim only
grep -rn "fontFamily" lib/ --include=*.dart | grep -v ds_typography   # must be empty
```

Then check by eye at **320dp wide**, at **1.3× text scale**, and in **dark
mode** — the three things that break layouts built on a large bright phone.

If something in the spec doesn't fit this app, say so and propose the change.
Do not silently deviate.

---

## Part 3 — What to expect

- **The palette table arrives first**, before any code. Look at the hexes and
  say yes or no. This is the moment to react.
- **The app will not look like a template.** The tinted neutrals and the flat
  brand surfaces are what do that, and they are the parts most likely to look
  odd in isolation. Judge the assembled screens, not the swatches.
- **It will look related to any other app built this way** — same bones, same
  rhythm — while reading as a different brand, because the hue drives
  everything. That's the intent.
- **A different primary changes the whole app**, including the greys and the
  shadows. Changing your mind on the brand colour later is one edit to the
  derivation and a rebuild, not a redesign — provided nothing hardcoded a hex.

---

## Part 4 — Worked example of a filled brief

```
APP_NAME:            ShipEast
WORDMARK_SPLIT:      Ship|East
LEGAL_NAME:          ShipEast Couriers & Bearer Services Ltd
TAGLINE:             Couriers & Bearer Services · Jamaica

PRIMARY:             #F72B54
SECONDARY:           (none)

PLATFORM:            Flutter (Android + iOS)
BACKEND:             Firebase

WHAT THE APP DOES:
  Local courier and shop-and-deliver service in Jamaica. A customer orders
  from a nearby merchant or asks a driver to buy and deliver something; a
  driver accepts jobs, navigates, and confirms delivery with a photo.

USER ROLES:
  Two separate apps — customer and driver — sharing one design system and
  one backend. A web admin panel is out of scope here.

SCREENS:
  Customer — splash, welcome, sign in/up, home, search, merchant, cart,
    checkout, order tracking, order history, profile.
  Driver — splash, welcome, sign in/up, pending approval, dashboard,
    job offer, pickup, delivery, delivery confirmation, earnings, profile.

MUST-HAVE FEATURES:
  Live GPS tracking on an active delivery · photo proof of delivery ·
  driver online/offline presence · push notifications.

EXPLICITLY OUT OF SCOPE:
  In-app payments · international shipping · a merchant-facing app.
```

That brief, run through `derive_palette.py`, produces `#E20D3C` as the action
tone, `#A50D30` as the shell, `#33292D` as the primary text and `#701A31` as the
shadow ink — all derived from the one hex, none chosen.

The shipped app's hand-tuned equivalents are `#E30D3B`, `#B00D33`, `#33292E` and
`#6E1A30`. The mean difference across all 28 comparable tokens is 2.4/255, which
is the point: a palette that took months of tuning comes back out of one input.
