#!/usr/bin/env python3
"""A page that uses a webfont must load it.

CSS naming a font the page never requests does not fail — the browser silently
falls back, so the text renders in something else and looks plausible. That is
how --font-mono came to resolve to IBM Plex Mono on the dashboard and to SF Mono
(via ui-monospace, on macOS only) on the marketing and design-system sites: the
token led with Plex, but only two pages ever loaded it. Odds rendered in one
typeface and the design system documented another, and nothing anywhere said so.

Checks each HTML page: for every webfont family named in a stylesheet it links,
is that family requested in the page's Google Fonts URL? A system-stack fallback
(ui-monospace, -apple-system, sans-serif) is fine and not flagged — the point is
a NAMED family that has to be downloaded.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / 'landing'
# Families that must be downloaded. A system font needs no request.
WEBFONTS = {'Inter', 'Space Grotesk', 'IBM Plex Mono', 'IBM Plex Sans'}


def linked_css(html_path, html):
    out = []
    for href in re.findall(r'<link[^>]+rel="stylesheet"[^>]+href="([^"]+)"', html):
        if href.startswith('http'):
            continue
        p = (html_path.parent / href.split('?')[0]).resolve()
        if p.exists():
            out.append(p)
    return out


def font_selectors(css, tokens):
    """Selectors whose rule sets a downloadable family, with that family.

    Custom properties are resolved through the WHOLE chain, not one level.
    ds.css declares `--mono: var(--font-mono)` and then uses `var(--mono)` in 23
    rules; following only one hop misses every one of them, which made the first
    version of this check unable to fire at all.
    """
    decls = dict(re.findall(r'(--[\w-]+)\s*:\s*([^;{}]+);', tokens + '\n' + css))

    def resolve(value, depth=0):
        if depth > 8:
            return set()
        fams = {p.strip().strip('\'"') for p in value.split(',')} & WEBFONTS
        for tok in re.findall(r'var\((--[\w-]+)\)', value):
            if tok in decls:
                fams |= resolve(decls[tok], depth + 1)
        return fams

    out = []
    for m in re.finditer(r'([^{}]+)\{([^{}]*)\}', css):
        sel, body = m.group(1).strip().split('\n')[-1].strip(), m.group(2)
        fm = re.search(r'font-family:\s*([^;{}]+)', body)
        if not fm:
            continue
        fams = resolve(fm.group(1))
        if fams:
            out.append((sel, fams))
    return out


def page_uses(sel, html):
    """Does this page contain markup the selector could match?

    Deliberately loose — a class name appearing anywhere in the markup counts.
    The alternative is attributing every rule in a shared stylesheet to every
    page that links it, which reported 31 pages for a rule that exists on one.
    """
    if re.match(r'^(html|body|\*|:root)\b', sel):
        return True
    classes = re.findall(r'\.([a-zA-Z][\w-]*)', sel)
    tags = re.findall(r'^([a-z]+)', sel)
    if classes:
        return any(('"' + c) in html or (' ' + c + '"') in html or (' ' + c + ' ') in html
                   for c in classes)
    return bool(tags)


def main():
    problems = []
    tokens = (ROOT / 'tokens.css').read_text() if (ROOT / 'tokens.css').exists() else ''

    for html_path in sorted(ROOT.rglob('*.html')):
        html = html_path.read_text()
        gf = ' '.join(re.findall(r'fonts\.googleapis\.com[^"\']*', html))
        requested = {f for f in WEBFONTS if f.replace(' ', '+') in gf}

        used = set()
        sheets = [c.read_text() for c in linked_css(html_path, html)]
        sheets += re.findall(r'<style[^>]*>(.*?)</style>', html, re.S)
        for css in sheets:
            for sel, fams in font_selectors(css, tokens):
                if page_uses(sel, html):
                    used |= fams

        missing = used - requested
        if missing:
            rel = html_path.relative_to(ROOT)
            problems.append(f'{rel}: uses {", ".join(sorted(missing))} but does not request it')

    if problems:
        print(f'font loading: {len(problems)} page(s) use a webfont they do not load\n')
        for p in problems:
            print('  ' + p)
        print('\nAdd the family to the page\'s fonts.googleapis.com request, or stop '
              'referencing it.\nA missing webfont does not error — it silently falls back.')
        return 1

    print('font loading: clean — every page requests the webfonts its CSS names')
    return 0


if __name__ == '__main__':
    sys.exit(main())
