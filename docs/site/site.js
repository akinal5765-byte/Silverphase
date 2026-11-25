/* Preserve section links as articles move between the gallery and notes. */
(() => {
  const panels = [...document.querySelectorAll('.device')];
  const controls = document.querySelector('[data-device-controls]');
  const language = document.querySelector('[data-language]');
  const defaultDevice = matchMedia('(max-width: 650px)').matches ? 'interface-iphone' : 'interface-mac';
  function showDevice(id) {
    for (const panel of panels) panel.hidden = panel.id !== id;
    for (const link of controls.querySelectorAll('a')) {
      if (link.hash === '#' + id) link.setAttribute('aria-current', 'true');
      else link.removeAttribute('aria-current');
    }
  }
  function readSection() {
    const id = location.hash.slice(1);
    const target = document.getElementById(id);
    if (target && target.hasAttribute('data-forward')) {
      location.replace(target.href);
      return;
    }
    if (language) language.hash = target ? location.hash : '';
    if (panels.length && (!id || target?.classList.contains('device'))) {
      showDevice(target?.id || defaultDevice);
    }
    if (target?.matches('.case input[type="radio"]')) target.checked = true;
    if (target?.tagName === 'DETAILS') target.open = true;
    if (id && target && (target.matches('.device, .tech-note') || target.closest('.collection'))) {
      const section = target.closest('.case') || target;
      requestAnimationFrame(() => section.scrollIntoView({block: 'start'}));
    }
  }
  if (controls) {
    controls.hidden = false;
    showDevice(defaultDevice);
    controls.addEventListener('click', event => {
      const link = event.target.closest('a');
      if (!link || event.ctrlKey || event.shiftKey || event.altKey || event.metaKey) return;
      event.preventDefault();
      showDevice(link.hash.slice(1));
      history.replaceState(null, '', link.hash);
      language.hash = link.hash;
    });
  }
  window.addEventListener('hashchange', readSection);
  readSection();
})();
