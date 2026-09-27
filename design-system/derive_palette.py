#!/usr/bin/env python3
"""
Derive a full design-system palette from one brand colour.

This is section 2 of DESIGN-SYSTEM.md, executable. It is the reference
implementation: if the spec and this script ever disagree, the script is right,
because it is the one that measures contrast instead of asserting it.

    ./derive_palette.py "#F72B54"                    # the table
    ./derive_palette.py "#F72B54" --secondary "#1F6BC1"
    ./derive_palette.py "#2563EB" --dart             # ds_colors.dart, ready to paste

Every tier and every neutral is walked toward its contrast gate rather than set
to a fixed lightness. That matters because HSL lightness is not perceptual
lightness: a green at L=58% and a blue at L=58% have very different luminance,
so a fixed-L neutral that passes on one hue fails on another. Walking to the
gate is what makes the system hue-independent.

No dependencies beyond the standard library.
"""

import argparse
import colorsys
import sys

# ── colour maths ─────────────────────────────────────────────────────────────


def hex2hsl(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        raise ValueError(f"not a hex colour: #{h}")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hh, l, s = colorsys.rgb_to_hls(r, g, b)
    return hh * 360, s * 100, l * 100


def hsl2hex(h, s, l):
    r, g, b = colorsys.hls_to_rgb(
        (h % 360) / 360, clamp(l, 0, 100) / 100, clamp(s, 0, 100) / 100
    )
    return "#%02X%02X%02X" % tuple(round(x * 255) for x in (r, g, b))


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def luminance(hx):
    hx = hx.lstrip("#")
    ch = []
    for i in (0, 2, 4):
        v = int(hx[i:i + 2], 16) / 255
        ch.append(v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4)
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def walk(h, s, start, against, target, step, limit):
    """Move L from `start` by `step` until contrast vs `against` clears
    `target`, or `limit` is reached. Returns (hex, L)."""
    l = start
    while (step < 0 and l > limit) or (step > 0 and l < limit):
        if contrast(hsl2hex(h, s, l), against) >= target:
            break
        l += step
    return hsl2hex(h, s, l), l


def darken_to(h, s, start, against, target, limit=6):
    return walk(h, s, start, against, target, -1, limit)


def lighten_to(h, s, start, against, target, limit=92):
    return walk(h, s, start, against, target, +1, limit)


def rgb_of(hx):
    hx = hx.lstrip("#")
    return tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))


# ── derivation (DESIGN-SYSTEM.md section 2) ──────────────────────────────────

FIXED_SEMANTIC = {
    "success": "#1C8252", "successTint": "#E4F6EC",
    "successInk": "#196B45", "successSoft": "#EFF8F2",
    "warning": "#D37A0D", "warningTint": "#FCEFDC",
    # 4.87:1 on warningSoft. The obvious choice one step lighter (#AD640B)
    # measures 4.19:1 and fails AA — amber is the tone where "it looks dark
    # enough" is most often wrong, because the hue is luminous.
    "warningInk": "#9E5B0A", "warningSoft": "#FDF4E7", "warningOn": "#3D2A05",
    "danger": "#A51D2F", "dangerTint": "#FCE6E9",
    "dangerInk": "#821725", "dangerSoft": "#FDEFF1",
    "info": "#1F6BC1", "infoTint": "#E6F0FB",
    "infoInk": "#1A579E", "infoSoft": "#EFF4FC",
    "star": "#E8A317",
}


def derive(primary, secondary=None):
    H, S, L = hex2hsl(primary)
    notes, warnings = [], []

    # 2.1 — route by lightness, then by saturation.
    if L < 42:
        notes.append(
            f"input is dark (L={L:.0f}%): it becomes the ACTION tone, and the "
            f"identity tone is lifted +10pp to give plates and accents "
            f"something brighter to use"
        )
        Li = L + 10
    elif L > 72:
        notes.append(
            f"input is light (L={L:.0f}%): kept for the logo, but the identity "
            f"tone is computed at L=62% so the ramp lands in usable range"
        )
        Li = 62.0
    else:
        Li = L

    satmul = 1.0
    if S < 25:
        notes.append(
            f"input is near-neutral (S={S:.0f}%): neutral saturations halved so "
            f"the tinted greys do not read as a second colour. The semantic "
            f"tones carry the colour in this app."
        )
        satmul = 0.5

    surface0 = hsl2hex(H, 100, 98)
    brandSoft = hsl2hex(H, 100, 97)
    shellInk = hsl2hex(H, 100, 98)
    darkBg = hsl2hex(H, 13, 7)

    # 2.2 — the tiers. Each walks to its gate.
    identity = hsl2hex(H, S, Li)
    action, la = darken_to(H - 1, S - 4, Li - 10, "#FFFFFF", 4.5)
    dark_ink = (Li - la) > 14

    if dark_ink:
        # This hue cannot be darkened enough to carry white without becoming a
        # different colour (yellow turns brown). Do what a real yellow button
        # does: keep the fill BRIGHT and put dark ink on it.
        action = hsl2hex(H - 1, S - 4, max(Li, 52))
        action_on, _ = darken_to(H, 70, 14, action, 4.5, limit=3)
        notes.append(
            f"this hue cannot carry white text (it needed −{Li - la:.0f}pp of "
            f"lightness, which changes the colour): the action tone stays a "
            f"BRIGHT fill and takes dark ink {action_on} instead. On this path "
            f"identity and action are near-identical by design — what "
            f"distinguishes them is the ink, not a second hue."
        )
    else:
        action_on = "#FFFFFF"

    shell, _ = darken_to(H - 2, S - 7, Li - 20, shellInk, 7.0)

    def neutral(h_off, sat, start, target):
        return darken_to(H + h_off, sat * satmul, start, surface0, target)[0]

    p = {
        # brand ramp
        "b50": hsl2hex(H, 100, 95),
        "b100": hsl2hex(H, 100, 92),
        "b200": hsl2hex(H, 97, 88),
        "b300": hsl2hex(H, 95, 78),
        "b400": lighten_to(H, S + 1, min(74, Li + 9), darkBg, 4.5)[0],
        "b500": identity,
        "b600": action,
        "b700": darken_to(H, 88, 38, brandSoft, 4.5)[0],
        "b800": hsl2hex(H, 85, 29),
        "b900": hsl2hex(H, 82, 20),
        "identity": identity,
        "action": action,
        "actionOn": action_on,
        "brandInk": darken_to(H, 88, 38, brandSoft, 4.5)[0],
        "brandSoft": brandSoft,
        # shell
        "shell": shell,
        "shellInk": shellInk,
        "shellMark": hsl2hex(H, 100, 89),
        # tinted neutrals
        "ink900": neutral(-15, 11, 18, 12.0),
        "ink700": neutral(-20, 10, 25, 9.0),
        "ink500": neutral(-15, 8, 44, 4.5),
        "ink400": neutral(-16, 9, 58, 3.0),
        "ink300": hsl2hex(H - 12, 13 * satmul, 76),
        "ink200": hsl2hex(H - 8, 20 * satmul, 88),
        "ink100": hsl2hex(H - 5, 25 * satmul, 92),
        "surface50": hsl2hex(H - 8, 46 * satmul, 95),
        "surface0": surface0,
        "surfaceRaised": "#FFFFFF",
        "field": hsl2hex(H, 62 * satmul, 96),
        "shadowInk": hsl2hex(H - 4, 62, 27),
        # dark theme
        "darkBg": darkBg,
        "darkCard": hsl2hex(H, 13, 13),
        "darkCardRaised": hsl2hex(H, 11, 17),
        "darkTextHi": hsl2hex(H - 8, 46 * satmul, 95),
        "darkTextLo": hsl2hex(H, 8, 63),
        "darkBorder": hsl2hex(H, 9, 22),
        "brandOnDark": lighten_to(H, S + 1, min(74, Li + 9), darkBg, 4.5)[0],
    }
    p.update(FIXED_SEMANTIC)

    # 2.7 — secondary takes over the informational role.
    if secondary:
        H2, S2, _ = hex2hsl(secondary)
        p["info"] = secondary.upper()
        p["infoTint"] = hsl2hex(H2, S2 * 0.55, 94)
        p["infoInk"] = darken_to(H2, S2, 36, hsl2hex(H2, S2 * 0.4, 96), 4.5)[0]
        p["infoSoft"] = hsl2hex(H2, S2 * 0.4, 96)
        notes.append("SECONDARY supplied: it takes over the informational tone, "
                     "the second category hue and chart series 2. It does not "
                     "get buttons — the app has one action colour.")

    # 2.6 — the collision rule. Hue alone is not enough: a deep maroon danger
    # tone sits only a few degrees from a bright pink brand and still reads as
    # clearly different, because the lightness gap does the work. Warn only
    # when the hue AND the lightness are both close.
    def hue_gap(a, b):
        d = abs(hex2hsl(a)[0] - hex2hsl(b)[0]) % 360
        return min(d, 360 - d)

    for role in ("danger", "success", "info"):
        hg = hue_gap(p[role], identity)
        lg = abs(hex2hsl(p[role])[2] - Li)
        if hg < 30 and lg < 15:
            warnings.append(
                f"'{role}' ({p[role]}) is {hg:.0f}° from the brand hue and only "
                f"{lg:.0f}pp apart in lightness — too close to tell apart at a "
                f"glance. Shift it per section 2.6, or '{role}' stops carrying "
                f"its meaning."
            )
    return p, notes, warnings


def gates(p):
    ink = p["actionOn"]
    return [
        (f"{'white' if ink == '#FFFFFF' else 'dark ink'} on action",
         p["action"], ink, 4.5),
        ("shellInk on shell", p["shell"], p["shellInk"], 7.0),
        ("ink900 on surface0", p["ink900"], p["surface0"], 12.0),
        ("ink700 on surface0", p["ink700"], p["surface0"], 9.0),
        ("ink500 on surface0", p["ink500"], p["surface0"], 4.5),
        ("ink400 on surface0", p["ink400"], p["surface0"], 3.0),
        ("brandInk on brandSoft", p["brandInk"], p["brandSoft"], 4.5),
        ("brandOnDark on darkBg", p["brandOnDark"], p["darkBg"], 4.5),
        ("successInk on successSoft", p["successInk"], p["successSoft"], 4.5),
        ("warningInk on warningSoft", p["warningInk"], p["warningSoft"], 4.5),
        ("dangerInk on dangerSoft", p["dangerInk"], p["dangerSoft"], 4.5),
        ("infoInk on infoSoft", p["infoInk"], p["infoSoft"], 4.5),
    ]


JOBS = {
    "b50": "wash", "b100": "hover tint, badges, cap accents",
    "b200": "disabled primary fill", "b300": "subtle accents",
    "b400": "brand text ON DARK", "b500": "= identity", "b600": "= action",
    "b700": "= brandInk", "b800": "deep", "b900": "ramp floor",
    "identity": "large fills, plates, focus rings — NEVER small white text",
    "action": "buttons, links, active states, cursors",
    "actionOn": "the text colour that goes on `action`",
    "brandInk": "brand-coloured text on a brand tint",
    "brandSoft": "secondary button fill, tinted panels",
    "shell": "caps, splash, auth hero — big permanent brand surfaces",
    "shellInk": "warm white ON the shell (never pure #FFF)",
    "shellMark": "wordmark accent + badges on the shell",
    "ink900": "primary text", "ink700": "headings, body, field labels",
    "ink500": "secondary text, captions",
    "ink400": "placeholder, disabled, inactive nav",
    "ink300": "muted icons, carets",
    "ink200": "HAIRLINES, borders, dividers, skeletons",
    "ink100": "inset divider inside a row group",
    "surface50": "page ground (the sheet)", "surface0": "cards, panels, bars",
    "surfaceRaised": "focused field, a pill lifted off a card",
    "field": "a sunken well you type into",
    "shadowInk": "all shadows are cast in this, never black",
    "darkBg": "dark page", "darkCard": "dark card",
    "darkCardRaised": "dark raised", "darkTextHi": "dark primary text",
    "darkTextLo": "dark secondary text", "darkBorder": "dark hairline",
    "brandOnDark": "brand text in dark mode",
}

GROUPS = [
    ("BRAND RAMP", ["b50", "b100", "b200", "b300", "b400", "b500", "b600",
                    "b700", "b800", "b900"]),
    ("THE THREE TIERS", ["identity", "action", "actionOn", "brandInk",
                         "brandSoft"]),
    ("SHELL", ["shell", "shellInk", "shellMark"]),
    ("TINTED NEUTRALS", ["ink900", "ink700", "ink500", "ink400", "ink300",
                         "ink200", "ink100", "surface50", "surface0",
                         "surfaceRaised", "field", "shadowInk"]),
    ("SEMANTIC", ["success", "successTint", "successInk", "successSoft",
                  "warning", "warningTint", "warningInk", "warningSoft",
                  "warningOn", "danger", "dangerTint", "dangerInk",
                  "dangerSoft", "info", "infoTint", "infoInk", "infoSoft",
                  "star"]),
    ("DARK THEME", ["darkBg", "darkCard", "darkCardRaised", "darkTextHi",
                    "darkTextLo", "darkBorder", "brandOnDark"]),
]


def swatch(hx):
    r, g, b = rgb_of(hx)
    return f"\x1b[48;2;{r};{g};{b}m   \x1b[0m"


def print_table(primary, p, notes, warnings, colour=True):
    H, S, L = hex2hsl(primary)
    print(f"\nPRIMARY {primary.upper()}  =  hsl({H:.0f}, {S:.0f}%, {L:.0f}%)")
    for n in notes:
        print(f"\n  NOTE  {n}")
    for w in warnings:
        print(f"\n  WARN  {w}")

    for title, keys in GROUPS:
        print(f"\n{title}")
        print(f"  {'token':16} {'hex':9}  {'hsl':20} job")
        for k in keys:
            hx = p[k]
            hh, ss, ll = hex2hsl(hx)
            sw = swatch(hx) + " " if colour else ""
            print(f"  {sw}{k:16} {hx:9}  "
                  f"{f'{hh:.0f}, {ss:.0f}%, {ll:.0f}%':20} {JOBS.get(k, '')}")

    print("\nCONTRAST GATES")
    ok = True
    for name, fg, bg, target in gates(p):
        r = contrast(fg, bg)
        good = r >= target - 0.005
        ok &= good
        print(f"  {'PASS' if good else 'FAIL':4}  {name:28} "
              f"{r:5.2f}:1  (need {target})")
    print(f"\n{'ALL GATES PASS' if ok else '*** GATES FAILED ***'}")
    return ok


DART_ORDER = [
    ("Brand ramp", ["b50", "b100", "b200", "b300", "b400", "b500", "b600",
                    "b700", "b800", "b900"]),
    ("Tiers", ["identity", "action", "actionOn", "brandInk", "brandSoft"]),
    ("Shell", ["shell", "shellInk", "shellMark"]),
    ("Semantic", ["success", "successTint", "successInk", "successSoft",
                  "warning", "warningTint", "warningInk", "warningSoft",
                  "warningOn", "danger", "dangerTint", "dangerInk",
                  "dangerSoft", "info", "infoTint", "infoInk", "infoSoft",
                  "star"]),
    ("Tinted neutrals", ["ink900", "ink700", "ink500", "ink400", "ink300",
                         "ink200", "ink100", "surface50", "surface0",
                         "surfaceRaised", "field"]),
    ("Dark theme", ["darkBg", "darkCard", "darkCardRaised", "darkTextHi",
                    "darkTextLo", "darkBorder", "brandOnDark"]),
]


def print_dart(p):
    sr, sg, sb = rgb_of(p["shadowInk"])
    print("""import 'package:flutter/material.dart';

/// Design system — colour tokens.
/// GENERATED by design-system/derive_palette.py. THE ONLY FILE WITH A HEX IN IT.
///
///  1. THREE-TIER BRAND. [identity] is bright and never carries small white
///     text. [action] is what buttons and links use. [shell] paints big
///     permanent brand surfaces under warm-white ink.
///  2. TINTED NEUTRALS. Surfaces are not white and text is not grey — both
///     carry the brand hue at low saturation, so the brand belongs to the same
///     family as its background instead of floating on a white sheet.
///  3. NO GRADIENTS. Depth is hairlines + brand-tinted shadows, never a sheen.
class DsColors {
  DsColors._();
""")
    for title, keys in DART_ORDER:
        print(f"  // ── {title} " + "─" * max(0, 66 - len(title)))
        for k in keys:
            job = JOBS.get(k, "")
            line = f"  static const Color {k} = Color(0xFF{p[k].lstrip('#')});"
            print(f"{line:<62}{'// ' + job if job else ''}".rstrip())
        print()
    print(f"""  /// All shadows are cast in this, never neutral black: over a tinted
  /// ground a black shadow turns grey and fights the palette.
  static const Color shadowInk = Color(0xFF{p['shadowInk'].lstrip('#')});
  static const int shadowR = {sr}, shadowG = {sg}, shadowB = {sb};

  /// Legibility scrim over photos and maps. The ONLY gradient in the system —
  /// a scrim is a function, not a decoration.
  static const LinearGradient inkScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00{p['darkBg'].lstrip('#')}), Color(0xB8{p['darkBg'].lstrip('#')})],
  );
}}""")


def main():
    ap = argparse.ArgumentParser(
        description="Derive a full palette from one brand colour.")
    ap.add_argument("primary", help="brand hex, e.g. '#F72B54'")
    ap.add_argument("--secondary", help="optional; becomes the info tone")
    ap.add_argument("--dart", action="store_true",
                    help="emit ds_colors.dart instead of the table")
    ap.add_argument("--no-colour", action="store_true",
                    help="no ANSI swatches")
    a = ap.parse_args()

    try:
        p, notes, warnings = derive(a.primary, a.secondary)
    except ValueError as e:
        sys.exit(f"error: {e}")

    if a.dart:
        print_dart(p)
        bad = [n for n, f, b, t in gates(p) if contrast(f, b) < t - 0.005]
        if bad:
            print(f"\n// WARNING: gates failed: {bad}", file=sys.stderr)
        return

    ok = print_table(a.primary, p, notes, warnings,
                     colour=not a.no_colour and sys.stdout.isatty())
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
