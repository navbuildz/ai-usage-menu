// AI Usage Menu site: small, dependency-free interaction layer. Everything degrades to a finished, static page.
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const ready = fn => document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', fn) : fn();

  ready(() => {
    // Header: frosted once the page scrolls.
    const mast = document.querySelector('.mast'), sentinel = document.querySelector('#mast-sentinel');
    if (mast && sentinel) new IntersectionObserver(([e]) => mast.classList.toggle('scrolled', !e.isIntersecting)).observe(sentinel);
    const menu = document.querySelector('.nav-disclosure');
    document.addEventListener('keydown', e => { if (e.key === 'Escape' && menu?.open) { menu.open = false; menu.querySelector('summary').focus(); } });
    document.addEventListener('click', e => { if (menu?.open && !menu.contains(e.target)) menu.open = false; });

    // Count a number up once.
    const countUp = (el, to) => {
      if (reduce) { el.textContent = to + '%'; return; }
      const start = performance.now(), dur = 1300;
      const tick = t => { const k = Math.min(1, (t - start) / dur), e = 1 - Math.pow(1 - k, 3); el.textContent = Math.round(to * e) + '%'; if (k < 1) requestAnimationFrame(tick); };
      el.textContent = '0%'; requestAnimationFrame(tick);
    };

    // Reveal and "fill on view" for rings, bars, dock tiles, timelines and the terminal.
    const io = new IntersectionObserver(entries => entries.forEach(({isIntersecting, target}) => {
      if (!isIntersecting) return;
      io.unobserve(target);
      target.classList.add('in');
      if (target.matches('[data-ring]')) { const n = target.querySelector('[data-count]'); if (n) countUp(n, +n.dataset.count); }
      if (target.matches('[data-term]')) typeTerminal(target);
    }), {rootMargin: '0px 0px -8% 0px', threshold: .15});
    $$('[data-reveal],[data-ring],[data-bars],[data-dock],[data-reveal-draw],[data-term]').forEach(el => io.observe(el));
    $$('[data-reveal-group]').forEach(g => [...g.children].forEach((c, i) => { c.setAttribute('data-reveal', ''); c.style.setProperty('--d', i); io.observe(c); }));

    // Terminal: type /usage, then print each line.
    function typeTerminal(root) {
      const cmd = root.querySelector('[data-type]'), outs = $$('.out', root);
      if (reduce || !cmd) { outs.forEach(o => o.classList.add('on')); return; }
      const text = cmd.dataset.type; cmd.textContent = ''; let i = 0;
      const step = () => { cmd.textContent = text.slice(0, ++i); if (i < text.length) setTimeout(step, 90); else outs.forEach((o, k) => setTimeout(() => o.classList.add('on'), 350 + k * 260)); };
      setTimeout(step, 300);
    }

    // Provider tabs in the app panel.
    $$('[data-panel] [role=tablist]').forEach(list => {
      const tabs = $$('[role=tab]', list);
      const select = tab => {
        tabs.forEach(t => { const on = t === tab; t.setAttribute('aria-selected', on); t.tabIndex = on ? 0 : -1; document.getElementById(t.getAttribute('aria-controls')).hidden = !on; });
        const view = document.getElementById(tab.getAttribute('aria-controls'));
        $$('[data-ring]', view).forEach(r => { r.classList.remove('in'); void r.offsetWidth; r.classList.add('in'); const n = r.querySelector('[data-count]'); if (n) countUp(n, +n.dataset.count); });
      };
      tabs.forEach((t, i) => {
        t.addEventListener('click', () => select(t));
        t.addEventListener('keydown', e => { if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') { e.preventDefault(); const n = tabs[(i + (e.key === 'ArrowRight' ? 1 : tabs.length - 1)) % tabs.length]; n.focus(); select(n); } });
      });
    });

    // Menu bar: step through healthy, nearing the limit and near capacity.
    $$('[data-menubar]').forEach(root => {
      const states = [[30, 'Healthy', 'tone-ok'], [72, 'Nearing the limit', 'tone-warn'], [94, 'Near capacity', 'tone-hot']];
      const gauge = root.querySelector('[data-mb-gauge]'), value = root.querySelector('[data-mb-value]'), pop = root.querySelector('[data-mb-pop]'), label = root.querySelector('[data-mb-label]');
      const ring = pop.querySelector('[data-ring]'), num = ring.querySelector('[data-count]'), legend = $$('[data-mb-state]', root);
      let i = 1, timer = null;
      const show = k => {
        i = k; const [v, name, tone] = states[k];
        [gauge, pop, ring].forEach(el => { el.classList.remove('tone-ok', 'tone-warn', 'tone-hot'); el.classList.add(tone); });
        value.textContent = v + '%'; label.textContent = name; ring.style.setProperty('--v', v); num.textContent = v + '%';
        legend.forEach((l, n) => l.classList.toggle('on', n === k));
      };
      legend.forEach((l, n) => { l.addEventListener('mouseenter', () => { clearInterval(timer); show(n); }); l.addEventListener('mouseleave', run); });
      function run() { if (reduce) return; clearInterval(timer); timer = setInterval(() => show((i + 1) % 3), 2600); }
      new IntersectionObserver(([e]) => { if (e.isIntersecting) run(); else clearInterval(timer); }).observe(root);
    });

    // Reading pages: highlight the current section in the contents.
    const toc = $$('.toc nav a');
    if (toc.length) {
      const targets = toc.map(a => document.getElementById(a.hash.slice(1))).filter(Boolean);
      const spy = new IntersectionObserver(entries => entries.forEach(e => { if (e.isIntersecting) toc.forEach(a => a.classList.toggle('on', a.hash === '#' + e.target.id)); }), {rootMargin: '-20% 0px -70% 0px'});
      targets.forEach(t => spy.observe(t));
    }

    // Compare cards on phones: five rows first, the rest on request.
    $$('.compare .row-more').forEach(b => b.addEventListener('click', () => { const tr = b.closest('tr'); const open = tr.classList.toggle('open'); b.setAttribute('aria-expanded', open); b.querySelector('span').textContent = open ? 'Show less' : 'Show all'; }));

    // Install tabs and copy buttons.
    $$('[data-terminal]').forEach(t => {
      const tabs = $$('[role=tab]', t);
      tabs.forEach(tab => tab.addEventListener('click', () => tabs.forEach(o => { const on = o === tab; o.setAttribute('aria-selected', on); document.getElementById(o.getAttribute('aria-controls')).hidden = !on; })));
    });
    $$('[data-copy-command]').forEach(b => b.addEventListener('click', async () => {
      const label = b.querySelector('span');
      try { await navigator.clipboard.writeText(b.closest('.command-row').querySelector('pre').textContent); label.textContent = 'Copied'; } catch { label.textContent = 'Select it'; }
      setTimeout(() => { label.textContent = 'Copy'; }, 1800);
    }));
  });
})();
