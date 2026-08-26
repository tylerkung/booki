#!/usr/bin/env python3
"""Motion must be tokenised, fast, and respect prefers-reduced-motion.

WHY. --ease was defined as the literal keyword `ease` and referenced zero
times, so all 66 transitions in the product fell through to the CSS default —
which is also `ease`, a curve that ACCELERATES before settling. Every hover
started slowly, and that contradicted the system's own anti-patterns page,
which already required critically damped motion. Nothing caught it because a
transition with no timing function is valid CSS and looks fine in review.

Three rules:

  1. No raw duration in a transition. Durations belong to the four --dur-*
     tokens, which is also what makes rule 3 work.
  2. No transition longer than MAX_MS for interaction. Emil Kowalski's argument,
     and the reason 0.12s reads as a response while 0.3s reads as a delay.
     Entrances are exempt via --dur-entrance, because a viewer is watching the
     motion rather than the result.
  3. Any stylesheet with @keyframes must have a prefers-reduced-motion block.
     Transitions are covered centrally by the token override in tokens.css;
     keyframes do not read tokens and must opt in per file.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKENS = ROOT / 'landing' / 'tokens.css'
SHEETS = ['landing/dashboard/dashboard.css', 'landing/styles.css',
          'landing/admin/admin.css', 'landing/design/ds.css',
          'landing/help/help.css']
MAX_MS = 300
ENTRANCE = '--dur-entrance'


def main():
    problems = []

    tok = TOKENS.read_text() if TOKENS.exists() else ''
    if 'prefers-reduced-motion' not in tok:
        problems.append(
            'tokens.css has no reduced-motion override. Re-pointing the --dur-* '
            'tokens there covers every surface at once; a block per stylesheet '
            'is the pattern that left three of four uncovered.')
    if re.search(r'--ease:\s*ease\s*;', tok):
        problems.append(
            'tokens.css still defines --ease as the bare keyword `ease`, which '
            'accelerates before settling. Use a decelerating curve.')

    # duration token values, for the speed check
    durs = {m.group(1): float(m.group(2))
            for m in re.finditer(r'(--dur-[\w-]+):\s*([\d.]+)s', tok)}

    for sheet in SHEETS:
        p = ROOT / sheet
        if not p.exists():
            continue
        src = re.sub(r'/\*.*?\*/', '', p.read_text(), flags=re.S)

        for m in re.finditer(r'transition:\s*([^;]+);', src):
            ln = src[:m.start()].count('\n') + 1
            val = m.group(1)
            raw = re.findall(r'(?<![\w-])(\d*\.?\d+)s(?![\w-])', val)
            if raw:
                problems.append(
                    f'{sheet}:{ln}  raw duration {raw[0]}s — use a --dur-* token')
            for t in re.findall(r'var\((--dur-[\w-]+)\)', val):
                if t == ENTRANCE:
                    continue
                if durs.get(t, 0) * 1000 > MAX_MS:
                    problems.append(
                        f'{sheet}:{ln}  {t} is {durs[t]}s, over {MAX_MS}ms for '
                        f'an interaction — use {ENTRANCE} if this is an entrance')

        if '@keyframes' in src and 'prefers-reduced-motion' not in src:
            n = len(re.findall(r'@keyframes', src))
            problems.append(
                f'{sheet}  defines {n} @keyframes but has no '
                f'prefers-reduced-motion block (keyframes do not read the '
                f'duration tokens)')

    if problems:
        print(f'motion: {len(problems)} problem(s)\n')
        for x in problems[:14]:
            print(f'  {x}')
        if len(problems) > 14:
            print(f'  … and {len(problems)-14} more')
        return 1

    print(f'motion: clean — all transitions tokenised, none over {MAX_MS}ms, '
          f'keyframes covered by reduced-motion')
    return 0


if __name__ == '__main__':
    sys.exit(main())
