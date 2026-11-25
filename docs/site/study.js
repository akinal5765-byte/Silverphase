(() => {
  const proof = document.querySelector('[data-lab-proof]');
  const controls = document.querySelector('[data-lab-controls]');
  if (!proof || !controls) return;
  const imLeft = proof.querySelector('.proof-front');
  const imRight = proof.querySelector('.lab-back');
  const left = controls.querySelector('[data-side="left"]');
  const right = controls.querySelector('[data-side="right"]');
  const sliders = proof.querySelector('input');
  const viewButtons = [...controls.querySelectorAll('[data-view]')];
  let view = 'full';
  function update() {
    const suffix = view === 'detail' ? '-detail.webp' : '.webp';
    proof.classList.toggle('detail-view', view === 'detail');
    for (const [select, image, side] of [[left,imLeft,'left'],[right,imRight,'right']]) {
      const label = select.selectedOptions[0].textContent;
      image.src = 'plates/' + select.value + suffix;
      image.alt = label;
      image.height = view === 'detail' ? 408 : 504;
      document.querySelector('[data-' + side + '-label]').textContent = label;
    }
  }
  const draw = () => proof.style.setProperty('--split', sliders.value + '%');
  sliders.addEventListener('input', draw);
  for (const sel of [left,right]) sel.addEventListener('change',update);
  for (const b of controls.querySelectorAll('[data-preset]')) b.addEventListener('click',() => {
    [left.value, right.value] = b.dataset.preset.split(',');
    sliders.value = '50';
    draw();
    update();
  });
  for (const b of viewButtons) b.addEventListener('click',() => {
    view = b.dataset.view;
    for (const v of viewButtons) v.setAttribute('aria-pressed',String(v === b));
    update();
  });
  draw();
  update();
  proof.classList.add('proof-ready');
  controls.hidden = false;
})();
