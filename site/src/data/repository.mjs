export async function readRepository(config, request = fetch) {
  if (config.owner === 'OWNER') return null;
  const url = 'https://api.github.com/repos/' + config.owner + '/' + config.repo;
  const headers = {Accept:'application/vnd.github+json'};
  if (process.env.GITHUB_TOKEN) headers.Authorization = 'Bearer ' + process.env.GITHUB_TOKEN;
  try {
    const responses = await Promise.all(['','/contributors?per_page=1&anon=1','/releases?per_page=5'].map(suffix => request(url+suffix,{headers,signal:AbortSignal.timeout(6000)})));
    if (responses.some(r => !r.ok)) return null;
    const [repo, first, releases] = await Promise.all(responses.map(r => r.json()));
    if (repo.private || !Array.isArray(first) || !Array.isArray(releases)) return null;
    const lastPage = responses[1].headers.get('link')?.match(/[?&]page=(\d+)[^>]*>; rel="last"/);
    return {stars:repo.stargazers_count,forks:repo.forks_count,issues:repo.open_issues_count,contributors:lastPage ? Number(lastPage[1]) : first.length,license:repo.license?.spdx_id,updated:repo.pushed_at,asOf:new Date().toISOString().slice(0,10),releases:releases.map(r=>({tag:r.tag_name,url:r.html_url,date:r.published_at?.slice(0,10),note:r.body?.split(/\r?\n/).find(Boolean)?.replace(/^#+\s*/,''),lines:(r.body??'').split(/\r?\n/).filter(line=>line.trim()&&!line.startsWith('#')).slice(0,5).map(line=>line.replace(/^[-*]\s+/,'')),downloads:r.assets.reduce((n,a)=>n+a.download_count,0)}))};
  } catch { return null; }
}
