import puppeteer from 'puppeteer-core';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import pages from '../src/data/content.json' with {type:'json'};
const browser=await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--disable-background-networking','--no-first-run']});
try {
 const page=await browser.newPage(), origin='http://127.0.0.1:4367';
 const external=new Set(),failed=new Set();
 page.on('request',r=>{if(r.url().startsWith('http')&&!r.url().startsWith(origin+'/'))external.add(r.url())});
 page.on('response',r=>{if(r.status()>=400&&r.url()!==origin+'/missing-page')failed.add(r.url())});
 await page.emulateMediaFeatures([{name:'prefers-reduced-motion',value:'reduce'}]);
 for(const id of Object.keys(pages)){
  for(const width of [320,360,390,1440]){
   await page.setViewport({width,height:width===1440?1000:844,deviceScaleFactor:1});
   await page.goto(origin+'/'+(id==='home'?'':id),{waitUntil:'networkidle0'});
   if(width<400){
     await page.click('.nav-disclosure summary');
     assert.equal(await page.$$eval('.mobile-links a',links=>links.length),5);
     if(['claude-code-usage','codex-usage','claude-usage-limits','open-source','compare'].includes(id))assert.equal(await page.$eval('.mobile-links [aria-current=page]',el=>el.pathname),'/'+id);
     await page.keyboard.press('Escape');
   }
   for(const theme of ['dark','light']){
    await page.click('[data-mode='+theme+']');
    assert.equal(await page.$eval('html',el=>el.dataset.theme),theme);
    await page.evaluate(()=>window.scrollTo({top:480,behavior:'instant'}));
    assert.ok(await page.$eval('.nav-download', el=>{const r=el.getBoundingClientRect();return r.top>=0 && r.bottom<130 && r.right<=innerWidth}));
    await page.evaluate(()=>window.scrollTo({top:0,behavior:'instant'}));
    await page.evaluate(()=>document.fonts.ready);
    if(width===390 && theme==='light'){
      const terminal=await page.$('[data-terminal]');
      if(terminal){
        await terminal.$eval('[role=tab]:last-child',el=>el.click());
        assert.equal(await terminal.$eval('[role=tab]:last-child',el=>el.getAttribute('aria-selected')),'true');
        await terminal.$eval('[role=tab]:first-child',el=>el.click());
      }
    }
    const hasOverflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
    assert.ok(!hasOverflow,id+' '+width+' '+theme+' horizontal overflow');
    if([390,1440].includes(width)&&['home','compare','claude-usage-limits'].includes(id))await page.screenshot({path:'audit/'+id+'-'+width+'-'+theme+'.png'});
    if([390,1440].includes(width))await page.screenshot({path:'../handoff/site-screens/'+id+'-'+width+'-'+theme+'.png'});
   }
  }
  console.log(id+' passed at 320, 360, 390 and 1440 px in both themes');
 }
 assert.equal((await page.goto(origin+'/missing-page')).status(),404);
 assert.equal((await page.goto(origin+'/privacy/')).url(),origin+'/privacy');
 const jsOff=await browser.newPage();await jsOff.setJavaScriptEnabled(false);
 await jsOff.goto(origin+'/');assert.ok((await jsOff.$eval('h1',e=>e.textContent)).includes('Stay in control'));
 assert.equal(external.size,0,[...external].join('\n'));assert.equal(failed.size,0,[...failed].join('\n'));
 console.log('Zero third-party URL requests or missing assets. 404, trailing slash and JS-off checks passed.');
}finally{await browser.close()}
