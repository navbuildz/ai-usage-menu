// Renders the 1200x630 social cards (public/art/og-<page>.jpg for link previews, .png for the GitHub
// social preview). Layout A, Nav's pick (2026-11-23): the menu bar strip large across the top with our
// item in front (the other menu bar items at 25%), the Dock tile large bottom left, and the app window
// rising on the right, zoomed so the session ring, reset time and pace line read at phone size.
// Every card uses the same art with its page's headline. Run with the preview server up, then rebuild.
import puppeteer from 'puppeteer-core';
import pages from '../src/data/content.json' with {type: 'json'};
// Short card headlines: the page title already shows under the card in link previews.
const headline = {
  home: 'Your AI limits, at a glance.',
  'claude-code-usage': 'Claude Code usage, live.',
  'codex-usage': 'Codex limits, at a glance.',
  'claude-usage-limits': 'Claude usage limits, explained.',
  'open-source': 'Open source. Read every line.',
  privacy: 'Nothing leaves your Mac.',
  compare: 'Usage trackers, compared.',
  download: 'Get AI Usage Menu for Mac.',
};
const BG = 'radial-gradient(70% 90% at 85% 40%,#3a1a5e66,transparent 70%),radial-gradient(60% 80% at 10% 100%,#1c2a6b88,transparent 70%),linear-gradient(125deg,#171842 0%,#0b0e20 54%,#2a1240 100%)';
const browser = await puppeteer.launch({executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-first-run', '--disable-background-networking']});
try {
  const page = await browser.newPage();
  await page.emulateMediaFeatures([{name: 'prefers-reduced-motion', value: 'reduce'}]);
  await page.evaluateOnNewDocument(() => { try { localStorage.setItem('aum-theme', 'dark'); } catch {} });
  for (const id of Object.keys(pages)) {
    await page.setViewport({width: 1200, height: 630, deviceScaleFactor: 1});
    await page.goto('http://127.0.0.1:4367/', {waitUntil: 'networkidle0'});
    await page.evaluate(() => document.fonts.ready);
    await page.evaluate((title, BG) => {
      document.querySelectorAll('[data-reveal],[data-ring],[data-bars],[data-dock],[data-reveal-draw],[data-term]').forEach(e => e.classList.add('in'));
      document.querySelectorAll('[data-count]').forEach(e => { e.innerHTML = e.dataset.count + '<small>%</small>'; });
      // One consistent reading everywhere on the card: 30% session (one bar lit, Dock 30, window 30%).
      const bar = document.querySelector('.menubar-demo .mb-bar');
      const gauge = bar.querySelector('[data-mb-gauge]');
      gauge.className = 'mb-gauge tone-ok';
      gauge.querySelector('[data-mb-value]').textContent = '30%';
      const dock = document.querySelector('.home .dock-float .dock-tile');
      const win = document.querySelector('.home .stage .app-panel');
      const logo = document.querySelector('.brand-live').cloneNode(true);
      const card = document.createElement('div');
      card.id = 'og';
      card.innerHTML = '<div class="v-copy"><div class="og-logo"></div><h1></h1><p class="og-url">aiusagemenu.com</p></div><div class="v-win"></div><div class="v-dock"></div><div class="v-bar"></div>';
      card.querySelector('.og-logo').append(logo);
      card.querySelector('h1').textContent = title;
      card.querySelector('.v-bar').append(bar);
      card.querySelector('.v-dock').append(dock);
      card.querySelector('.v-win').append(win); // moved, not cloned: SVG gradients must stay in a rendered tree
      const style = document.createElement('style');
      style.textContent = `body > *:not(#og){display:none!important}
        html,body{margin:0;background:#0b0e20;overflow:hidden}
        #og{position:fixed;inset:0;width:1200px;height:630px;overflow:hidden;background:${BG}}
        .v-copy{position:absolute;left:64px;top:130px;width:420px;display:grid;gap:22px}
        .og-logo .brand-live{pointer-events:none}.og-logo .brand-mark{width:40px;height:40px}.og-logo .brand-word{font-size:1.35rem;color:#fff}
        #og h1{margin:0;color:#fff;font:700 52px/1.06 'Inter Variable',sans-serif;letter-spacing:-.03em;text-wrap:balance}
        .og-url{margin:0;color:#b9a6ff;font:600 21px/1 'Inter Variable',sans-serif}
        .v-bar{position:absolute;top:0;left:0;right:0;transform-origin:top right;transform:scale(2.6);width:calc(1200px/2.6);margin-left:calc(1200px - 1200px/2.6);z-index:4}
        .v-bar .mb-bar{backdrop-filter:none;background:#0e1026e6;color:#fff}
        .v-bar .mb-bar > :not(.mb-gauge){opacity:.25}
        .v-bar .mb-gauge .g-bar{fill:#ffffff47}
        .v-bar .mb-gauge.tone-ok .b1{fill:#fff}
        .v-win{position:absolute;right:50px;top:160px;transform-origin:top right;transform:scale(1.6)}
        .v-win .app-panel{width:400px;box-shadow:0 30px 80px #0009}
        .v-dock{position:absolute;left:64px;top:400px;width:180px;z-index:3}
        .v-dock .dock-tile{filter:drop-shadow(0 20px 40px #000a)}`;
      document.head.append(style);
      document.body.append(card);
      // Long page titles: shrink the headline until it fits beside the window in three lines,
      // then put the Dock tile under the copy and shrink it if it would run off the card.
      const h1 = card.querySelector('h1');
      for (let size = 52; size > 34; size -= 2) {
        h1.style.fontSize = size + 'px';
        const lines = Math.round(h1.getBoundingClientRect().height / (size * 1.06));
        if (lines <= 3) break;
      }
      const copyBottom = card.querySelector('.v-copy').getBoundingClientRect().bottom;
      const dockEl = card.querySelector('.v-dock');
      const top = Math.max(400, Math.ceil(copyBottom) + 28);
      dockEl.style.top = top + 'px';
      dockEl.style.width = Math.min(180, 606 - top) + 'px';
    }, headline[id] || pages[id].h1, BG);
    await new Promise(r => setTimeout(r, 1800));
    await page.screenshot({path: 'public/art/og-' + id + '.png', clip: {x: 0, y: 0, width: 1200, height: 630}});
    // Light JPEG for link previews (iMessage is fussy with heavy images); the PNG is for the GitHub social preview.
    await page.screenshot({path: 'public/art/og-' + id + '.jpg', type: 'jpeg', quality: 88, clip: {x: 0, y: 0, width: 1200, height: 630}});
    console.log('wrote og-' + id + '.png/.jpg');
  }
} finally {
  await browser.close();
}
