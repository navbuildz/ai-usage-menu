import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {parse} from 'node-html-parser';
import {HtmlValidate} from 'html-validate';
import pages from '../src/data/content.json' with {type:'json'};
import {readRepository} from '../src/data/repository.mjs';
import {facts} from '../src/data/facts.mjs';
import {pageText} from './page-text.mjs';
import {dates} from '../src/data/shared.mjs';
// Ranges count everything in <main>, so they include page chrome (eyebrows, figure captions, the download card, the closing call to action) as well as the copy.
const ranges={privacy:[600,1300],home:[900,1300],compare:[900,1600],'claude-usage-limits':[1600,2300],'claude-code-usage':[1200,1750],'codex-usage':[1200,1750]};
const full=[],reports=[];
const root='../app/build/site-dist';
const titles=new Set(), keywordOwners=new Set(),h1s=new Set();
const validator=new HtmlValidate({extends:['html-validate:recommended'],rules:{'no-inline-style':'off','void-style':'off','no-trailing-whitespace':'off','attr-case':'off','attribute-boolean-style':'off','attribute-empty-style':'off','element-required-attributes':['error',{ignore:[]}],'long-title':'off','doctype-style':'off'}});
let invalid=0;
const sitemap=parse(await fs.readFile(root+'/sitemap.xml','utf8'));
const errorPage=parse(await fs.readFile(root+'/404.html','utf8'));
assert.ok(!errorPage.querySelector('link[rel="canonical"]'));
assert.equal(errorPage.querySelector('meta[name="robots"]').getAttribute('content'),'noindex');
for(const sel of ['link[rel="icon"][href="/favicon.ico"]','link[rel="icon"][href="/favicon.svg"]','link[rel="apple-touch-icon"]','meta[property="og:image"]','meta[name="twitter:card"]'])assert.ok(errorPage.querySelector(sel),'404 missing '+sel);
assert.equal(sitemap.querySelectorAll('url').length,8);
for(const [id,data] of Object.entries(pages)){
 const path=id==='home'?'':id;
 const raw=await fs.readFile(root+'/'+path+'/index.html','utf8');
 const html=parse(raw), meta=k=>html.querySelector('meta[name="'+k+'"]')?.getAttribute('content');
 const title=html.querySelector('title').text;
 const description=meta('description'),heading=html.querySelector('h1').text;
 const canonical=html.querySelector('link[rel="canonical"]').getAttribute('href');
 assert.equal(canonical,'https://aiusagemenu.com/'+path);
 assert.equal(html.querySelectorAll('h1').length,1);
 assert.ok(!titles.has(title)&&title.length<=60);titles.add(title);
 assert.ok(!h1s.has(heading));h1s.add(heading);
 assert.ok(!keywordOwners.has(data.primary));keywordOwners.add(data.primary);
 assert.ok(description.length>=150&&description.length<=158,id+' description length');
 const graph=JSON.parse(html.querySelector('script[type="application/ld+json"]').innerHTML)['@graph'];
 assert.ok(graph.some(t=>t['@type']==='BreadcrumbList'));
 const faqs=graph.find(t=>t['@type']==='FAQPage')?.mainEntity??[];
 assert.deepEqual(faqs.map(q=>[q.name,q.acceptedAnswer.text]),html.querySelectorAll('.faq details').map(d=>[d.querySelector('summary').text,d.querySelector('p').text]));
 const how=graph.find(t=>t['@type']==='HowTo');
 if(how)assert.deepEqual(how.step.map(x=>x.text),html.querySelectorAll('[data-howto] li').map(li=>li.text));
 if(id==='home'||id==='download'){const app=graph.find(t=>t['@type']==='SoftwareApplication');assert.equal(app.offers.price,0);assert.equal(app.offers.priceCurrency,'USD');assert.ok(app.license&&app.screenshot.length&&app.downloadUrl);assert.equal(app.applicationCategory,'DeveloperApplication');assert.equal(app.publisher.name,'TypeFire');assert.equal(app.operatingSystem,'macOS 13 or later')}
 for(const img of html.querySelectorAll('img'))assert.ok(img.getAttribute('width')&&img.getAttribute('height')&&img.getAttribute('alt'));
 for(const pic of html.querySelectorAll('picture')){assert.ok(pic.querySelector('source[type="image/avif"]')&&pic.querySelector('source[type="image/webp"]'));await fs.access(root+pic.querySelector('img').getAttribute('src'))}
 const og=html.querySelector('meta[property="og:image"]').getAttribute('content');await fs.access(root+new URL(og).pathname);
 // Every page carries the full icon set and social card (a missing favicon or card fails the build).
 for(const sel of ['link[rel="icon"][href="/favicon.ico"]','link[rel="icon"][href="/favicon.svg"]','link[rel="icon"][href="/favicon-192.png"]','link[rel="apple-touch-icon"]','link[rel="manifest"]'])assert.ok(html.querySelector(sel),id+' missing '+sel);
 for(const href of ['/favicon.ico','/favicon.svg','/favicon-192.png','/apple-touch-icon.png','/site.webmanifest'])await fs.access(root+href);
 for(const prop of ['og:title','og:description','og:url','og:type','og:site_name','og:image:width','og:image:height'])assert.ok(html.querySelector('meta[property="'+prop+'"]')?.getAttribute('content'),id+' missing '+prop);
 assert.equal(html.querySelector('meta[property="og:url"]').getAttribute('content'),canonical,id+' og:url must equal the canonical');
 assert.equal(html.querySelector('meta[name="twitter:card"]')?.getAttribute('content'),'summary_large_image',id+' twitter:card');
 for(const name of ['twitter:title','twitter:description','twitter:image'])assert.ok(html.querySelector('meta[name="'+name+'"]')?.getAttribute('content'),id+' missing '+name);
 { const png=await fs.readFile(root+new URL(og).pathname); assert.equal(png.readUInt32BE(16)+'x'+png.readUInt32BE(20),'1200x630',id+' og:image must be 1200x630'); }
 assert.doesNotMatch(html.querySelector('footer').text,/BaseThread/);
 assert.equal(html.querySelector('footer a[href="/privacy"]').text,'Privacy & Legal');
 if(id==='privacy')assert.ok(html.querySelector('main').text.includes('© 2026 BaseThread LLC'));
 assert.ok(html.querySelector('footer').text.includes('not affiliated with Anthropic or OpenAI'));
 assert.ok(html.querySelector('footer a[href="https://typefire.app"]'));
 if(id==='home'){
   const sectionTitles=html.querySelectorAll('main h2').map(h=>h.text);
   assert.ok(!sectionTitles.includes('Sources')&&!sectionTitles.includes('Explore AI Usage Menu'));
   assert.ok(!html.querySelector('main .date'));
 }
 const competitor=/\b(codexbar|ccusage|claudeusagebar|ai ?usage ?bar|ai usage monitor)\b/i;
 assert.ok(!competitor.test(title+' '+heading));
 const visible=pageText(raw);
 const bodyWords=(visible.match(/[\p{L}\p{N}]+(?:['’.-][\p{L}\p{N}]+)*/gu)||[]).length;
 const headings=html.querySelectorAll('main h2').map(h=>h.text.trim().toLowerCase());
 assert.equal(new Set(headings).size,headings.length,id+' duplicate H2 '+headings.join(' | '));
 assert.doesNotMatch(html.querySelector('body').text,/<!--|\b(?:OWNER|TODO)\b/);
 assert.doesNotMatch(JSON.stringify(graph),/PLACEHOLDER|\b(?:OWNER|TODO)\b/i);
 const date=dates[id];
 const revised=html.querySelector('.revision time');
 assert.equal(revised?.getAttribute('datetime'),date);
 assert.equal(Date.parse(revised.text+' UTC'),Date.parse(date));
 assert.equal(sitemap.querySelectorAll('url').find(el=>el.querySelector('loc').text===canonical)?.querySelector('lastmod').text,date);
 assert.ok(graph.some(node=>node.dateModified===date));
 for(const node of graph.filter(node=>node.dateModified))assert.equal(node.dateModified,date);
 if(['claude-code-usage','codex-usage','claude-usage-limits','compare'].includes(id)){
   const article=graph.find(t=>t['@type']==='Article');assert.equal(article.headline,heading);assert.equal(article.author['@type'],'Organization');
 }
 full.push('# '+title+'\n'+canonical+'\n\n'+visible);
 const range=ranges[id]||[600,1000];
 if(bodyWords<range[0]||bodyWords>range[1]){invalid++;console.error(id,'body words',bodyWords,'target',range)}

 for(const sentence of visible.split(/[.!?\n]/))if(competitor.test(sentence))assert.doesNotMatch(sentence,/\b(best|great|excellent|winner|better than us|deciding factor|if you need .+ use)\b/i);
 assert.doesNotMatch(raw,/—|\b(colour|favourite|behaviour|organise|licence|summarise)\b/i);
 reports.push({id,bodyWords,keywords:data.keywords,date,title,titleLength:title.length,primary:data.primary,description,descriptionLength:description.length,first120:description.slice(0,120),heading,canonical,og,types:graph.map(t=>t['@type'])});
 const validation=await validator.validateString(raw);
 if(!validation.valid){invalid++;console.error(id,JSON.stringify(validation.results.flatMap(r=>r.messages).map(m=>[m.ruleId,m.message]).slice(0,25)))}
}
for(const report of reports)console.log(JSON.stringify(report));
await fs.writeFile(root+'/llms-full.txt',full.join('\n\n'));
await fs.mkdir('audit',{recursive:true});
await fs.writeFile('audit/pages.json',JSON.stringify(reports,null,2)+'\n');
const owners=new Map();
for(const [id,data] of Object.entries(pages)){
 for(const phrase of data.keywords??[]){
   assert.ok(!owners.has(phrase),'Duplicate keyword owner: '+phrase);
   owners.set(phrase,id);
 }
 const phrase=data.primary.toLowerCase();
 const matches=reports.filter(r=>r.title.toLowerCase().includes(phrase));
 assert.ok(matches.length<=1,'Two titles target '+phrase);
}
const robots=await fs.readFile(root+'/robots.txt','utf8');
for(const agent of ['*','OAI-SearchBot','ChatGPT-User','PerplexityBot','ClaudeBot','Claude-SearchBot','Google-Extended','Applebot-Extended','Bingbot'])assert.ok(robots.includes('User-agent: '+agent+'\nAllow: /'));
const readme=await fs.readFile('../README.md','utf8');
const llms=await fs.readFile(root+'/llms.txt','utf8');
for(const value of Object.values(facts)){
 assert.ok(readme.includes(value)&&llms.includes(value)&&full[0].includes(value),value);
}
const cfg={owner:'fixture',repo:'usage'};
assert.equal(await readRepository(cfg,async()=>new Response(null,{status:404})),null);
const values=[{stargazers_count:11,forks_count:2,open_issues_count:1,license:{spdx_id:'MIT'}},[{}],[{tag_name:'v1',assets:[{download_count:4}]}]];
let i=0;const success=await readRepository(cfg,async()=>Response.json(values[i++],{headers:{link:'<https://api.github.com/test?page=3>; rel="last"'}}));
assert.equal(success.stars,11);assert.equal(success.contributors,3);assert.equal(success.releases[0].downloads,4);
assert.equal(Object.keys(pages).length,8);
// Release day: the site is written for a public repository and a signed, notarized download.
const cfg2=JSON.parse(await fs.readFile('src/data/repo.json','utf8'));
const releaseGaps=[cfg2.owner==='OWNER'&&'repo.json owner is the OWNER placeholder (clone command and GitHub links are hidden)',!cfg2.dmg&&'repo.json dmg is empty (download buttons use <repo>/releases/latest/download/AIUsageMenu.dmg)'].filter(Boolean);
if(releaseGaps.length)console.warn('RELEASE-DAY WARNING:\n - '+releaseGaps.join('\n - '));
if(invalid)process.exitCode=1;
