import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {brotliCompressSync} from 'node:zlib';
const root=path.resolve('../app/build/site-dist');
const mime={'.html':'text/html','.js':'application/javascript','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.avif':'image/avif','.webp':'image/webp','.ico':'image/x-icon','.txt':'text/plain','.xml':'application/xml','.woff2':'font/woff2','.webmanifest':'application/manifest+json'};
http.createServer(async(req,res)=>{
 const url=new URL(req.url,'http://localhost');let name=decodeURIComponent(url.pathname);
 if(name.length>1&&name.endsWith('/')){res.writeHead(308,{Location:name.slice(0,-1)});return res.end()}
 if(name==='/')name='/index.html';else if(!path.extname(name))name+='/index.html';
 let file=path.resolve(root,'.'+name);if(!file.startsWith(root+'/')){res.writeHead(403);return res.end()}
 let status=200,data;
 try{data=await fs.readFile(file)}catch{file=root+'/404.html';data=await fs.readFile(file);status=404}
 const ext=path.extname(file),headers={'Content-Type':mime[ext]||'application/octet-stream','Cache-Control':url.pathname.startsWith('/_astro/')?'public,max-age=31536000,immutable':'no-cache'};
 if(/html|css|js|svg|xml|txt/.test(ext)&&req.headers['accept-encoding']?.includes('br')){headers['Content-Encoding']='br';data=brotliCompressSync(data)}
 res.writeHead(status,headers);res.end(data);
}).listen(4367,'127.0.0.1',()=>console.log('http://127.0.0.1:4367'));
