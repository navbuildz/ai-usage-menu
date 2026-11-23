const key=process.env.INDEXNOW_KEY;
if (!key || !/^[a-zA-Z0-9-]{8,128}$/.test(key)) throw Error('Supply the deployed INDEXNOW_KEY before running.');
const host='aiusagemenu.com';
const {default:pages}=await import('../src/data/content.json',{with:{type:'json'}});
const response=await fetch('https://api.indexnow.org/indexnow',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({host,key,keyLocation:'https://'+host+'/'+key+'.txt',urlList:Object.keys(pages).map(k=>'https://'+host+'/'+(k==='home'?'':k))})});
if (!response.ok) throw Error('IndexNow returned '+response.status);
