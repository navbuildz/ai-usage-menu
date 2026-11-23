// Use the rendered main element so build-time code and terminal panels are included.
import {parse} from 'node-html-parser';
export function pageText(raw) {
  const main = parse(raw,{blockTextElements:{style:true,script:true}}).querySelector('main');
  for (const el of main.querySelectorAll('nav,script,style,svg,[aria-hidden="true"]')) el.remove();
  for (const el of main.querySelectorAll('p,h1,h2,h3,h4,td,th,dt,dd,li,figcaption,summary,button')) el.insertAdjacentHTML('afterend',' ');
  return main.structuredText.split('\n').map(line=>line.replace(/\s+/g,' ').trim()).filter(Boolean).join('\n');
}
