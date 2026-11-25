/* Native scroll remains in charge. Each surface follows a short, reversible,
   viewport-driven animation; a stopped scroll is a stopped timeline. */
(() => {
  'use strict';
  if (!Element.prototype.animate) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const narrow = matchMedia('(max-width: 650px)');
  const wideStory = matchMedia('(min-width: 900px) and (min-height: 640px)');
  const edge = document.querySelector('.border-feature');
  let lens = null;

  // [selector, surface, sequence]. Media leads, labels and prose follow.
  const recipe = [
    ['main .overprint:not(.hero .overprint) > h2',                 'title',    0],
    ['main .overprint:not(.hero .overprint) > .overprint-plate',   'outline',  0],
    ['main .overprint:not(.hero .overprint) > .overprint-label',   'label',    1],
    ['.section-row > .text-link, .material-copy > p',             'caption',  1],
    ['.selected-grid .selection:nth-child(1) .print-carriage',     'left',     0],
    ['.selected-grid .selection:nth-child(2) .print-carriage',     'mid',      1],
    ['.selected-grid .selection:nth-child(3) .print-carriage',     'right',    2],
    ['.selected-grid .selection > div, .work-credit',             'caption',  1],
    ['.border-feature .print-carriage',                          'strip',    0],
    ['.border-feature figcaption, .art-credit',                  'caption',  1],
    ['.cover-grid figure .print-carriage',                       'cover',   -1],
    ['.cover-grid figcaption',                                   'label',   -1],
    ['.device .capture img',                                     'screen',   0],
    ['.device > div, .device-note, .reading > p',                 'caption',  1],
    ['.platforms > *, .related > div',                           'caption', -1],
    ['.case-meta, .detail-study figcaption',                     'caption',  0],
    ['.process-image, .compare-pair > figure',                   'screen',  -1],
    ['.steps > *, .note-content > p',                            'caption', -1]
  ];

  // x/y (px), rotation, initial scale, opacity, initial matte, then end line.
  const profiles = {
    title:   [ 0, 30,  0,    1,    .82,  0, .57],
    outline: [ 0, 11,  0,    1,    .55,  0, .48],
    label:   [ 0, 12,  0,    1,    .88,  0, .59],
    caption: [ 0, 17,  0,    1,    .86,  0, .63],
    left:    [-5, 39, -1.3,  .98,  .92, 10, .48],
    mid:     [ 0, 33,  0,    .975, .95,  7, .44],
    right:   [ 5, 39,  1.2,  .98,  .92, 12, .47],
    strip:   [-48, 4,  -.5,  .97,  .90,  0, .46],
    cover:   [ 0, 25,  0,    .965, .9,   0, .57],
    screen:  [ 0, 37,  0,    .962, .95,  0, .43]
  };

  let items = [], raf = 0, remeasure = true;
  function documentTop(el) {
    let y = el.offsetTop;
    while ((el = el.offsetParent)) y += el.offsetTop + el.clientTop;
    return y;
  }
  function install() {
    for (const {animation} of items) animation.cancel();
    items = [];
    lens?.reveal.cancel();
    lens = null;
    const sticky = Boolean(edge?.querySelector('.edge-stage img')) && wideStory.matches && !reduced.matches;
    edge?.classList.toggle('edge-story', sticky);
    if (reduced.matches) return;
    if (sticky) {
      const stage = edge.querySelector('.edge-stage');
      const reveal = stage.querySelector('img').animate([
        {clipPath:'inset(14.9% 2.3% 15.5% 1.2%)'},
        {clipPath:'inset(0% 0% 0% 0%)'}
      ],{duration:1000,fill:'both',easing:'cubic-bezier(.32,.06,.24,1)'});
      reveal.pause();
      reveal.currentTime = 0;
      edge.dataset.edgeStep = '0';
      lens = {reveal,appliedReveal:0};
    }
    const mobile = narrow.matches;
    const q = mobile ? .73 : 1;
    const registered = new Set();
    for (const [selector,type,sequence] of recipe) {
      for (const el of document.querySelectorAll(selector)) {
        if (registered.has(el) || (sticky && el.closest('.edge-stage'))) continue;
        registered.add(el);
        const [x,y,angle,scale,opacity,matte,endLine] = profiles[type];
        const first = {transform:`translate(${x*q}px,${y*q}px) rotate(${angle*q}deg) scale(${scale})`,opacity};
        const last = {transform:'translate(0px,0px) rotate(0deg) scale(1)',opacity:1};
        if (matte) {
          first.clipPath = `inset(0 0 ${matte}% 0)`;
          last.clipPath = 'inset(0 0 0 0)';
        }
        const animation = el.animate([first,last],{duration:1000,fill:'both',
          easing: type === 'title' || type === 'caption' || type === 'label'
            ? 'cubic-bezier(.22,.67,.27,1)' : 'cubic-bezier(.34,.04,.22,1)'});
        animation.pause();
        animation.currentTime = 1000;
        const parent = el.parentElement;
        const sibling = parent.matches('.platforms, .compare-pair, .steps') ? el : parent;
        const slot = Array.prototype.indexOf.call(sibling.parentElement?.children || [],sibling);
        const beat = mobile ? 0 : sequence < 0 ? Math.max(0,slot) % 4 : sequence;
        const startLine = .995 - .054 * beat - (type === 'label' ? .036 : 0);
        items.push({el,animation,startLine,endLine:endLine - .012 * beat,applied:1000});
      }
    }
    remeasure = true;
    queue();
  }
  function tick() {
    raf = 0;
    if (reduced.matches) return;
    const viewport = innerHeight;
    const y = Math.max(0,scrollY);
    if (remeasure) {
      const last = Math.max(0,document.documentElement.scrollHeight - viewport);
      for (const p of items) {
        p.hidden = !p.el.getClientRects().length;
        if (p.hidden) continue;
        const top = documentTop(p.el);
        p.start = top - viewport*p.startLine;
        p.end = Math.min(last,top - viewport*p.endLine);
      }
      if (lens) {
        const top = documentTop(edge);
        lens.top = top;
      }
      remeasure = false;
    }
    if (lens) {
      const position = (y - lens.top)/viewport;
      const progress = (start,end) => Math.round(1000*Math.max(0,Math.min(1,(position-start)/(end-start))));
      const r = progress(.06,.39);
      if (r !== lens.appliedReveal) {
        lens.reveal.currentTime = r;
        lens.appliedReveal = r;
      }
      const step = position > .66 ? '2' : r > 350 ? '1' : '0';
      if (edge.dataset.edgeStep !== step) edge.dataset.edgeStep = step;
    }
    const targeted = location.hash && document.getElementById(location.hash.slice(1));
    for (const p of items) {
      if (p.hidden) continue;
      const immediate = (targeted && (targeted === p.el || targeted.contains(p.el)))
        || Boolean(p.el.closest(':focus-within')?.querySelector(':focus-visible'));
      const time = immediate ? 1000
        : Math.round(1000*Math.max(0,Math.min(1,(y-p.start)/Math.max(1,p.end-p.start))));
      if (time === p.applied) continue;
      p.animation.currentTime = time;
      p.applied = time;
    }
  }
  function queue() { if (!raf && !reduced.matches) raf = requestAnimationFrame(tick); }
  function measureNext() { remeasure = true; queue(); }

  addEventListener('scroll',queue,{passive:true});
  addEventListener('resize',measureNext,{passive:true});
  addEventListener('hashchange',measureNext);
  addEventListener('load',measureNext,{once:true});
  document.addEventListener('focusin',queue);
  document.addEventListener('focusout',queue);
  document.addEventListener('toggle',measureNext,true);
  if ('ResizeObserver' in window) new ResizeObserver(measureNext).observe(document.body);
  const devices = new MutationObserver(measureNext);
  for (const panel of document.querySelectorAll('.device')) devices.observe(panel,{attributes:true,attributeFilter:['hidden']});
  reduced.addEventListener('change',install);
  narrow.addEventListener('change',install);
  wideStory.addEventListener('change',install);
  install();
})();
