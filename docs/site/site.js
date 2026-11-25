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
