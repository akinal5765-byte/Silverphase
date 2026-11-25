(() => {
  const grid = document.querySelector('#comparison');
  if (!grid) return;
  const full = document.querySelector('#swap-full');
  const detail = document.querySelector('#swap-detail');
  const name = document.querySelector('#swap-name');
  const note = document.querySelector('#swap-note');
  const buttons = [...document.querySelectorAll('button[data-print]')];
  for (const button of buttons) {
    button.addEventListener('click', () => {
      const key = button.dataset.print;
      const data = document.getElementById('paper-' + key).content;
      full.src = grid.dataset.src + key + '.webp';
      detail.src = grid.dataset.src + key + '-detail.webp';
      name.textContent = data.querySelector('span').textContent;
      note.textContent = data.querySelector('p').textContent;
      for (const candidate of buttons) candidate.setAttribute('aria-pressed', String(candidate === button));
    });
  }
  document.documentElement.classList.add('interactive');
})();

(() => {
  const proof = document.querySelector('[data-proof]');
  if (proof) {
    const input = proof.querySelector('input');
    const draw = () => proof.style.setProperty('--split', input.value + '%');
    input.addEventListener('input', draw);
    draw();
    proof.classList.add('proof-ready');
  }
  if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const observed = document.querySelectorAll('.paper .section-head, .stock-grid, .night-grid, .workflow, .strip-grid');
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) {
        entry.target.classList.add('arrived');
        observer.unobserve(entry.target);
      }
    }, {threshold: 0.13});
    observed.forEach(node => observer.observe(node));
  }
})();
