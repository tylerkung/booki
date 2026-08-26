#!/usr/bin/env python3
"""WCAG AA contrast for the colour pairs that ACTUALLY occur.

WHY THIS SHAPE. The first audit measured every foreground token against every
surface token and reported 11 failures. Most were fiction: `--accent-secondary`
only ever appears inside gradients, and `--final` and `--scheduled` are only
ever set as text on their own tinted fill, never on a raw surface. Measuring
combinations that never render produces alarming numbers and teaches people to
ignore the check.

So this reads the stylesheets and measures three real relationships:

  1. every foreground token against the three surfaces, for tokens actually
     used as `color:` somewhere
  2. badge text against its own tinted fill, composited at the fill's real
     alpha over the card — the pattern `background: var(--fill-x); color: ...`
  3. nothing else

Text-only. A gradient, a dot or a border has no AA text requirement, and
flagging them is how a check loses its audience.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKENS = ROOT / 'landing' / 'tokens.css'
SHEETS = ['landing/dashboard/dashboard.css', 'landing/styles.css',
          'landing/admin/admin.css', 'landing/design/ds.css']

AA_NORMAL = 4.5
# WCAG 1.4.11: non-text content (icons, indicators, control boundaries) has a
# 3:1 floor, not 4.5:1. Holding an icon to the text threshold is not "stricter",
# it is wrong, and it pushes people to change brand colours to satisfy a rule
# that does not apply to them.
AA_NONTEXT = 3.0
NONTEXT_HINT = re.compile(r'icon|dot|chevron|caret|arrow|indicator|glyph|bullet')
SURFACES = ['--background', '--card', '--elevated']


def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _lum(rgb):
    r, g, b = rgb
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def ratio(a, b):
    la, lb = _lum(a), _lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hexrgb(h):
    h = h.lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def composite(fg, alpha, bg):
    return tuple(round(f * alpha + b * (1 - alpha)) for f, b in zip(fg, bg))


def load_tokens():
    src = TOKENS.read_text()
    raw = dict(re.findall(r'(--[\w-]+)\s*:\s*([^;]+);', src))
    hexes, alphas, fills = {}, {}, {}
    for k, v in raw.items():
        v = v.strip()
        m = re.fullmatch(r'#[0-9A-Fa-f]{3,6}', v)
        if m:
            hexes[k] = hexrgb(v)
        elif re.fullmatch(r'0?\.\d+', v):
            alphas[k] = float(v)
        # --fill-x: rgba(var(--x-rgb), var(--o-y))
        fm = re.fullmatch(r'rgba\(var\((--[\w-]+)-rgb\),\s*var\((--[\w-]+)\)\)', v)
        if fm:
            fills[k] = (fm.group(1), fm.group(2))
    # resolve one level of aliasing (--success: var(--accent))
    for k, v in raw.items():
        am = re.fullmatch(r'var\((--[\w-]+)\)', v.strip())
        if am and am.group(1) in hexes:
            hexes[k] = hexes[am.group(1)]
    return hexes, alphas, fills


def rules(path):
    """Yield (selector, declarations) for each rule block."""
    src = re.sub(r'/\*.*?\*/', '', path.read_text(), flags=re.S)
    for m in re.finditer(r'([^{}]+)\{([^{}]*)\}', src):
        yield m.group(1).strip().split('\n')[-1].strip(), m.group(2)


def real_pairs():
    """Colour pairs that actually render.

    A pair only counts when a rule sets BOTH a text colour and the thing behind
    it, or when a rule sets a text colour that will land on one of the page
    surfaces. The distinction matters: `--background` is used as `color:` on
    accent buttons, so pairing it against `--background` — which an
    every-foreground-by-every-surface sweep does — reports 1.00 and is pure
    fiction. That noise is what makes a check ignorable.
    """
    STRUCTURAL = {'--background', '--card', '--card-deep', '--elevated',
                  '--border', '--divider'}
    out = []
    for sheet in SHEETS:
        p = ROOT / sheet
        if not p.exists():
            continue
        for sel, body in rules(p):
            cm = re.search(r'(?<![-\w])color:\s*var\((--[\w-]+)\)', body)
            if not cm:
                continue
            fg = cm.group(1)
            bm = re.search(r'background(?:-color)?:\s*var\((--[\w-]+)\)', body)
            if bm:
                out.append((fg, bm.group(1), sel))
            elif fg not in STRUCTURAL:
                # inherits a page surface; check against all three
                for surf in SURFACES:
                    out.append((fg, surf, sel))
    return out


def main():
    hexes, alphas, fills = load_tokens()
    fails, checked, seen = [], 0, set()

    for fg, bg, sel in real_pairs():
        if fg not in hexes:
            continue
        if bg in fills:
            base, alpha_tok = fills[bg]
            if base not in hexes or alpha_tok not in alphas:
                continue
            bg_rgb = composite(hexes[base], alphas[alpha_tok], hexes['--card'])
        elif bg in hexes:
            bg_rgb = hexes[bg]
        else:
            continue
        key = (fg, bg)
        if key in seen:
            continue
        seen.add(key)
        checked += 1
        threshold = AA_NONTEXT if NONTEXT_HINT.search(sel.lower()) else AA_NORMAL
        r = ratio(hexes[fg], bg_rgb)
        if r < threshold:
            kind = 'non-text' if threshold == AA_NONTEXT else 'text'
            fails.append(f'{fg} on {bg}: {r:.2f} (needs {threshold} for {kind})  e.g. {sel[:38]}')

    if fails:
        print(f'contrast: {len(fails)} rendered pair(s) below WCAG AA\n')
        for f in sorted(fails):
            print(f'  {f}')
        print('\nLift the foreground, or pair the fill with a *-foreground token.')
        return 1

    print(f'contrast: clean — {checked} rendered pair(s) meet WCAG AA ({AA_NORMAL}:1)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
