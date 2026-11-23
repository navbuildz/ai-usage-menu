import {dates,base,pathFor} from '../data/shared.mjs';
export function GET(){return new Response('<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+Object.entries(dates).map(([k,date])=>'<url><loc>'+base+pathFor(k)+'</loc><lastmod>'+date+'</lastmod></url>').join('')+'</urlset>')}
