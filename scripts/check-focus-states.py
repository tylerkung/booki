#!/usr/bin/env python3
"""Interactive elements must have a visible focus state.

WHY THIS EXISTS. The design system specified "2px accent, 2px offset, on every
interactive element, applied through :focus-visible" from the day it was
written. For months the product had 60 :hover rules and ZERO :focus-visible
rules — all three that existed lived inside ds.css, the design system's own
documentation page, and --shadow-focus was referenced nowhere at all.

Nothing failed. Nothing looked wrong in review, because the defect was an
absence. This is the check that makes the absence visible.

Two rules:

  1. A base :focus-visible rule must exist in tokens.css, which every surface
     loads. Requiring each stylesheet to carry its own is what caused the gap.
  2. No stylesheet may set `outline: none` on a :focus or :focus-visible
     selector without providing a replacement in the same rule (a box-shadow or
     a border-color change). The design system already words this exactly:
     "never removed without a replacement".
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKENS = ROOT / 'landing' / 'tokens.css'
SHEETS = ['landing/dashboard/dashboard.css', 'landing/styles.css',
          'landing/admin/admin.css', 'landing/design/ds.css',
          'landing/help/help.css']


def rules(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    for m in re.finditer(r'([^{}]+)\{([^{}]*)\}', text):
        yield m.group(1).strip().split('\n')[-1].strip(), m.group(2), \
            text[:m.start()].count('\n') + 1


def main():
    problems = []

    if not TOKENS.exists():
        print('focus states: tokens.css missing')
        return 1
    tok = TOKENS.read_text()
    if ':focus-visible' not in tok:
        problems.append(
            'tokens.css has no base :focus-visible rule. Every surface loads '
            'this file; a per-stylesheet rule is the pattern that failed before.')

    for sheet in SHEETS:
        p = ROOT / sheet
        if not p.exists():
            continue
        for sel, body, ln in rules(p.read_text()):
            if not re.search(r'outline:\s*(none|0)\b', body):
                continue
            if ':focus' not in sel:
                continue  # resting-state reset, harmless on its own
            has_replacement = (
                re.search(r'box-shadow:\s*(?!none)', body)
                or re.search(r'border(?:-color)?:\s*(?!none)', body)
                or re.search(r'outline-offset', body))
            if not has_replacement:
                problems.append(
                    f'{sheet}:{ln}  {sel[:50]} removes the outline on focus '
                    f'with no visible replacement')

    if problems:
        print(f'focus states: {len(problems)} problem(s)\n')
        for x in problems:
            print(f'  {x}')
        print('\nThe rule is "never removed without a replacement" — a '
              'box-shadow or border-color change counts, nothing does not.')
        return 1

    count = tok.count(':focus-visible')
    print(f'focus states: clean — base rule present in tokens.css '
          f'({count} :focus-visible selectors), no unreplaced outline removals')
    return 0


if __name__ == '__main__':
    sys.exit(main())
