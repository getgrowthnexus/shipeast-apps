#!/usr/bin/env python3
"""ShipEast admin panel — design-system verification gate.

Enforces the locked values in DESIGN-SPEC.md against the shipped source. Run
from admin_panel/:

    python3 tools/verify-design.py

Exits non-zero if any gate fails, so it can be wired into CI.

Two classes of check:
  * CONSUMER gates run against every file that uses tokens. These must pass as
    soon as the restyle's component phase is done.
  * ALIAS gates run against tokens.css itself, where the compatibility aliases
    live on purpose until the final sweep deletes them. Pass --strict to
    require those gone too.
"""
from __future__ import annotations
import argparse, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSS_DIR = ROOT / 'css'
TOKENS = CSS_DIR / 'tokens.css'
CASCADE = ['tokens.css', 'shell.css', 'components.css', 'pages.css', 'responsive.css']
# Files that consume tokens but must never define the design system.
CONSUMERS = [CSS_DIR / n for n in CASCADE if n != 'tokens.css'] + \
            sorted(ROOT.glob('*.js')) + [ROOT / 'index.html']

failures: list[str] = []
notes: list[str] = []


def fail(gate: str, msg: str) -> None:
    failures.append(f'{gate}: {msg}')


def strip_comments(text: str, html: bool = False) -> str:
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    if html:
        text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    return text


# ─── colour maths ──────────────────────────────────────────────────────────
def _rgb(hx: str) -> tuple[int, int, int]:
    hx = hx.lstrip('#')
    if len(hx) == 3:
        hx = ''.join(c * 2 for c in hx)
    return tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore


def _lum(hx: str) -> float:
    def ch(c: int) -> float:
        s = c / 255
        return s / 12.92 if s <= .03928 else ((s + .055) / 1.055) ** 2.4
    r, g, b = _rgb(hx)
    return .2126 * ch(r) + .7152 * ch(g) + .0722 * ch(b)


def contrast(a: str, b: str) -> float:
    l1, l2 = _lum(a), _lum(b)
    hi, lo = max(l1, l2), min(l1, l2)
    return round((hi + .05) / (lo + .05), 2)


def over(fg: str, alpha_: float, bg: str) -> str:
    """Composite a translucent colour onto an opaque one, sRGB, no gamma —
    which is what a browser does when it paints one over the other."""
    f, b = _rgb(fg), _rgb(bg)
    return '#%02X%02X%02X' % tuple(
        round(f[i] * alpha_ + b[i] * (1 - alpha_)) for i in range(3))


def token(name: str, scope: str | None = None) -> str | None:
    """Literal hex value of a token, optionally within a theme scope."""
    body = TOKENS.read_text(encoding='utf-8')
    if scope:
        parts = body.split(scope, 1)
        if len(parts) < 2:
            return None
        body = parts[1]
    m = re.search(re.escape(name) + r'\s*:\s*(#[0-9A-Fa-f]{3,6})\b', body)
    return m.group(1) if m else None


def alpha(name: str, scope: str | None = None) -> tuple[str, float] | None:
    """(hex, alpha) of an rgba() token, so translucent ink can be measured
    against whatever it is painted on rather than exempted from the gate."""
    body = TOKENS.read_text(encoding='utf-8')
    if scope:
        parts = body.split(scope, 1)
        if len(parts) < 2:
            return None
        body = parts[1]
    m = re.search(re.escape(name) + r'\s*:\s*rgba\(\s*(\d+)\s*,\s*(\d+)\s*,'
                                    r'\s*(\d+)\s*,\s*([0-9.]+)\s*\)', body)
    if not m:
        return None
    r, g, b, a = int(m.group(1)), int(m.group(2)), int(m.group(3)), float(m.group(4))
    return '#%02X%02X%02X' % (r, g, b), a


# ─── gate 1: banned literals in consumer files ─────────────────────────────
DEAD_HEX = ['#C8102E', '#E1495F', '#86091E', '#F04A5E', '#A80D26', '#5F0615',
            '#3D0410', '#EE8492', '#F7B9C2', '#FFE0E5', '#FFF1F3', '#E11D34',
            '#9A0B22', '#FF6A3D', '#F5A524', '#0E9488', '#17B3A4', '#16A34A',
            '#D92D20', '#F59E0B', '#1C1A17', '#3A362F', '#6B6459', '#938C7F',
            '#C7C0B4', '#E4E0D9', '#ECEAE6', '#FAF9F7', '#F4F1EB', '#EDEAE3']
DEAD_TOKEN = ['--grad-ember', '--grad-sunset', '--glow', '--gold-500', '--gold-tint',
              '--ocean-500', '--ocean-tint', '--brand', '--brand-text', '--text-hi',
              '--text-lo', '--text-mute', '--card-raised', '--sidebar-bg', '--scrim',
              '--track-pill', '--gutter',
              # The two-family split. --ff-display / --ff-ui existed to switch
              # between Figtree and Inter Tight; there is one face now, so a
              # var(--ff-display) left anywhere is a rule that silently falls
              # back to the browser default.
              '--ff-display', '--ff-ui']


def gate_dead_values() -> None:
    for f in CONSUMERS:
        if not f.exists():
            continue
        src = strip_comments(f.read_text(encoding='utf-8'), html=f.suffix == '.html')
        rel = f.relative_to(ROOT)
        for hx in DEAD_HEX:
            for m in re.finditer(re.escape(hx), src, flags=re.I):
                line = src[:m.start()].count('\n') + 1
                fail('dead-hex', f'{rel}:{line} still uses {hx}')
        for t in DEAD_TOKEN:
            for m in re.finditer(r'var\(\s*' + re.escape(t) + r'\s*[),]', src):
                line = src[:m.start()].count('\n') + 1
                fail('dead-token', f'{rel}:{line} still reads {t}')
        # --ink-N and --sN numeric aliases
        for pat, label in ((r'var\(\s*(--ink-[0-9]{3})', 'ink alias'),
                           (r'var\(\s*(--s[0-9]{1,2})\s*[),]', 'spacing alias')):
            for m in re.finditer(pat, src):
                line = src[:m.start()].count('\n') + 1
                fail('dead-token', f'{rel}:{line} still reads {m.group(1)} ({label})')


# ─── gate 2: type discipline ───────────────────────────────────────────────
ALLOWED_FS = {'11px', '12px', '13px', '14px', '15px', '17px', '20px', '24px',
              '26px', '30px', '.86em', '1em', 'inherit', '0'}

# Weight 800 is BACK. The old rule banned it outright because Jakarta's
# variable axis stopped at 700 and anything above it was synthesised — a faux
# bold, which smears the stems and is exactly why the panel read as limp.
# Figtree carries a real master at every step of its 300–900 axis, so the ban
# is replaced by a whitelist. 900 stays out: it exists in the file, but at the
# sizes this panel uses it closes the counters on 'a' and 'e'.
ALLOWED_FW = {'400', '500', '600', '700', '800', 'inherit', 'normal', 'bold'}

# ONE FACE. The panel is set entirely in Figtree; the only other family it may
# name is the mono stack, on inline <code> and a handed-over password. This is
# the check that keeps "one typography system" true in the code rather than
# only in the screenshots — a second family cannot be introduced by adding a
# font-family somewhere, it can only be introduced by editing this list.
#   'Figtree'  — the @font-face declarations in tokens.css
#   inherit    — button/input/select/textarea, which do not inherit by default
ALLOWED_FF = {"var(--ff)", 'var(--ff-mono)', "'Figtree'", 'inherit'}


def gate_type() -> None:
    for f in CONSUMERS + [TOKENS]:
        if not f.exists():
            continue
        src = strip_comments(f.read_text(encoding='utf-8'), html=f.suffix == '.html')
        rel = f.relative_to(ROOT)
        for m in re.finditer(r'font-weight\s*:\s*([^;}\n)]+)', src):
            v = m.group(1).strip()
            # A variable font's @font-face declares an axis RANGE ("300 900").
            # That is the face's capability, not a value the design uses.
            if v.startswith('var(') or v in ALLOWED_FW or re.fullmatch(r'\d+ \d+', v):
                continue
            line = src[:m.start()].count('\n') + 1
            fail('off-scale-weight',
                 f'{rel}:{line} — font-weight:{v} is not one of '
                 f'{"/".join(sorted(w for w in ALLOWED_FW if w.isdigit()))}')
        for m in re.finditer(r'font-size\s*:\s*([0-9]+\.5px)', src):
            line = src[:m.start()].count('\n') + 1
            fail('half-pixel', f'{rel}:{line} — {m.group(1)}')
        for m in re.finditer(r'font-size\s*:\s*([^;}\n)]+)', src):
            v = m.group(1).strip()
            if v.startswith('var(') or v.startswith('clamp(') or v in ALLOWED_FS:
                continue
            line = src[:m.start()].count('\n') + 1
            fail('off-scale-size', f'{rel}:{line} — font-size:{v} is not in the ten-step scale')
        for m in re.finditer(r'font-family\s*:\s*([^;}\n]+)', src):
            # Only the first family in the stack is checked — the fallbacks
            # after it are system faces by definition.
            v = m.group(1).split(',')[0].strip()
            if v in ALLOWED_FF:
                continue
            line = src[:m.start()].count('\n') + 1
            fail('second-face', f'{rel}:{line} — font-family:{v} introduces a second '
                                f'typeface; the panel is set in one face (var(--ff))')
        # Tracking belongs to the token layer. Nine --tr-* values cover every
        # role in the panel, and a raw letter-spacing is how a tenth gets in
        # without anyone deciding it should exist — which is how the coupon
        # ended up on 2px and .12em while everything else was on em-relative
        # tokens that scale with the type.
        #
        # config.js is exempt and stays exempt: its one letter-spacing is on
        # the "you are pointed at PRODUCTION" banner, which is deliberately
        # built out of hardcoded values and system-ui so that it still paints
        # when the stylesheet or the font has failed to load. A safety warning
        # that depends on the design system is a safety warning that can
        # disappear with it.
        if f != TOKENS and f.name != 'config.js':
            for m in re.finditer(r'letter-spacing\s*:\s*([^;}\n]+)', src):
                v = m.group(1).strip()
                if v.startswith('var('):
                    continue
                line = src[:m.start()].count('\n') + 1
                fail('raw-tracking', f'{rel}:{line} — letter-spacing:{v} is not a '
                                     f'--tr-* token')


# ─── gate 3: spacing discipline ────────────────────────────────────────────
BANNED_PX = {'3px', '5px', '6px', '7px', '9px', '10px', '11px', '13px', '14px',
             '15px', '17px', '18px', '19px', '21px', '22px', '23px', '25px',
             '26px', '27px', '28px', '30px'}


def gate_spacing() -> None:
    props = r'(?:padding|margin|gap|row-gap|column-gap)(?:-(?:top|right|bottom|left|inline|block))?'
    for f in [CSS_DIR / n for n in CASCADE]:
        if not f.exists():
            continue
        src = strip_comments(f.read_text(encoding='utf-8'))
        rel = f.relative_to(ROOT)
        for m in re.finditer(props + r'\s*:\s*([^;}\n]+)', src):
            # (?<![\d.]) so "12.5px" is not read as a "5px" hit — the decimal
            # values are caught by the half-pixel gate instead.
            for px in re.findall(r'(?<![\d.])-?\d+px', m.group(1)):
                if px.lstrip('-') in BANNED_PX:
                    line = src[:m.start()].count('\n') + 1
                    fail('off-grid-spacing',
                         f'{rel}:{line} — {m.group(0).split(":")[0].strip()}: {px} '
                         f'is off the 4pt grid; use a --sp-*/--pad-*/--gap-* token')


# ─── gate 4: every consumed token resolves ─────────────────────────────────
def gate_tokens_resolve() -> None:
    tok = strip_comments(TOKENS.read_text(encoding='utf-8'))
    decl_only = re.sub(r'var\(\s*--[a-z0-9-]+', 'var(X', tok)
    defined = set(re.findall(r'(--[a-z0-9-]+)\s*:', decl_only))
    local = {'--card-pad'}
    consumed: dict[str, str] = {}
    for f in CONSUMERS + [TOKENS]:
        if not f.exists():
            continue
        src = strip_comments(f.read_text(encoding='utf-8'), html=f.suffix == '.html')
        for m in re.finditer(r'var\(\s*(--[a-z0-9-]+)', src):
            consumed.setdefault(m.group(1), f'{f.relative_to(ROOT)}:'
                                           f'{src[:m.start()].count(chr(10)) + 1}')
    for t, where in sorted(consumed.items()):
        if t not in defined and t not in local:
            fail('undefined-token', f'{where} reads {t}, which is never declared')
    notes.append(f'{len(defined)} tokens declared, {len(consumed)} consumed')


# ─── gate 5: contrast ──────────────────────────────────────────────────────
def gate_contrast() -> None:
    need = ['--n-0', '--n-25', '--n-50', '--n-100', '--n-300', '--n-400', '--n-500',
            '--n-600', '--n-800', '--red-50', '--red-400', '--red-500',
            '--red-600', '--red-700',
            '--success', '--warning', '--danger', '--info',
            '--brand-soft', '--success-soft', '--warning-soft', '--info-soft',
            '--danger-soft', '--shell', '--shell-mark', '--shell-ink-hi']
    L = {n: token(n) for n in need}
    missing = [n for n, v in L.items() if not v]
    if missing:
        fail('contrast', f'cannot resolve {", ".join(missing)} to a literal')
        return
    dark_surface = token('--surface', '[data-theme="dark"]')
    dark_sunken = token('--sunken', '[data-theme="dark"]')
    dark_field = token('--field', '[data-theme="dark"]')
    dark_shell = token('--shell', '[data-theme="dark"]')
    dark_soft = {n: token(f'--{n}-soft', '[data-theme="dark"]')
                 for n in ('brand', 'success', 'warning', 'info', 'danger')}
    if not all((dark_surface, dark_sunken, dark_field, dark_shell)) \
            or not all(dark_soft.values()):
        fail('contrast', 'dark theme surfaces do not resolve to literals')
        return

    # The rail's labels are white at partial opacity, so they have to be
    # composited before they can be measured. The rail is ONE flat colour now,
    # so --shell is both the body and the worst case; the --shell-hi peak these
    # were previously measured against is what --shell was set to when the
    # gradient came out, which is why no figure here moved.
    shell_ink = alpha('--shell-ink')
    shell_dim = alpha('--shell-ink-dim')
    d_shell_ink = alpha('--shell-ink', '[data-theme="dark"]')
    d_shell_dim = alpha('--shell-ink-dim', '[data-theme="dark"]')
    if not all((shell_ink, shell_dim, d_shell_ink, d_shell_dim)):
        fail('contrast', 'rail ink tokens are not plain rgba(...) literals')
        return

    checks = [
        # label,                fg,             bg,             min,  max
        # --surface is --n-25 now, NOT --n-0: light carries the brand tint on
        # its surfaces, which was the whole point of the 2026 pass. --n-0
        # survives as --surface-raised (inputs, row cards, the nav pill), so
        # both tones are gated — the pure-white checks below are not dead.
        ('primary ink / surface', L['--n-800'], L['--n-25'],    12.5, 14.6),
        ('secondary ink / surface', L['--n-600'], L['--n-25'],   7.0,  9.0),
        ('tertiary ink / surface', L['--n-500'], L['--n-25'],    4.5,  6.0),
        ('action red / surface', L['--red-600'], L['--n-25'],    4.5, 99),
        ('primary ink / card',   L['--n-800'],  L['--n-0'],     12.5, 14.6),
        ('primary ink / band',   L['--n-800'],  L['--n-100'],   12.5, 14.6),
        ('secondary ink / card', L['--n-600'],  L['--n-0'],      7.0,  9.0),
        ('tertiary ink / card',  L['--n-500'],  L['--n-0'],      4.5,  6.0),
        ('tertiary ink / band',  L['--n-500'],  L['--n-100'],    4.5,  6.0),
        # The 2026 ground (--n-50) is a real tint, not near-white, and the
        # topbar sits directly on it — so the breadcrumb, the date and every
        # page title are ink ON THE GROUND. These two are what stop anyone
        # deepening it further "just a little" until the chrome fails AA.
        ('primary ink / ground', L['--n-800'],  L['--n-50'],    10.0, 14.6),
        ('tertiary ink / ground', L['--n-500'], L['--n-50'],     4.5,  6.0),
        ('disabled ink / card',  L['--n-400'],  L['--n-0'],      3.0,  4.0),
        ('white / action red',   '#FFFFFF',     L['--red-600'],  4.5, 99),
        ('action red / card',    L['--red-600'], L['--n-0'],     4.5, 99),
        ('accent ink / wash',    L['--red-700'], L['--red-50'],  4.5, 99),
        ('white / danger',       '#FFFFFF',     L['--danger'],   4.5, 99),
        ('white / success',      '#FFFFFF',     L['--success'],  4.5, 99),
        ('white / info',         '#FFFFFF',     L['--info'],     4.5, 99),
        ('dark primary ink',     L['--n-50'],   dark_surface,    4.5, 99),
        ('dark secondary ink',   L['--n-300'],  dark_surface,    4.5, 99),
        ('dark tertiary ink',    L['--n-400'],  dark_surface,    4.5, 99),
        ('dark accent ink',      L['--red-400'], dark_surface,   4.5, 99),
        ('dark accent / sunken', L['--red-400'], dark_sunken,    4.5, 99),
        ('dark ink / sidebar',   L['--n-50'],   dark_shell,      4.5, 99),

        # ── The red rail ──────────────────────────────────────────────────
        # The sidebar is the one surface in the panel that is both permanently
        # on screen and painted in a saturated colour, so every piece of ink
        # on it is gated. It is a FLAT fill now — the bloom/shade/wash stack
        # was removed because it darkened the foot of the column off-brand —
        # so there is one background to measure against per theme instead of
        # three, and --shell was pinned to what the bloom's peak used to be so
        # that none of these figures changed when it went.
        ('white / rail',         '#FFFFFF',     L['--shell'],    4.5, 99),
        ('lockup mark / rail',   L['--shell-mark'], L['--shell'], 4.5, 99),
        # The rail's ink is a WARM white (#FFF4F7) rather than #FFF — see
        # --shell-ink-hi. Softening chrome by hue is only defensible if it
        # costs nothing in legibility, so the full tone is gated on both
        # rails exactly as pure white was, and the two composited steps
        # below it are measured against what the cold stack reached
        # (5.52 / 4.56 light, 8.04 / 5.40 dark). All four figures went UP.
        ('lockup white / rail',  L['--shell-ink-hi'], L['--shell'],  4.5, 99),
        ('lockup white / dark rail', L['--shell-ink-hi'], dark_shell, 4.5, 99),
        ('nav label / rail',
         over(shell_ink[0], shell_ink[1], L['--shell']), L['--shell'], 4.5, 99),
        ('section head / rail',
         over(shell_dim[0], shell_dim[1], L['--shell']), L['--shell'], 4.5, 99),
        # The selected pill inverts to white in BOTH themes, so its ink is
        # gated once, against white, rather than per-theme.
        ('active pill ink',      L['--red-700'], L['--n-0'],     4.5, 99),
        ('dark white / rail',    '#FFFFFF',     dark_shell,      4.5, 99),
        ('dark nav label / rail',
         over(d_shell_ink[0], d_shell_ink[1], dark_shell), dark_shell, 4.5, 99),
        ('dark section head / rail',
         over(d_shell_dim[0], d_shell_dim[1], dark_shell), dark_shell, 4.5, 99),
        # --shell-mark is deliberately NOT re-cut for dark, so it is checked
        # on both rails. It carries the lockup's sub-label on the rail, in
        # both themes, at 11px — which is the size that makes these two the
        # binding pair rather than a formality. This is also what catches
        # anyone "tidying" it into the --red-100/200 steps, which invert.
        ('lockup mark / dark rail', L['--shell-mark'], dark_shell, 4.5, 99),
        # The login's brand panel IS the rail — same --shell, same --shell-ink
        # body copy, same warm white — so it is covered by the rail checks
        # above rather than needing its own. The old `white / login canvas`
        # pair went with the --red-900 field it measured: that maroon existed
        # only behind the login card, which is exactly why the first screen
        # announced a colour the product does not otherwise have.

        # ── Soft tones as SURFACES ────────────────────────────────────────
        # The point of the soft step is that it is a surface you may set type
        # on without thinking, which is only true if it is gated like one. Ten
        # checks: primary ink and tertiary ink on each of the five, in both
        # themes. A soft tone that fails these is a decoration, not a surface,
        # and the stat cards / toasts / helper panels that use them would be
        # quietly illegible.
        ('ink / brand soft',     L['--n-800'], L['--brand-soft'],   12.5, 14.6),
        ('ink / success soft',   L['--n-800'], L['--success-soft'], 12.5, 14.6),
        ('ink / warning soft',   L['--n-800'], L['--warning-soft'], 12.5, 14.6),
        ('ink / info soft',      L['--n-800'], L['--info-soft'],    12.5, 14.6),
        ('ink / danger soft',    L['--n-800'], L['--danger-soft'],  12.5, 14.6),
        ('tertiary ink / brand soft',   L['--n-500'], L['--brand-soft'],   4.5, 6.0),
        ('tertiary ink / success soft', L['--n-500'], L['--success-soft'], 4.5, 6.0),
        ('tertiary ink / warning soft', L['--n-500'], L['--warning-soft'], 4.5, 6.0),
        ('tertiary ink / info soft',    L['--n-500'], L['--info-soft'],    4.5, 6.0),
        ('tertiary ink / danger soft',  L['--n-500'], L['--danger-soft'],  4.5, 6.0),
        ('dark ink / brand soft',   L['--n-50'], dark_soft['brand'],   4.5, 99),
        ('dark ink / success soft', L['--n-50'], dark_soft['success'], 4.5, 99),
        ('dark ink / warning soft', L['--n-50'], dark_soft['warning'], 4.5, 99),
        ('dark ink / info soft',    L['--n-50'], dark_soft['info'],    4.5, 99),
        ('dark ink / danger soft',  L['--n-50'], dark_soft['danger'],  4.5, 99),
        # --field is where the panel's text is actually TYPED, so it is gated
        # on both themes rather than assumed safe for being "nearly --sunken".
        ('ink / field',          L['--n-800'],  L['--n-100'],   12.5, 14.6),
        ('placeholder / field',  L['--n-400'],  L['--n-100'],    2.8,  4.0),
        ('dark ink / field',     L['--n-50'],   dark_field,      4.5, 99),
        ('dark placeholder / field', L['--n-500'], dark_field,   2.8, 99),
    ]
    for label, fg, bg, lo, hi in checks:
        v = contrast(fg, bg)
        if not (lo <= v <= hi):
            bound = f'{lo}' if hi >= 99 else f'{lo}–{hi}'
            fail('contrast', f'{label}: {fg} on {bg} = {v}:1, wanted {bound}')

    # warning must never be paired with white
    w = contrast('#FFFFFF', L['--warning'])
    if w >= 4.5:
        notes.append(f'warning now passes with white ({w}:1) — the never-white rule '
                     f'could be relaxed')
    else:
        notes.append(f'warning + white is {w}:1 as expected — tint+ink only')
    notes.append(f'{len(checks)} contrast pairs checked')


# ─── gate 6: structural sanity ─────────────────────────────────────────────
def gate_structure() -> None:
    for f in [CSS_DIR / n for n in CASCADE]:
        if not f.exists():
            fail('structure', f'{f.name} is missing')
            continue
        src = strip_comments(f.read_text(encoding='utf-8'))
        if src.count('{') != src.count('}'):
            fail('structure', f'{f.name} braces unbalanced '
                              f'({src.count("{")} open, {src.count("}")} close)')
    html = (ROOT / 'index.html').read_text(encoding='utf-8')
    for i, name in enumerate(CASCADE):
        if f'css/{name}' not in html:
            fail('structure', f'index.html does not link css/{name}')
    # cascade order must match CASCADE exactly
    order = re.findall(r'href="css/([a-z]+\.css)"', html)
    if order != CASCADE:
        fail('structure', f'stylesheet link order is {order}, must be {CASCADE} '
                          f'— responsive.css last, tokens.css first')
    if (ROOT / 'styles.css').exists():
        fail('structure', 'styles.css still exists; the split left a stale copy')


# ─── gate 7: aliases gone (strict only) ────────────────────────────────────
def gate_aliases_removed() -> None:
    tok = strip_comments(TOKENS.read_text(encoding='utf-8'))
    decl_only = re.sub(r'var\(\s*--[a-z0-9-]+', 'var(X', tok)
    for t in DEAD_TOKEN:
        if re.search(re.escape(t) + r'\s*:', decl_only):
            fail('alias-left', f'tokens.css still declares {t}')
    for m in re.finditer(r'(--ink-[0-9]{3}|--s[0-9]{1,2})\s*:', decl_only):
        fail('alias-left', f'tokens.css still declares {m.group(1)}')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--strict', action='store_true',
                    help='also require the compatibility aliases to be gone')
    args = ap.parse_args()

    gate_structure()
    gate_tokens_resolve()
    gate_contrast()
    gate_type()
    gate_spacing()
    gate_dead_values()
    if args.strict:
        gate_aliases_removed()

    for n in notes:
        print(f'  · {n}')
    print()
    if failures:
        by_gate: dict[str, list[str]] = {}
        for f in failures:
            g, _, rest = f.partition(': ')
            by_gate.setdefault(g, []).append(rest)
        total = len(failures)
        for g, items in sorted(by_gate.items()):
            print(f'{g}  ({len(items)})')
            for it in items[:15]:
                print(f'    {it}')
            if len(items) > 15:
                print(f'    … and {len(items) - 15} more')
            print()
        print(f'FAILED — {total} issue{"s" if total != 1 else ""} across '
              f'{len(by_gate)} gate{"s" if len(by_gate) != 1 else ""}')
        return 1
    print('ALL GATES PASSED')
    return 0


if __name__ == '__main__':
    sys.exit(main())
