const saved = () => { try { return localStorage.getItem('aum-theme') || 'system'; } catch { return 'system'; } };
function apply(choice) {
  const dark = choice === 'dark' || (choice === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  const mode = dark ? 'dark' : 'light';
  document.documentElement.dataset.theme = mode;
  document.querySelectorAll('source[data-capture-theme]').forEach(source => {
    source.media = source.dataset.captureTheme === mode ? source.dataset.viewport : 'not all';
  });
}
apply(saved());
document.addEventListener('DOMContentLoaded',()=>{
  const buttons = document.querySelectorAll('[data-mode]');
  let choice = saved();
  function reflect() {
    apply(choice);
    buttons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.mode === choice)));
  }
  reflect();
  buttons.forEach(button => button.addEventListener('click', () => {
    choice = button.dataset.mode;
    try { localStorage.setItem('aum-theme', choice); } catch {}
    reflect();
  }));
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', reflect);
  document.querySelectorAll('.copy').forEach(button=>button.addEventListener('click',async()=>{
    try {await navigator.clipboard.writeText(button.previousElementSibling.textContent);button.textContent='Copied'} catch {button.textContent='Select the command above'}
  }));
});

document.addEventListener('DOMContentLoaded', () => {
  const sentinel = document.querySelector('#mast-sentinel');
  if (sentinel) new IntersectionObserver(([entry]) => {
    document.querySelector('.mast').classList.toggle('scrolled', !entry.isIntersecting);
  }).observe(sentinel);
  const menu = document.querySelector('.nav-disclosure');
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && menu?.open) { menu.open = false; menu.querySelector('summary').focus(); }
  });
});
