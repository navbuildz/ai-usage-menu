import fs from 'node:fs/promises';
import {launch} from 'chrome-launcher';
import lighthouse from 'lighthouse';
import desktop from 'lighthouse/core/config/desktop-config.js';
import pages from '../src/data/content.json' with {type:'json'};
const app='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const dest='../handoff/lighthouse';
for(const id of (process.argv.slice(2).length?process.argv.slice(2):Object.keys(pages))){
 for(const mode of ['mobile','desktop']){
 const chrome=await launch({chromePath:app,chromeFlags:['--headless=new','--disable-extensions','--disable-background-networking','--no-first-run']});
 try{
 const result=await lighthouse('http://127.0.0.1:4367/'+(id==='home'?'':id),{port:chrome.port,logLevel:'error',onlyCategories:['performance','accessibility','best-practices','seo'],output:'json',maxWaitForLoad:20000},mode==='desktop'?desktop:undefined);
 const lhr=result.lhr;
 const summary={id,mode,time:lhr.fetchTime,url:lhr.finalDisplayedUrl,version:lhr.lighthouseVersion,scores:Object.fromEntries(Object.entries(lhr.categories).map(([k,v])=>[k,Math.round(v.score*100)])),lcp:lhr.audits['largest-contentful-paint'].numericValue,cls:lhr.audits['cumulative-layout-shift'].numericValue,transfer:lhr.audits['total-byte-weight'].numericValue,issues:Object.values(lhr.audits).filter(a=>typeof a.score==='number'&&a.score<0.9).map(a=>({id:a.id,score:a.score,detail:a.displayValue}))};
 await fs.writeFile(dest+'/'+id+'-'+mode+'.json',JSON.stringify(lhr,(k,v)=>k==='data'&&typeof v==='string'&&v.startsWith('data:image/')?undefined:v));
 console.log(JSON.stringify(summary));
 }finally{await chrome.kill()}
 }
}
