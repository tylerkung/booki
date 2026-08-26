/**
 * Rail + pane switching. One section on screen at a time, addressable by hash
 * so a section can be linked to directly.
 */
(function () {
  const nav = document.getElementById('ds-nav-list');
  const main = document.getElementById('ds-main');

  DS_SECTIONS.forEach(s => {
    const a = document.createElement('a');
    a.className = 'ds-link';
    a.href = '#' + s.id;
    a.textContent = s.label;
    a.dataset.target = s.id;
    nav.appendChild(a);

    const pane = document.createElement('section');
    pane.className = 'ds-section';
    pane.id = 'pane-' + s.id;
    pane.innerHTML = s.html;
    main.appendChild(pane);
  });

  function show(id) {
    const known = DS_SECTIONS.some(s => s.id === id) ? id : DS_SECTIONS[0].id;
    document.querySelectorAll('.ds-section').forEach(p => p.classList.remove('is-visible'));
    document.getElementById('pane-' + known).classList.add('is-visible');
    document.querySelectorAll('.ds-link').forEach(a => a.classList.toggle('is-active', a.dataset.target === known));
    window.scrollTo(0, 0);
  }

  // Fill each swatch's hex label from the resolved token, so the page always
  // shows what landing/tokens.css actually says rather than a copy of it.
  const rootStyle = getComputedStyle(document.documentElement);
  const toHex = (v) => {
    v = v.trim();
    if (v.startsWith('#')) return v.toUpperCase();
    const m = v.match(/^rgba?\(([^)]+)\)$/);
    if (!m) return v;
    const [r, g, b] = m[1].split(',').map(x => parseInt(x, 10));
    return '#' + [r, g, b].map(x => x.toString(16).padStart(2, '0')).join('').toUpperCase();
  };
  // Gradient labels: read the stops back out of the computed value so the
  // label cannot drift from the token. The browser resolves nested var()s to
  // rgb() for us, so this only has to convert rgb -> hex.
  const probe = document.createElement('div');
  probe.style.position = 'absolute';
  probe.style.visibility = 'hidden';
  document.body.appendChild(probe);
  main.querySelectorAll('[data-gradient]').forEach(el => {
    probe.style.backgroundImage = 'var(' + el.dataset.gradient + ')';
    const resolved = getComputedStyle(probe).backgroundImage;
    const stops = [...resolved.matchAll(/rgba?\(([^)]+)\)/g)].map(m => {
      const [r, g, b] = m[1].split(',').map(x => parseInt(x, 10));
      return '#' + [r, g, b].map(x => x.toString(16).padStart(2, '0')).join('').toUpperCase();
    });
    el.textContent = stops.join(' \u2192 ');
  });
  probe.remove();

  main.querySelectorAll('[data-radius]').forEach(el => {
    el.textContent = rootStyle.getPropertyValue(el.dataset.radius).trim();
  });
  main.querySelectorAll('.ds-swatch[data-token]').forEach(el => {
    const hex = toHex(rootStyle.getPropertyValue(el.dataset.token));
    el.dataset.copy = hex;
    const label = el.querySelector('.ds-swatch__hex');
    if (label) label.textContent = hex;
  });

  // Same principle as the swatches above, applied to components: derive the
  // comparison from the stylesheets rather than restating them.
  renderDrift();

  window.addEventListener('hashchange', () => show(location.hash.slice(1)));
  show(location.hash.slice(1));

  // Click any swatch to copy its hex — the whole point of an internal reference.
  const toast = document.getElementById('ds-toast');
  let timer;
  main.addEventListener('click', e => {
    const el = e.target.closest('[data-copy]');
    if (!el) return;
    navigator.clipboard.writeText(el.dataset.copy).then(() => {
      toast.textContent = el.dataset.copy + ' copied';
      toast.classList.add('show');
      clearTimeout(timer);
      timer = setTimeout(() => toast.classList.remove('show'), 1400);
    });
  });
})();


/* ── live component drift ───────────────────────────────────────────────────
   Reads the two stylesheets the page has actually loaded and compares, for each
   component, which variants exist on each side. Nothing here is written down in
   advance — a hand-maintained inventory of another file is precisely the thing
   that drifted, so the page derives it instead. Add a variant to dashboard.css
   and this table changes on the next reload. */
function renderDrift() {
  const host = document.getElementById('ds-drift');
  if (!host) return;

  const collect = (matchHref) => {
    const found = [];
    for (const sheet of document.styleSheets) {
      const href = sheet.href || '';
      if (!matchHref(href)) continue;
      let rules;
      try { rules = sheet.cssRules; } catch (e) { continue; }
      for (const r of rules) if (r.selectorText) found.push(r.selectorText);
    }
    return found.join(' ');
  };

  const productCss = collect(h => h.includes('dashboard.css'));
  const pageCss    = collect(h => h.includes('ds.css'));

  const variants = (css, re) => {
    const out = new Set();
    let m;
    while ((m = re.exec(css)) !== null) out.add(m[1]);
    return out;
  };

  const BASES = ['btn', 'badge', 'card'];
  const html = BASES.map(base => {
    const shipped = variants(productCss, new RegExp('\\.' + base + '-([a-z0-9-]+)', 'g'));
    const docs    = variants(pageCss,    new RegExp('\\.ds-' + base + '(?:--|__)([a-z0-9-]+)', 'g'));
    const union = [...new Set([...shipped, ...docs])].sort();
    const both = union.filter(v => shipped.has(v) && docs.has(v)).length;

    const tag = base === 'badge' ? 'span' : (base === 'card' ? 'div' : 'button');
    const strip = [...shipped].sort().map(v =>
      `<${tag} class="${base} ${base}-${v}">${v}</${tag}>`).join('');

    const rows = union.map(v => {
      const d = docs.has(v)    ? '<span class="ds-ok">yes</span>' : '<span class="ds-no">&mdash;</span>';
      const p = shipped.has(v) ? '<span class="ds-ok">yes</span>' : '<span class="ds-no">&mdash;</span>';
      return `<tr><td><code>${v}</code></td><td>${d}</td><td>${p}</td></tr>`;
    }).join('');

    return `<p class="ds-label">${base} &mdash; rendered from dashboard.css</p>
      <div class="ds-demo"><div class="ds-wrapline">${strip}</div></div>
      <p class="ds-note">${both} of ${union.length} variants exist on both sides.</p>
      <div class="ds-scroll"><table class="ds-table">
        <thead><tr><th>variant</th><th>documented here</th><th>shipped</th></tr></thead>
        <tbody>${rows}</tbody></table></div>`;
  }).join('');

  host.innerHTML = html;
}
