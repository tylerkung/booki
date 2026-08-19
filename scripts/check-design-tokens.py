#!/usr/bin/env python3
"""
Design-token linter for the web dashboard.

Fails when a style value is written as a literal instead of a token. The point
is that changing a token in dashboard.css :root should change the app, so any
literal that bypasses the token layer is a value nobody can restyle
programmatically -- and, historically, a value that silently goes stale. Before
this existed the dashboard carried four dead orange literals and a danger tint
frozen at a red that had not been --danger for months.

    python3 scripts/check-design-tokens.py            # report + exit 1 on drift
    python3 scripts/check-design-tokens.py --summary  # counts only

Add to a pre-commit hook or CI to keep the audit from being a manual job.
"""
import re, sys, os, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DASH = os.path.join(ROOT, "landing", "dashboard")
CSS = os.path.join(DASH, "dashboard.css")

# --- deliberate, documented exceptions -------------------------------------
ALLOW = {
    # value-or-pattern            : why it is allowed
    "font-size: 0":               "layout reset, collapses inline-block whitespace",
    "border-radius: 1px":         "hairline, below the smallest radius step",
    "@media":                     "custom properties are invalid in media conditions",
    "var(--":                     "already a token",
}
# properties that must never carry a raw literal
CHECKS = [
    ("colour",     r'\b(?:color|background|background-color|border(?:-(?:top|right|bottom|left))?(?:-color)?|box-shadow|fill|stroke|outline(?:-color)?)\s*:\s*([^;{}]+)',
                   r'#[0-9a-fA-F]{3,8}\b|rgba?\(\s*\d'),
    ("font-size",  r'\bfont-size\s*:\s*([^;{}]+)',            r'\b\d+(?:\.\d+)?(?:px|rem|em)\b'),
    ("font-weight",r'\bfont-weight\s*:\s*([^;{}]+)',          r'\b[1-9]00\b'),
    ("radius",     r'\bborder-radius\s*:\s*([^;{}]+)',        r'\b\d+(?:px|%)\b'),
    ("z-index",    r'\bz-index\s*:\s*([^;{}]+)',              r'\b-?\d+\b'),
    ("transition", r'\btransition(?:-duration)?\s*:\s*([^;{}]+)', r'\b\d+(?:\.\d+)?m?s\b'),
    ("line-height", r'\bline-height\s*:\s*([^;{}]+)',        r'\b\d+(?:\.\d+)?\b'),
]
SPACING_PROPS = (r'(?:margin|padding|gap|top|right|bottom|left|width|height'
                 r'|min-width|min-height|max-width|max-height|inset)'
                 r'(?:-(?:top|right|bottom|left))?')

def strip_root_and_comments(css):
    """the :root block defines the tokens, so literals there are the point"""
    m = re.search(r':root\s*\{.*?\n\}', css, re.S)
    body = css[m.end():] if m else css
    return re.sub(r'/\*.*?\*/', '', body, flags=re.S)

def allowed(line):
    return any(a in line for a in ALLOW if a != "var(--")

def scan_css(path):
    raw = open(path).read()
    m = re.search(r':root\s*\{.*?\n\}', raw, re.S)
    offset = raw[:m.end()].count("\n") if m else 0
    body = strip_root_and_comments(raw)
    out = []
    for i, line in enumerate(body.split("\n"), offset + 1):
        if allowed(line):
            continue
        for name, prop_pat, lit_pat in CHECKS:
            for mm in re.finditer(prop_pat, line):
                val = mm.group(1)
                val = re.sub(r'var\([^()]*(?:\([^()]*\)[^()]*)*\)', '', val)  # drop token refs
                for bad in re.finditer(lit_pat, val):
                    out.append((os.path.relpath(path, ROOT), i, name,
                                bad.group(0), line.strip()[:78]))
        for mm in re.finditer(rf'\b{SPACING_PROPS}\s*:\s*([^;{{}}]+)', line):
            val = re.sub(r'var\([^()]*\)', '', mm.group(1))
            for px in re.findall(r'(\d+)px', val):
                n = int(px)
                if n % 4 and n not in (1, 2):
                    out.append((os.path.relpath(path, ROOT), i, "spacing",
                                f"{n}px off 4pt grid", line.strip()[:78]))
    return out

def scan_inline(path):
    src = open(path).read()
    out = []
    line_of = lambda pos: src[:pos].count("\n") + 1
    for m in re.finditer(r'style="([^"]*)"', src):
        decls, ln = m.group(1), line_of(m.start())
        for name, prop_pat, lit_pat in CHECKS:
            for mm in re.finditer(prop_pat, decls):
                val = re.sub(r'var\([^()]*(?:\([^()]*\)[^()]*)*\)', '', mm.group(1))
                for bad in re.finditer(lit_pat, val):
                    out.append((os.path.relpath(path, ROOT), ln, name,
                                bad.group(0), decls[:78]))
        # margin/padding/gap must come from the spacing scale, not a literal.
        # Dimensions (width/height/...) are deliberately excluded: a 90px column
        # or a 28px avatar is a size, not spacing, and belongs in a named
        # dimension token instead of being forced onto the 4pt grid.
        for mm in re.finditer(r'\b(?:margin|padding|gap|row-gap|column-gap)'
                              r'(?:-(?:top|right|bottom|left))?\s*:\s*([^;]+)', decls):
            val = re.sub(r'var\([^()]*\)', '', mm.group(1))
            for px in re.findall(r'(\d+)px', val):
                out.append((os.path.relpath(path, ROOT), ln, "spacing",
                            f"{px}px not from the scale", decls[:78]))
    return out

DIMPROP = (r'(?<![-\w])(?:width|height|min-width|min-height|max-width'
           r'|max-height|flex-basis)\s*:\s*([^;{}"\']+)')

def scan_dimensions():
    """A dimension used three or more times is a design decision and needs a
    name. A one-off container width is a bespoke layout constraint — naming it
    would move the number without making it reusable, so it stays a literal.

    Skeleton geometry is exempt: a shimmer bar is 100px wide because that is
    roughly how wide a name looks, and every such value is deliberately
    arbitrary. Tokenising them would invent meaning that is not there."""
    seen = collections.defaultdict(list)
    for path in (CSS, os.path.join(DASH, "index.html"), os.path.join(DASH, "login.html")):
        raw = open(path).read()
        if path.endswith(".css"):
            m = re.search(r':root\s*\{.*?\n\}', raw, re.S)
            chunks = [(raw[:m.end()].count("\n") if m else 0,
                       re.sub(r'/\*.*?\*/', '', raw[m.end():] if m else raw, flags=re.S))]
        else:
            chunks = []
            for mm in re.finditer(r'<[^>]*\sstyle="([^"]*)"[^>]*>', raw):
                ctx = raw[max(0, mm.start() - 400):mm.end()]
                if re.search(r'skeleton|shimmer|sk-', ctx[-500:], re.I):
                    continue
                chunks.append((raw[:mm.start()].count("\n") + 1, mm.group(1)))
        for base, text in chunks:
            for d in re.finditer(DIMPROP, text):
                val = re.sub(r'var\([^()]*\)', '', d.group(1))
                ln = base + text[:d.start()].count("\n")
                for px in re.findall(r'(\d+)px', val):
                    seen[int(px)].append((os.path.relpath(path, ROOT), ln, d.group(0).strip()[:70]))
    out = []
    for px, uses in seen.items():
        if len(uses) >= 3:
            for path, ln, ctx in uses:
                out.append((path, ln, "dimension",
                            f"{px}px used {len(uses)}× — needs a name", ctx))
    return out

# Concepts the dashboard and the design-system page both define, under
# different names. They are two hand-maintained copies, so nothing structural
# stops them drifting — this check is what stops it. If a pair legitimately
# diverges (as the motion scales do), remove it here and say why on the page.
MIRRORED = [
    ("--bg", "--background"), ("--bg-card", "--card"), ("--bg-elevated", "--elevated"),
    ("--border", "--border"), ("--divider", "--divider"),
    ("--text-primary", "--text-primary"), ("--text-secondary", "--text-secondary"),
    ("--text-muted", "--text-muted"), ("--accent", "--accent"),
    ("--accent-secondary", "--accent-secondary"), ("--accent-tertiary", "--accent-tertiary"),
    ("--gold", "--gold"), ("--danger", "--danger"), ("--warning", "--warning"),
    ("--scheduled", "--scheduled"), ("--final-status", "--final"),
    ("--radius", "--radius"), ("--radius-sm", "--radius-sm"), ("--radius-full", "--radius-full"),
    ("--s-xs", "--s1"), ("--s-sm", "--s2"), ("--s-md", "--s3"), ("--s-lg", "--s4"),
    ("--s-xl", "--s6"), ("--s-xxl", "--s8"), ("--s-xxxl", "--s12"),
]
DS_CSS = os.path.join(ROOT, "landing", "design", "ds.css")
TOKENS = os.path.join(ROOT, "landing", "tokens.css")
SITE_CSS = os.path.join(ROOT, "landing", "styles.css")
THEME = os.path.join(ROOT, "Booki", "Theme.swift")

# Values a consumer stylesheet is allowed to define itself, with the reason.
# Everything else in a consumer :root must be an alias — `var(--canonical)`.
CONSUMER_LOCAL = {
    "--chrome": "design-system page chrome, not a product surface",
    "--rail": "design-system page nav width, not a product surface",
    "--demo-radius": "design-system specimen box; sits above --radius so specimens keep their true radius",
}

# tokens.css name -> Theme.swift constant. The iOS app cannot link CSS, so this
# is what keeps the third consumer honest.
THEME_MAP = {
    "--background": "background", "--card": "cardBackground",
    "--elevated": "elevatedBackground", "--border": "border",
    "--divider": "divider", "--text-primary": "textPrimary",
    "--text-secondary": "textSecondary", "--text-muted": "textMuted",
    "--accent": "accent", "--accent-secondary": "accentSecondary",
    "--accent-tertiary": "accentTertiary", "--gold": "gold",
    "--danger": "danger", "--warning": "warning",
    "--scheduled": "scheduled", "--final": "finalStatus",
}

def root_tokens(path):
    src = open(path).read()
    m = re.search(r':root\s*\{.*?\n\}', src, re.S)
    if not m: return {}
    return {a: b.strip() for a, b in re.findall(r'(--[\w-]+)\s*:\s*([^;]+);', m.group(0))}

def scan_radius_tokens():
    """border-radius must come from the radius scale.

    A spacing token in a radius slot is valid CSS and can be exactly the right
    number by accident: .ds-seg__item used var(--s2), which is 8px, so it looked
    correct while bypassing the radius scale entirely — and would not have
    followed a radius change. This cannot live in CHECKS, because scan_css
    strips var() before matching and a pattern looking for var() never fires.
    """
    out = []
    for path in (CSS, DS_CSS):
        if not os.path.exists(path): continue
        # blank comments rather than delete them, so reported line numbers
        # still match the real file
        src = re.sub(r'/\*.*?\*/',
                     lambda m: "\n" * m.group(0).count("\n"),
                     open(path).read(), flags=re.S)
        for mm in re.finditer(r'border-radius\s*:\s*([^;{}]+)', src):
            for ref in re.finditer(r'var\(\s*(--[\w-]+)', mm.group(1)):
                if "radius" in ref.group(1):
                    continue
                out.append((os.path.relpath(path, ROOT),
                            src[:mm.start()].count("\n") + 1, "radius-token",
                            f"{ref.group(1)} is not from the radius scale",
                            mm.group(0).strip()[:70]))
    return out

def scan_drift():
    """Theme.swift is the one consumer that cannot link tokens.css, so compare
    its palette against the canonical block instead."""
    out = []
    if not (os.path.exists(TOKENS) and os.path.exists(THEME)):
        return out
    tok = root_tokens(TOKENS)
    swift = {m.group(1): "#" + m.group(2).upper() for m in
             re.finditer(r'static let (\w+)\s*=\s*Color\(hex:\s*0x([0-9A-Fa-f]{6})\)',
                         open(THEME).read())}
    for name, const in THEME_MAP.items():
        if name in tok and const in swift and tok[name].upper() != swift[const]:
            out.append((os.path.relpath(THEME, ROOT), 0, "drift",
                        f"Theme.{const} = {swift[const]} but {name} = {tok[name]}",
                        "iOS palette disagrees with tokens.css"))
    return out

def scan_consumer_literals():
    """A consumer stylesheet may only alias. Defining a value there recreates
    the second-source-of-truth problem this architecture removed."""
    out = []
    for path in (CSS, DS_CSS, SITE_CSS):
        if not os.path.exists(path): continue
        src = open(path).read()
        m = re.search(r':root\s*\{.*?\n\}', src, re.S)
        if not m: continue
        base = src[:m.start()].count("\n") + 1
        for d in re.finditer(r'(--[\w-]+)\s*:\s*([^;]+);', m.group(0)):
            name, val = d.group(1), d.group(2).strip()
            if name in CONSUMER_LOCAL or val.startswith("var("):
                continue
            out.append((os.path.relpath(path, ROOT),
                        base + m.group(0)[:d.start()].count("\n"), "second-source",
                        f"{name} defines a value ({val[:28]}) instead of aliasing",
                        "move it to landing/tokens.css"))
    return out

def scan_unresolved():
    """A var() with no fallback that names nothing renders as an invalid
    declaration — silently, with no console error. .games-sport-card sat
    transparent for months on a var(--card-bg) that was never defined."""
    defined = set(root_tokens(TOKENS))
    out = []
    for consumer, extras in (
        (CSS, ["landing/dashboard/index.html", "landing/dashboard/login.html"]),
        (DS_CSS, ["landing/design/index.html", "landing/design/ds-content.js"]),
        # The marketing stylesheet is the fourth consumer. Only the
        # architecture checks apply to it — its own values are not linted yet,
        # because it predates the token layer and uses a rem-based scale.
        (SITE_CSS, []),
    ):
        if not os.path.exists(consumer): continue
        # A custom property may be declared on ANY selector, not just :root —
        # component-scoped ones like --avatar-size are how a variant passes a
        # value down to a rule it does not own. Collect every declaration.
        local = set(re.findall(r'(--[\w-]+)\s*:', open(consumer).read()))
        known = defined | local
        for rel in [os.path.relpath(consumer, ROOT)] + extras:
            fp = os.path.join(ROOT, rel)
            if not os.path.exists(fp): continue
            src = open(fp).read()
            for mm in re.finditer(r'var\(\s*(--[\w-]+)\s*(,)?', src):
                if mm.group(2) or mm.group(1) in known:
                    continue
                out.append((rel, src[:mm.start()].count("\n") + 1, "unresolved",
                            f"var({mm.group(1)}) names no token",
                            "declaration is silently invalid"))
    return out

def main():
    summary = "--summary" in sys.argv
    findings = scan_css(CSS)
    for f in ("index.html", "login.html"):
        findings += scan_inline(os.path.join(DASH, f))
    findings += scan_dimensions()
    findings += scan_radius_tokens()
    findings += scan_drift()
    findings += scan_consumer_literals()
    findings += scan_unresolved()

    if not findings:
        print("design tokens: clean — every styled value routes through a token")
        return 0

    by_cat = {}
    for f in findings:
        by_cat.setdefault(f[2], []).append(f)
    print(f"design tokens: {len(findings)} literal(s) bypassing the token layer\n")
    for cat in sorted(by_cat, key=lambda c: -len(by_cat[c])):
        rows = by_cat[cat]
        print(f"  {cat}  ({len(rows)})")
        if not summary:
            for path, ln, _, bad, ctx in rows[:12]:
                print(f"    {path}:{ln}  {bad}")
                print(f"        {ctx}")
            if len(rows) > 12:
                print(f"    … and {len(rows)-12} more")
        print()
    print("Add a token to dashboard.css :root and reference it, or document the")
    print("exception in ALLOW at the top of this script.")
    return 1

if __name__ == "__main__":
    sys.exit(main())
