// Renders the README images from the built site, in light and dark, on a transparent background.
// Run with the preview server up (node scripts/preview.mjs): node scripts/readme-art.mjs
import puppeteer from 'puppeteer-core';
import fs from 'node:fs/promises';
const out = '../docs/readme/';
await fs.mkdir(out, {recursive: true});
const shots = [
  // [file, page, selector, viewport width, dark-only]
  ['hero', '/', '.home .stage', 1280, false],
  ['menu-bar', '/', '.menubar-demo', 1280, false],
  ['activity', '/', '.activity-card', 1280, false],
  ['dock', '/', '.dock-row', 1280, false],
  ['usage-flow', '/', '.band', 1280, true],
  ['providers', '/', '.show .app-panel', 1280, false],
  ['privacy', '/privacy', '.dataflow', 1280, false],
];
const browser = await puppeteer.launch({executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-first-run', '--disable-background-networking']});
try {
  const page = await browser.newPage();
  await page.emulateMediaFeatures([{name: 'prefers-reduced-motion', value: 'reduce'}]);
  for (const [name, path, selector, width, darkOnly] of shots) {
    for (const theme of darkOnly ? ['dark'] : ['light', 'dark']) {
      await page.setViewport({width, height: 1000, deviceScaleFactor: 2});
      await page.evaluateOnNewDocument(t => { try { localStorage.setItem('aum-theme', t); } catch {} }, theme);
      await page.goto('http://127.0.0.1:4367' + path, {waitUntil: 'networkidle0'});
      await page.evaluate(() => document.fonts.ready);
      const el = await page.$(selector);
      if (!el) throw new Error('Missing ' + selector + ' on ' + path);
      await el.evaluate(e => e.scrollIntoView({block: 'center'}));
      // Finish every fill-on-view animation, then drop the page background so only the art remains.
      await page.evaluate(() => {
        document.querySelectorAll('[data-reveal],[data-ring],[data-bars],[data-dock],[data-reveal-draw],[data-term]').forEach(e => e.classList.add('in'));
        document.querySelectorAll('.term .out').forEach(e => e.classList.add('on'));
        document.querySelectorAll('[data-type]').forEach(e => { e.textContent = e.dataset.type; });
        document.querySelectorAll('[data-count]').forEach(e => { e.innerHTML = e.dataset.count + '<small>%</small>'; });
        document.documentElement.style.background = 'transparent';
        document.body.style.background = 'transparent';
      });
      await new Promise(r => setTimeout(r, 2200));
      const file = out + name + (darkOnly ? '' : '-' + theme) + '.png';
      await el.screenshot({path: file, omitBackground: true, captureBeyondViewport: true});
      console.log('wrote', file);
    }
  }
} finally {
  await browser.close();
}
