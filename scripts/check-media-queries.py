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

    if bad:
        print(f'media queries: {len(bad)} condition(s) contain a custom property\n')
        for b in bad:
            print(f'  {b}')
        print('\nThese never match at any width. Custom properties cannot be '
              'resolved in a\nmedia condition — write the literal value.')
        return 1

    total = sum(len(re.findall(r'@media', p.read_text())) for p in SHEETS)
    print(f'media queries: clean — {total} condition(s), none using var()')
    return 0


if __name__ == '__main__':
    sys.exit(main())
