/* The rail is also the drag target when the round grip is above the viewport. */
(() => {
  function initComparison(frame) {
    const handle = frame.querySelector('.divider');
    function setSplit(percent) {
      const value = Math.max(0, Math.min(100, Math.round(percent)));
      frame.style.setProperty('--split', value + '%');
      handle.setAttribute('aria-valuenow', String(value));
      handle.setAttribute('aria-valuetext', handle.dataset.original + ' ' + value + '%');
    }
    let drag = null;
    function move(clientX) {
      const rect = frame.getBoundingClientRect();
      if (rect.width) setSplit((clientX - rect.left) / rect.width * 100);
    }
    handle.addEventListener('pointerdown', event => {
      if (!event.isPrimary || event.button !== 0) return;
      // Pointer comparison leaves keyboard focus and the reading position intact.
      event.preventDefault();
      drag = {id: event.pointerId, x: event.clientX, y: event.clientY, active: event.pointerType === 'mouse'};
      handle.setPointerCapture(event.pointerId);
    });
    handle.addEventListener('pointermove', event => {
      if (!drag || drag.id !== event.pointerId) return;
      if (!drag.active) {
        const dx = Math.abs(event.clientX - drag.x);
        const dy = Math.abs(event.clientY - drag.y);
        if (Math.max(dx, dy) < 5) return;
        if (dy > dx) { drag = null; return; }
        drag.active = true;
      }
      move(event.clientX);
    });
    handle.addEventListener('pointerup', event => {
      if (drag?.id === event.pointerId && drag.active) move(event.clientX);
      drag = null;
    });
    for (const type of ['pointercancel', 'lostpointercapture']) {
      handle.addEventListener(type, () => { drag = null; });
    }
    handle.addEventListener('keydown', event => {
      const current = Number(handle.getAttribute('aria-valuenow'));
      const step = event.shiftKey ? 10 : 1;
      const values = {ArrowLeft: current - step, ArrowDown: current - step,
        ArrowRight: current + step, ArrowUp: current + step, Home: 0, End: 100,
        PageDown: current - 10, PageUp: current + 10};
      if (!(event.key in values)) return;
      event.preventDefault();
      setSplit(values[event.key]);
    });
    handle.hidden = false;
    return setSplit;
  }
  const comparisons = new Map();
  for (const frame of document.querySelectorAll('[data-compare]')) {
    comparisons.set(frame, initComparison(frame));
  }
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
    if (target?.hasAttribute('data-endpoint')) {
      comparisons.get(target.closest('[data-compare]'))(Number(target.dataset.endpoint));
    }
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
