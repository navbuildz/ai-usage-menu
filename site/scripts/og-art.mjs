// Renders the 1200x630 social cards (public/art/og-<page>.png) from the built site: each page's own
// H1 beside its own hero art, on the dark brand background. Run with the preview server up, then rebuild.
import puppeteer from 'puppeteer-core';
import pages from '../src/data/content.json' with {type: 'json'};
const headline = {home: 'Your Claude Code and Codex limits, in your menu\u00a0bar and\u00a0Dock.'};
const browser = await puppeteer.launch({executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-first-run', '--disable-background-networking']});
try {
  const page = await browser.newPage();
  await page.emulateMediaFeatures([{name: 'prefers-reduced-motion', value: 'reduce'}]);
  await page.evaluateOnNewDocument(() => { try { localStorage.setItem('aum-theme', 'dark'); } catch {} });
  for (const id of Object.keys(pages)) {
    await page.setViewport({width: 1200, height: 630, deviceScaleFactor: 1});
    await page.goto('http://127.0.0.1:4367/' + (id === 'home' ? '' : id), {waitUntil: 'networkidle0'});
    await page.evaluate(() => document.fonts.ready);
    await page.evaluate((title) => {
      document.querySelectorAll('[data-reveal],[data-ring],[data-bars],[data-dock],[data-reveal-draw],[data-term]').forEach(e => e.classList.add('in'));
      document.querySelectorAll('[data-count]').forEach(e => { e.innerHTML = e.dataset.count + '<small>%</small>'; });
      const art = document.querySelector('.hero-art .stage') || document.querySelector('.hero-art');
      const logo = document.querySelector('.brand-live').cloneNode(true);
      const card = document.createElement('div');
      card.id = 'og';
      card.innerHTML = `<div class="og-copy"><div class="og-logo"></div><h1></h1><p class="og-url">aiusagemenu.com</p></div><div class="og-art"></div>`;
      card.querySelector('.og-logo').append(logo);
      card.querySelector('h1').textContent = title;
      card.querySelector('.og-art').append(art); // moved, not cloned: SVG gradients must stay in a rendered tree
      const style = document.createElement('style');
      style.textContent = `
        body > *:not(#og){display:none!important}
        html,body{margin:0;background:#0b0e20;overflow:hidden}
        #og{position:fixed;inset:0;width:1200px;height:630px;display:grid;grid-template-columns:560px 1fr;align-items:center;gap:20px;padding:0 0 0 64px;box-sizing:border-box;
          background:radial-gradient(70% 90% at 85% 40%,#3a1a5e66,transparent 70%),radial-gradient(60% 80% at 10% 100%,#1c2a6b88,transparent 70%),linear-gradient(125deg,#171842 0%,#0b0e20 54%,#2a1240 100%);overflow:hidden}
        .og-copy{display:grid;gap:26px;align-content:center;height:100%}
        .og-logo .brand-live{pointer-events:none}.og-logo .brand-mark{width:44px;height:44px}.og-logo .brand-word{font-size:1.5rem;color:#fff}
        #og h1{margin:0;color:#fff;font:700 54px/1.06 'Inter Variable',sans-serif;letter-spacing:-.03em;text-wrap:balance;max-width:540px}
        .og-url{margin:0;color:#b9a6ff;font:600 22px/1 'Inter Variable',sans-serif}
        .og-art{height:630px;display:grid;place-items:center;overflow:visible}
        .og-art .stage{transform:scale(.86);transform-origin:center;padding:40px 4%}
        .og-art .chip{animation:none}
        .og-art .dock-float{position:absolute;left:4%!important;right:auto!important;bottom:2%!important;width:104px!important}`;
      document.head.append(style);
      document.body.append(card);
    }, headline[id] || pages[id].h1);
    await new Promise(r => setTimeout(r, 1800));
    await page.screenshot({path: 'public/art/og-' + id + '.png', clip: {x: 0, y: 0, width: 1200, height: 630}});
    // Light JPEG for link previews (iMessage is fussy with heavy images); the PNG stays for the GitHub social preview.
    await page.screenshot({path: 'public/art/og-' + id + '.jpg', type: 'jpeg', quality: 88, clip: {x: 0, y: 0, width: 1200, height: 630}});
    console.log('wrote og-' + id + '.png/.jpg');
  }
} finally {
  await browser.close();
}
