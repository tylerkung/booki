#!/usr/bin/env python3
"""Media conditions must not contain custom properties.

`@media (max-width: var(--w-content))` is INVALID CSS. It does not throw, it
does not warn, and DevTools renders the rule in the stylesheet exactly like a
working one. It simply never matches, at any viewport width.

Twelve of these existed in dashboard.css. Between them they held 66 rules —
the sidebar, the mobile header, the stats grid and the entire data-table
card transform. The dashboard's mobile layout had been inert.

The mistake is an easy one to make and impossible to see: every OTHER value in
this codebase routes through a token, so writing var() in a media query is what
consistency looks like. It is also why check-design-tokens.py explicitly allows
raw px in an @media line — that allowance and this check are two halves of the
same rule, and only having the first half is what let this through.

Custom properties are resolved per-element at computed-value time; a media
condition is evaluated before any element exists, so there is nothing to resolve
against. Fixing it needs a literal, or a build step this project does not have.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHEETS = list((ROOT / 'landing').rglob('*.css'))


def adjacent_pairs(all_widths):
    """max-width: Npx paired with min-width: (N+1)px leaves a fractional gap.

    The pair looks correct — the two do not overlap on integer widths — and it
    is what most people write. But a viewport can report a FRACTIONAL CSS pixel
    width at some zoom levels and on devices with fractional DPR scaling, and
    768.5px matches neither `(max-width: 768px)` nor `(min-width: 769px)`. Both
    sides of the layout switch off at once.

    The convention that closes it: the max side takes .98, the min side takes
    the round number, so they meet exactly.
    """
    maxes = {w for kind, w in all_widths if kind == 'max' and float(w).is_integer()}
    mins = {w for kind, w in all_widths if kind == 'min'}
    return sorted((m, m + 1) for m in maxes if (m + 1) in mins)


def main():
    bad = []
    for p in SHEETS:
        src = p.read_text()
        for m in re.finditer(r'@media[^{]*', src):
            cond = m.group(0)
            if 'var(' in cond:
                ln = src[:m.start()].count('\n') + 1
                rel = p.relative_to(ROOT)
                bad.append(f'{rel}:{ln}  {cond.strip()[:64]}')

    widths = []
    for p in SHEETS:
        for m in re.finditer(r'\((max|min)-width:\s*([\d.]+)px\)', p.read_text()):
            widths.append((m.group(1), float(m.group(2))))
    for lo, hi in adjacent_pairs(widths):
        bad.append(
            f'(max-width: {lo:g}px) is paired with (min-width: {hi:g}px) — a '
            f'viewport at {lo:g}.5px matches neither. Use '
            f'(max-width: {lo - 0.02:.2f}px) and (min-width: {lo:g}px).')

    if bad:
        print(f'media queries: {len(bad)} problem(s)\n')
        for b in bad:
            print(f'  {b}')
        print('\nA var() condition never matches at any width — custom properties '
              'cannot be\nresolved before an element exists, so write the literal. '
              'An adjacent pair\nleaves a fractional-pixel gap — move the max side '
              'to .98.')
        return 1

    total = sum(len(re.findall(r'@media', p.read_text())) for p in SHEETS)
    print(f'media queries: clean — {total} condition(s), none using var(), '
          f'no gapped pairs')
    return 0


if __name__ == '__main__':
    sys.exit(main())
