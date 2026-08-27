#!/usr/bin/env python3
"""Build the /vs/ comparison pages from the brief's copy.

The three pages share their chrome with the blog posts and differ only in body
copy, so they are generated from one template rather than hand-assembled three
times. Kept in the repo because the copy will be edited again and hand-editing
three near-identical files is how they drift apart.

Chrome is lifted from landing/blog/*.html so nav, footer and the auth-aware
script stay identical — the brief says match the site, not restyle it.
"""
import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Page copy lives in the repo, not in a brief in someone's Downloads folder —
# a build that depends on a file outside version control is not reproducible.
BRIEFS = sorted((ROOT / 'content' / 'vs').glob('*.md'))
OUT = ROOT / 'landing' / 'vs'

PRO_CTA = 'Start Pro &mdash; $49.99/month'


def fix_href(h):
    """Site-relative links in the copy have to resolve from /vs/."""
    if h.startswith('/blog/'):
        return '../blog/' + h[len('/blog/'):] + '.html'
    if h.startswith('/vs/'):
        return h[len('/vs/'):] + '.html'
    if h == '/pph-software-alternative':
        return '../pph-software-alternative.html'
    return h


def inline(t):
    t = re.sub(r'\[([^\]]+)\]\(([^)]+)\)',
               lambda m: '<a href="' + fix_href(m.group(2)) + '"' +
                         (' target="_blank" rel="noopener nofollow"'
                          if m.group(2).startswith('http') else '') +
                         '>' + m.group(1) + '</a>', t)
    t = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', t)
    return t


def table(rows):
    cells = [[c.strip() for c in r.strip().strip('|').split('|')] for r in rows]
    head, body = cells[0], cells[2:]
    th = ''.join('<th>' + inline(c) + '</th>' for c in head)
    tb = ''.join('<tr>' + ''.join('<td>' + inline(c) + '</td>' for c in r) + '</tr>'
                 for r in body)
    return ('<div class="pph-cost-table-wrap"><table class="pph-cost-table">'
            '<thead><tr>' + th + '</tr></thead><tbody>' + tb + '</tbody></table></div>')


NUM_ITEM = re.compile(r'^\d+\. ')


def md_to_html(md):
    out, lines, i = [], md.split('\n'), 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith('# '):
            i += 1
            continue                                  # h1 lives in the article header
        if ln.startswith('## '):
            out.append('<h2>' + inline(ln[3:]) + '</h2>')
            i += 1
            continue
        if ln.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                rows.append(lines[i])
                i += 1
            out.append(table(rows))
            continue
        if NUM_ITEM.match(ln):
            items = []
            while i < len(lines) and NUM_ITEM.match(lines[i]):
                text = NUM_ITEM.sub('', lines[i])
                items.append('<li>' + inline(text) + '</li>')
                i += 1
            out.append('<ol>' + ''.join(items) + '</ol>')
            continue
        if ln.strip():
            para = [ln]
            i += 1
            while (i < len(lines) and lines[i].strip()
                   and not lines[i].startswith(('#', '|'))
                   and not NUM_ITEM.match(lines[i])):
                para.append(lines[i])
                i += 1
            out.append('<p>' + inline(' '.join(para)) + '</p>')
            continue
        i += 1
    return '\n                    '.join(out)


PAGE = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="apple-touch-icon" sizes="180x180" href="../assets/favicon_io/apple-touch-icon.png">
    <link rel="icon" type="image/png" sizes="32x32" href="../assets/favicon_io/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="../assets/favicon_io/favicon-16x16.png">
    <link rel="icon" type="image/x-icon" href="../assets/favicon_io/favicon.ico">
    <meta name="description" content="{meta}">
    <title>{title}</title>

    <!-- Open Graph -->
    <meta property="og:type" content="article">
    <meta property="og:url" content="https://bookisports.com/vs/{slug}.html">
    <meta property="og:title" content="{title}">
    <meta property="og:description" content="{meta}">
    <meta property="og:image" content="https://bookisports.com/assets/booki-og.jpg">

    <!-- Twitter Card -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="{title}">
    <meta name="twitter:description" content="{meta}">
    <meta name="twitter:image" content="https://bookisports.com/assets/booki-og.jpg">

    <link rel="canonical" href="https://bookisports.com/vs/{slug}.html">

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Space+Grotesk:wght@600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="../tokens.css">
    <link rel="stylesheet" href="../styles.css">
</head>
<body>
    <nav class="site-nav">
        <div class="container nav-content">
            <a href="../index.html" class="nav-logo">
                <img src="../assets/logo-booki-blk.svg" alt="Booki" />
            </a>
            <div class="nav-links">
                <a href="../features.html" class="nav-link">Features</a>
                <a href="../help/" class="nav-link">Help</a>
                <a href="../blog/" class="nav-link">Blog</a>
                <a href="../index.html#pricing" class="nav-link">Pricing</a>
            </div>
            <div class="nav-actions">
                <a href="../dashboard/login.html" class="btn-nav-login">Log In</a>
                <a href="../dashboard/" class="btn-primary btn-nav">{cta}</a>
            </div>
            <button class="nav-hamburger" aria-label="Toggle menu">
                <span></span><span></span><span></span>
            </button>
        </div>
        <div class="nav-mobile">
            <a href="../features.html" class="nav-link">Features</a>
            <a href="../help/" class="nav-link">Help</a>
            <a href="../blog/" class="nav-link">Blog</a>
            <a href="../index.html#pricing" class="nav-link">Pricing</a>
            <a href="../dashboard/login.html" class="nav-link">Log In</a>
            <a href="../dashboard/" class="btn-primary btn-nav-mobile">{cta}</a>
        </div>
    </nav>

    <main>
        <article class="blog-article">
            <div class="container">
                <header class="blog-article-header">
                    <a href="../pph-software-alternative.html" class="blog-back-link">&larr; PPH software alternative</a>
                    <h1>{h1}</h1>
                    <div class="blog-article-meta">
                        <span>August 26, 2026</span>
                        <span class="blog-meta-sep">&middot;</span>
                        <span>Comparison</span>
                    </div>
                </header>

                <div class="blog-prose">
                    {body}

                    <div class="blog-related">
                        <p class="blog-related-title">Keep reading</p>
                        {related}
                    </div>
                </div>
            </div>
        </article>
    </main>

{footer}
</body>
</html>
'''

RELATED = {
    'perhead-cr': [
        ('../pph-software-alternative.html', 'PPH software alternative'),
        ('realbookies.html', 'Booki vs RealBookies'),
        ('ace-per-head.html', 'Booki vs Ace Per Head'),
        ('../blog/pay-per-head-pricing-breakdown.html', 'Pay per head pricing in 2026'),
    ],
    'realbookies': [
        ('../pph-software-alternative.html', 'PPH software alternative'),
        ('perhead-cr.html', 'Booki vs PerHead.CR'),
        ('payperhead.html', 'Booki vs PayPerHead.com'),
        ('../blog/best-pph-software-small-bookies.html', 'Best PPH software for small bookies'),
    ],
    'price-per-player': [
        ('../pph-software-alternative.html', 'PPH software alternative'),
        ('perhead-cr.html', 'Booki vs PerHead.CR'),
        ('ace-per-head.html', 'Booki vs Ace Per Head'),
        ('../blog/best-bookie-software-small-books.html', 'Best bookie software for small books'),
    ],
    'ace-per-head': [
        ('../pph-software-alternative.html', 'PPH software alternative'),
        ('payperhead.html', 'Booki vs PayPerHead.com'),
        ('perhead-cr.html', 'Booki vs PerHead.CR'),
        ('../blog/pay-per-head-pricing-breakdown.html', 'Pay per head pricing in 2026'),
    ],
    'payperhead': [
        ('../pph-software-alternative.html', 'PPH software alternative'),
        ('ace-per-head.html', 'Booki vs Ace Per Head'),
        ('ace-per-head.html', 'Booki vs Ace Per Head'),
        ('../blog/pay-per-head-pricing-breakdown.html', 'Pay per head pricing in 2026'),
    ],
}


def main():
    blocks = []
    for b in BRIEFS:
        if not b.exists():
            continue
        blocks += re.findall(r'### `/vs/([a-z-]+)`\n(?:.*?)```\n(.*?)\n```', b.read_text(), re.S)
    assert len(blocks) >= 3, [b[0] for b in blocks]

    footer = (ROOT / 'landing' / 'blog' / 'pay-per-head-pricing-breakdown.html').read_text()
    footer = footer[footer.index('    <footer class="footer">'):footer.index('</body>')].rstrip()

    OUT.mkdir(exist_ok=True)
    for slug, body in blocks:
        fm = re.search(r'seo_title: "([^"]+)"\s*\nmeta_description: "([^"]+)"', body)
        title, meta = fm.group(1), fm.group(2)
        h1 = re.search(r'^# (.+)$', body, re.M).group(1)
        md = body[body.index('\n# ') + 1:]

        # CORRECTION to the brief: futures are graded MANUALLY. grading.ts
        # returns "Outright/futures market: manual grading required." Claiming
        # automated futures grading in a table cell scored against a competitor
        # would be a false product claim on a page whose whole argument is
        # honesty.
        md = md.replace('Moneylines, spreads, totals, parlays, futures',
                        'Moneylines, spreads, totals, parlays. Futures graded manually.')
        md = md.replace('Automated: ML, spread, totals, parlays, futures',
                        'Automated: ML, spread, totals, parlays. Futures manual.')
        md = md.replace('ML, spread, totals, parlays, futures',
                        'ML, spread, totals, parlays. Futures manual.')
        md = md.replace('automated grading (moneylines, spreads, totals, parlays, futures)',
                        'automated grading (moneylines, spreads, totals, parlays; futures graded manually)')
        md = md.replace('automated grading for moneylines, spreads, totals, parlays, and futures',
                        'automated grading for moneylines, spreads, totals and parlays (futures are graded manually)')

        related = '\n                        '.join(
            '<a href="' + href + '" class="blog-related-link">' + label + '</a>'
            for href, label in RELATED[slug])

        page = PAGE.format(slug=slug, title=title, meta=meta, h1=h1,
                           cta=PRO_CTA, body=md_to_html(md),
                           related=related, footer=footer)
        (OUT / (slug + '.html')).write_text(page)
        print('  wrote landing/vs/' + slug + '.html  (' + str(len(page)) + ' bytes)')


if __name__ == '__main__':
    main()
