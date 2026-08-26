#!/usr/bin/env python3
"""The design-system page must not reimplement product components.

For a long time landing/design/ carried its own .ds-* copy of every component.
Two hand-maintained implementations of one thing drift by default, and this
particular pair drifted badly: of 20 button variants across the two, only 3
existed on both sides. The page documented a system nobody shipped.

The page now loads ../dashboard/dashboard.css and renders the product's real
classes. This check stops the copy growing back.

A .ds-* class whose base name also exists in the product is a duplicate unless
it is listed in KNOWN, with a reason. KNOWN is not a mute button — every entry
still prints on a clean run, because the point is that the divergence stays
visible rather than being resolved by forgetting about it.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DS = ROOT / 'landing' / 'design' / 'ds.css'
PRODUCT = ROOT / 'landing' / 'dashboard' / 'dashboard.css'

# base name -> why it is still duplicated
KNOWN = {
    'btn':   'the two systems model buttons on different axes — the page names '
             'intent (primary/secondary/ghost), the product names outcome '
             '(grade-win/void). Reconciling them is a design decision.',
    'badge': 'PARTLY RESOLVED 2026-08-26 — the product adopted the semantic '
             'names (won/lost/push/pending/scheduled/live/final), so 7 of 17 '
             'variants now agree, up from 2 of 14. The visual names remain for '
             'non-status badges (a member being active is not a pick outcome), '
             'and .ds-badge--off has no product analogue.',
    'card':  'the page uses BEM parts (card__head/__foot), the product uses '
             'card-header/card-title. A rename, but one that touches markup '
             'across the dashboard.',
}

# .ds-* names that are page chrome, not components, and have no product analogue
CHROME_PREFIXES = ('nav', 'section', 'main', 'brand', 'swatch', 'h1', 'h2',
                   'lede', 'label', 'note', 'demo', 'row', 'table', 'scroll',
                   'grid', 'code', 'rules', 'toast', 'tabbar', 'skel', 'matrix',
                   'stat', 'meter', 'wrapline', 'ok', 'no', 'focus', 'w')


def main():
    if not (DS.exists() and PRODUCT.exists()):
        print('ds drift: stylesheets missing')
        return 1

    ds_bases = {re.split(r'--|__', m)[0]
                for m in re.findall(r'\.ds-([a-z][a-z0-9-]*)', DS.read_text())}
    # EXACT class names only. Deriving a base by splitting on '-' invents
    # components that do not exist: .tag-tooltip is not evidence of a .tag, and
    # .empty-state is not evidence of an .empty. That produced three phantom
    # duplicates the first time this ran.
    product = set(re.findall(r'^\.([a-z][a-z0-9-]*)\s*[,{]',
                             PRODUCT.read_text(), re.M))

    dupes = sorted(b for b in ds_bases
                   if b in product and not b.startswith(CHROME_PREFIXES))

    unknown = [b for b in dupes if b not in KNOWN]
    if unknown:
        print(f'ds drift: {len(unknown)} component(s) reimplemented on the '
              f'design-system page\n')
        for b in unknown:
            print(f'  .ds-{b} duplicates .{b} in dashboard.css')
        print('\nRender the product class instead, or add it to KNOWN with the '
              'reason\nthe two cannot be the same class.')
        return 1

    print(f'ds drift: clean — no new component copies '
          f'({len(dupes)} known, listed below)')
    for b in dupes:
        print(f'  .ds-{b}: {KNOWN[b].split(".")[0]}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
