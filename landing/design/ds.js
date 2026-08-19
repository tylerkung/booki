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
