// Runs in <head>: apply the saved theme before first paint, mark JS as available, wire the Auto/Light/Dark switch.
document.documentElement.classList.add('js');
const saved = () => { try { return localStorage.getItem('aum-theme') || 'system'; } catch { return 'system'; } };
function apply(choice) {
  const dark = choice === 'dark' || (choice === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  document.querySelectorAll('source[data-capture-theme]').forEach(source => {
    source.media = source.dataset.captureTheme === (dark ? 'dark' : 'light') ? source.dataset.viewport : 'not all';
  });
}
apply(saved());
document.addEventListener('DOMContentLoaded', () => {
  const buttons = document.querySelectorAll('[data-mode]');
  let choice = saved();
  const reflect = () => { apply(choice); buttons.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.mode === choice))); };
  reflect();
  buttons.forEach(b => b.addEventListener('click', () => { choice = b.dataset.mode; try { localStorage.setItem('aum-theme', choice); } catch {} reflect(); }));
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', reflect);
});
