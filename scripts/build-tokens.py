#!/usr/bin/env python3
"""Assemble landing/tokens.css from the design-system source files.

The tokens were split so a second product can take `design-system/core.css`
unchanged and supply its own brand file. Booki still loads ONE stylesheet —
every page links tokens.css directly and there is no build step in this repo,
so splitting the served file would mean editing 20-odd pages and paying an
extra request on each.

So tokens.css is generated, and `--check` asserts it is current. Without that
assertion the split would quietly become two copies of the same values, which
is the drift the split exists to prevent.

    python3 scripts/build-tokens.py           # regenerate
    python3 scripts/build-tokens.py --check   # fail if stale
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = ROOT / 'design-system' / 'core.css'
BRAND = ROOT / 'design-system' / 'brand-booki.css'
OUT = ROOT / 'landing' / 'tokens.css'

# Emission order. Deliberately explicit rather than derived from the files:
# the order tokens appear in is reviewable here, and a section that silently
# stopped being emitted would otherwise be invisible.
ORDER = ['colour', 'channel', 'opacity', 'fills', 'fill-fg', 'wave', 'spacing',
         'radius', 'type-ios', 'type-web', 'tracking', 'cta', 'elevation',
         'motion', 'layers', 'dimensions']
RULES = ROOT / 'design-system' / 'core.rules.css'

BANNER = """/* ============================================================================
   Booki design tokens — GENERATED, do not edit by hand.

   Source: design-system/core.css (structural) + design-system/brand-booki.css
   (colour) + design-system/core.rules.css (the reduced-motion and focus rules).
   Regenerate with scripts/build-tokens.py; check-all.sh fails if this file is
   stale.

   Edit the source files, not this one. An edit here is overwritten by the next
   build and, worse, silently diverges the two products that share core.css.
   ============================================================================ */

:root {
"""

SECTION_RE = re.compile(r'/\* ── ([^─]+?)\s*──')


def root_sections(path):
    """Labelled blocks from a file whose whole body is one :root { ... }.

    Only ever called on files that contain exactly one brace pair, so it strips
    the wrapper by position rather than by counting braces. An earlier version
    counted, and ate the closing braces of an @media block along with an entire
    focus rule.
    """
    text = path.read_text()
    body = text[text.index(':root {') + len(':root {'):]
    body = body[:body.rindex('}')]
    out, cur, buf = {}, None, []
    for line in body.split('\n'):
        m = SECTION_RE.search(line)
        if m:
            if cur:
                out[cur] = '\n'.join(buf).rstrip()
            cur, buf = slug(m.group(1)), [line]
        elif cur is not None:
            buf.append(line)
    if cur:
        out[cur] = '\n'.join(buf).rstrip()
    return out


def slug(label):
    s = label.strip().lower()
    if s.startswith('tinted'):
        return 'fills'
    if s.startswith('fill foreground'):
        return 'fill-fg'
    if s.startswith('type'):
        return 'type-ios' if 'ios' in s else 'type-web'
    if s.startswith('cta'):
        return 'cta'
    return s.split()[0]


def build():
    have = {}
    have.update(root_sections(CORE))
    have.update(root_sections(BRAND))
    missing = [x for x in ORDER if x not in have]
    if missing:
        sys.exit('build-tokens: sections missing from source: %s' % ', '.join(missing))
    body = '\n\n'.join(have[x] for x in ORDER)
    rules = RULES.read_text()
    rules = rules[rules.index('*/') + 2:].strip('\n')   # drop the file's own banner
    return BANNER + body + '\n}\n\n' + rules + '\n\n'


def main():
    built = build()
    if '--check' in sys.argv:
        current = OUT.read_text() if OUT.exists() else ''
        if current != built:
            print('tokens: landing/tokens.css is STALE — run scripts/build-tokens.py')
            print('  it is generated from design-system/core.css + brand-booki.css')
            sys.exit(1)
        n = len(re.findall(r'^\s*--[a-z0-9-]+:', built, re.M))
        print('tokens: clean — landing/tokens.css matches its source (%d declarations)' % n)
        return
    OUT.write_text(built)
    print('tokens: wrote %s (%d lines)' % (OUT.relative_to(ROOT), built.count('\n')))


if __name__ == '__main__':
    main()
