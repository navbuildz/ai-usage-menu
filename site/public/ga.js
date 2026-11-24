// Google Analytics 4 for aiusagemenu.com (the app itself has no analytics or telemetry).
// Loaded as a file so the Content Security Policy needs no inline script.
window.dataLayer = window.dataLayer || [];
function gtag(){ dataLayer.push(arguments); }
window.gtag = gtag;
gtag('js', new Date());
gtag('config', 'G-BQD441VNTH');
// Count download and feedback clicks. Reporting must never break the page.
document.addEventListener('click', e => {
  const a = e.target.closest && e.target.closest('a[href]');
  if (!a) return;
  const href = a.getAttribute('href') || '';
  const where = a.dataset.cta || (a.closest('header') ? 'header' : a.closest('footer') ? 'footer' : (a.closest('section,[id]')?.id || 'page'));
  // transport_type beacon: the hit is queued and never delays or cancels the download navigation.
  const params = {cta: where, page: location.pathname, link_text: (a.textContent || '').trim().slice(0, 60), transport_type: 'beacon'};
  try {
    if (href.includes('AIUsageMenu.dmg')) gtag('event', 'mac_download', params);
    else if (href === '/download') gtag('event', 'download_page_click', params);
    else if (href.includes('/issues/new')) gtag('event', 'feedback_click', {...params, kind: href.includes('feature') ? 'feature' : 'bug'});
    else if (href.includes('github.com/navbuildz/ai-usage-menu')) gtag('event', 'github_click', params);
  } catch {}
}, {capture: true});
