/**
 * Knowledge base contents.
 *
 * Single source of truth for the left rail. Adding an article means adding a
 * line here — the rail renders itself on every page, so a new article never
 * requires editing the others. (Static site, so this is the cheapest way to
 * avoid the sidebar drifting page to page.)
 */
const KB_CONTENTS = [
    {
        group: 'Getting started',
        items: [
            { href: 'index.html', title: 'Overview' },
            { href: 'how-to-run-your-group.html', title: 'How to run your group' },
        ],
    },
    // Planned — see tasks/prd-knowledge-base.md
    // {
    //     group: 'How odds work',
    //     items: [
    //         { href: 'how-odds-work.html', title: 'Where odds come from' },
    //     ],
    // },
    // {
    //     group: 'Limits and rules',
    //     items: [
    //         { href: 'credit-and-win-limits.html', title: 'Credit and win limits' },
    //         { href: 'how-picks-are-graded.html', title: 'How picks are graded' },
    //     ],
    // },
];

(function renderKbRail() {
    const rail = document.getElementById('kb-rail');
    if (!rail) return;

    // Match the current page whether it was reached as /help/, /help/ or
    // /help/index.html — the dev server and Netlify differ on trailing slashes.
    const path = window.location.pathname.replace(/\/$/, '/index.html');
    const current = path.split('/').pop() || 'index.html';

    const markup = KB_CONTENTS.map((section) => {
        const links = section.items.map((item) => {
            const isCurrent = item.href === current;
            return `<li><a href="${item.href}"${isCurrent ? ' class="is-current" aria-current="page"' : ''}>${item.title}</a></li>`;
        }).join('');
        return `<div class="kb-group">
            <p class="kb-group-label">${section.group}</p>
            <ul class="kb-links">${links}</ul>
        </div>`;
    }).join('');

    rail.innerHTML = `<p class="kb-rail-title">Contents</p>${markup}`;

    // Mobile: the rail starts collapsed behind a toggle.
    const toggle = document.getElementById('kb-rail-toggle');
    if (toggle) {
        const collapse = () => {
            if (window.matchMedia('(max-width: 900px)').matches) rail.hidden = true;
        };
        collapse();
        window.addEventListener('resize', () => {
            if (!window.matchMedia('(max-width: 900px)').matches) rail.hidden = false;
        });
        toggle.addEventListener('click', () => { rail.hidden = !rail.hidden; });
    }
})();
