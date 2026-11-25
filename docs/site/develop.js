/* SPDX-License-Identifier: GPL-3.0-or-later
 * Browser presentation port of Silverphase Canvas/Renderer.swift and
 * Canvas/Shaders.metal (akinal5765-byte/Silverphase, derived from Hanze Qiu's
 * SpektraLab). The native shader adapts Andrea Volpato's spektrafilm
 * polaroid_animation.py at 3bb2c2d2801ff68b92019cf1dbcbb133d60832bc.
 * Intermediate frames are presentation only. Not an image-processing engine.
 * The full GPL text is distributed alongside this source.
 */
(() => {
  'use strict';
  const demo = document.querySelector('[data-develop]');
  if (!demo) return;
  const duration = 2200;
  const stage = demo.querySelector('.print-stage');
  const canvas = stage.querySelector('canvas');
  const slider = stage.querySelector('.divider');
  const positive = stage.querySelector('.positive');
  const play = stage.querySelector('[data-play]');
  const playLabel = play.querySelector('[data-play-label]');
  const status = demo.querySelector('[data-status]');
  const preference = matchMedia('(prefers-reduced-motion: reduce)');
  let raf = 0, generation = 0, gpu, negativeTask;
  let returnToCompare = 0;
  const firstPlayLabel = playLabel.textContent;
  let hasPlayed = false;
  const vertexSource = `
attribute vec2 xy;
varying vec2 uv;
void main() {
  uv = vec2(0.5 + 0.5 * xy.x, 0.5 - 0.5 * xy.y);
  gl_Position = vec4(xy, 0., 1.);
}`;
  const fragmentSource = `
precision highp float;
varying vec2 uv;
uniform sampler2D negativeFrame;
uniform sampler2D printFrame;
uniform float time;

float sigmoid(float t, float center, float slope) {
    float start = 1. / (1. + exp(center * slope));
    float end = 1. / (1. + exp(-(1. - center) * slope));
    float value = 1. / (1. + exp(-(t - center) * slope));
    return clamp((value - start) / (end - start), 0., 1.);
}
float rise(float t, float center, float slope, float tail) {
    float r = sigmoid(t, center, slope);
    return r + (1. - r) * pow(t, tail);
}
float pulse(float t, float on, float onSlope, float off, float offSlope, float decay) {
    return sigmoid(t, on, onSlope) * (1. - sigmoid(t, off, offSlope)) * pow(1. - t, decay);
}
float sRGBDecode(float v) {
    return v <= .040449936 ? v / 12.92 : pow((v + .055) / 1.055, 2.4);
}
float sRGBEncode(float v) {
    return v <= .0031308 ? v * 12.92 : 1.055 * pow(v, 1. / 2.4) - .055;
}
float rommEncode(float v) {
    return v < 1. / 512. ? 16. * v : pow(v, 1. / 1.8);
}
float rommDecode(float v) {
    return v < 16. / 512. ? v / 16. : pow(v, 1.8);
}
vec3 rommEncode3(vec3 color) {
    return vec3(rommEncode(color.r), rommEncode(color.g), rommEncode(color.b));
}
vec3 toROMM(vec3 color) {
    vec3 linear = vec3(sRGBDecode(color.r), sRGBDecode(color.g), sRGBDecode(color.b));
    // Columns of the inverse of the neutral-normalized Silverphase
    // ProPhoto->linear Rec.709 matrix (CineonLUT.swift).
    mat3 toPhoto = mat3(.52920885, .09837752, .01687616,
                        .33020557, .87349104, .11769881,
                        .14058558, .02813144, .86542503);
    return rommEncode3(toPhoto * linear);
}
vec3 toSRGB(vec3 color) {
    vec3 linear = vec3(rommDecode(color.r), rommDecode(color.g), rommDecode(color.b));
    mat3 to709 = mat3(2.03469887, -.22888402, -.00854901,
                     -.72782711, 1.23174142, -.15332533,
                     -.30687176, -.00285740, 1.16187434);
    linear = clamp(to709 * linear, 0., 1.);
    return vec3(sRGBEncode(linear.r), sRGBEncode(linear.g), sRGBEncode(linear.b));
}
vec3 developPaper(vec3 printed, float t) {
    vec3 linear = vec3(rommDecode(printed.r), rommDecode(printed.g), rommDecode(printed.b));
    vec3 density = clamp(-log(max(linear, vec3(.0001))), 0., 9.21034);
    float neutral = min(density.r, min(density.g, density.b));
    vec3 chroma = density - neutral;
    vec3 latent = clamp(density / 6., 0., 1.);
    vec3 chromaLatent = clamp(chroma / 6., 0., 1.);
    float shadow = clamp(dot(density, vec3(.34, .39, .27)) / 1.75, 0., 1.);
    float highlight = 1. - shadow;
    float strength = max(chromaLatent.r, max(chromaLatent.g, chromaLatent.b));
    float warmth = clamp((chroma.g + 1.25 * chroma.b - .85 * chroma.r)
        / (chroma.r + chroma.g + chroma.b + .0001), 0., 1.);
    float body = rise(t, .19, 7.4, 3.8);
    vec3 result = vec3(neutral * body * rise(t, .12, 8., 2.8));
    result += chroma * body * vec3(rise(t, .52, 9.4, 5.4), rise(t, .31, 10.2, 3.4), rise(t, .22, 11., 3.));
    vec3 receiver = (.30 + .70 * highlight) * vec3(.04, .08, .15);
    float silverMap = clamp(.24 + .46 * shadow + .30 * clamp(neutral / 6., 0., 1.), 0., 1.);
    vec3 silver = clamp(silverMap * vec3(.18, .19, .20) + chromaLatent.gbr * vec3(.03, .02, .04), 0., .28);
    vec3 anti = (highlight * vec3(.10, .06, .02) + (1. - latent.brg) * vec3(.13, .07, .18)
                 + chromaLatent.gbr * vec3(.04, .02, .06)) * (.40 + .60 * highlight);
    vec3 warm = (.24 + .42 * highlight + .34 * max(warmth, strength)) * vec3(.02, .08, .19);
    result += receiver * 1.08 * pow(1. - t, .46);
    result += silver * pulse(t, .05, 32., .44, 8., .24);
    result += anti * 1.22 * pulse(t, .10, 54., .28, 28., .18);
    result += warm * .96 * pulse(t, .12, 20., .80, 6.5, .34);
    result += highlight * vec3(.03, .06, .11) * .68 * pulse(t, .03, 24., .98, 4., .08);
    return mix(rommEncode3(exp(-result)), printed, smoothstep(.84, 1., t));
}
void main() {
    vec3 negative = texture2D(negativeFrame, uv).rgb;
    vec3 printed = texture2D(printFrame, uv).rgb;
    if (time <= 0.) { gl_FragColor = vec4(negative, 1.); return; }
    if (time >= 1.) { gl_FragColor = vec4(printed, 1.); return; }
    float paperTime = clamp((time - .10) / .90, 0., 1.);
    vec3 paper = developPaper(toROMM(printed), paperTime);
    vec3 result = mix(toROMM(negative), paper, smoothstep(0., .10, time));
    gl_FragColor = vec4(toSRGB(result), 1.);
}`;

  function shader(gl,type,source) {
    const s = gl.createShader(type);
    gl.shaderSource(s,source);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s,gl.COMPILE_STATUS)) {
      throw new Error('Develop GLSL: ' + gl.getShaderInfoLog(s));
    }
    return s;
  }
  function makeGPU(negative,printFrame) {
    const gl = canvas.getContext('webgl',{alpha:false,depth:false,antialias:false,powerPreference:'low-power'});
    if (!gl) throw new Error('WebGL unavailable');
    const program = gl.createProgram();
    gl.attachShader(program,shader(gl,gl.VERTEX_SHADER,vertexSource));
    gl.attachShader(program,shader(gl,gl.FRAGMENT_SHADER,fragmentSource));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program,gl.LINK_STATUS)) throw new Error('Develop link: ' + gl.getProgramInfoLog(program));
    gl.useProgram(program);
    const geometry = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER,geometry);
    gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,1,1]),gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(program,'xy');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0);
    // Endpoints are opaque SDR sRGB WebPs; no implicit upload transform.
    gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL,gl.NONE);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);
    for (const [i,name,img] of [[0,'negativeFrame',negative],[1,'printFrame',printFrame]]) {
      const tx = gl.createTexture();
      gl.activeTexture(gl.TEXTURE0+i);
      gl.bindTexture(gl.TEXTURE_2D,tx);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGB,gl.RGB,gl.UNSIGNED_BYTE,img);
      gl.uniform1i(gl.getUniformLocation(program,name),i);
    }
    if (gl.getError() !== gl.NO_ERROR) throw new Error('Texture upload failed');
    const time = gl.getUniformLocation(program,'time');
    return t => {
      gl.viewport(0,0,canvas.width,canvas.height);
      gl.uniform1f(time,t);
      gl.drawArrays(gl.TRIANGLE_STRIP,0,4);
    };
  }
  const load = (src) => new Promise((resolve,reject) => {
    const im = new Image();
    im.onload = () => resolve(im);
    im.onerror = () => reject(new Error('Missing render'));
    im.src = src;
  });
  // The fallback clip was rendered with the same shader and endpoints.
  const clip = document.createElement('video');
  clip.hidden = true;
  clip.muted = true;
  clip.playsInline = true;
  clip.preload = 'none';
  clip.setAttribute('aria-hidden', 'true');
  stage.insertBefore(clip, canvas);

  function setView(mode) {
    generation++;
    cancelAnimationFrame(raf);
    clearTimeout(returnToCompare);
    clip.pause();
    clip.hidden = true;
    canvas.hidden = true;
    demo.dataset.mode = mode;
    slider.hidden = mode !== 'split';
    playLabel.textContent = mode === 'playing' ? demo.dataset.skip :
      (hasPlayed ? demo.dataset.replay : firstPlayLabel);
  }
  function finish(message = demo.dataset.finished, holdPrint = false) {
    hasPlayed = true;
    setView(holdPrint && !preference.matches ? 'print' : 'split');
    status.textContent = message;
    if (demo.dataset.mode === 'print') {
      // Hold the actual final still briefly, then restore the visitor's divider.
      returnToCompare = setTimeout(() => setView('split'), 260);
    }
  }

  async function playClip(token) {
    if (token !== generation) return;
    if (preference.matches) { finish(); return; }
    if (!clip.getAttribute('src')) clip.src = new URL('develop-replay.mp4', positive.src).href;
    if (clip.readyState > 0) clip.currentTime = 0;
    clip.onended = () => { if (token === generation) finish(demo.dataset.finished, true); };
    clip.onerror = () => { if (token === generation) finish(demo.dataset.fallback); };
    try {
      await clip.play();
      if (token === generation && !preference.matches) clip.hidden = false;
    } catch { if (token === generation) finish(demo.dataset.fallback); }
  }
  async function replay() {
    if (demo.dataset.mode === 'playing' || preference.matches) { finish(); return; }
    setView('playing');
    const token = generation;
    status.textContent = demo.dataset.playing;
    try {
      negativeTask ||= load(demo.dataset.negative).catch(error => {
        negativeTask = undefined;
        throw error;
      });
      const [negative] = await Promise.all([negativeTask, positive.decode()]);
      if (token !== generation) return;
      if (negative.naturalWidth !== positive.naturalWidth || negative.naturalHeight !== positive.naturalHeight) {
        finish(demo.dataset.fallback);
        return;
      }
      const width = Math.min(1280, positive.naturalWidth, stage.clientWidth * Math.min(devicePixelRatio || 1, 1.5));
      canvas.width = Math.max(1, Math.round(width));
      canvas.height = Math.max(1, Math.round(width * positive.naturalHeight / positive.naturalWidth));
      if (!gpu) gpu = makeGPU(negative, positive);
      gpu(0);
      canvas.hidden = false;
      const start = performance.now();
      function advance(now) {
        if (token !== generation) return;
        const t = Math.min(1, Math.max(0, (now - start) / duration));
        if (t >= 1 || preference.matches) { finish(demo.dataset.finished, true); return; }
        gpu(t);
        raf = requestAnimationFrame(advance);
      }
      raf = requestAnimationFrame(advance);
    } catch { await playClip(token); }
  }
  play.addEventListener('click', replay);
  function updateMotion() {
    if (preference.matches && demo.dataset.mode !== 'split') finish();
    play.hidden = preference.matches;
  }
  if (preference.addEventListener) preference.addEventListener('change', updateMotion);
  else preference.addListener(updateMotion);
  canvas.addEventListener('webglcontextlost', event => {
    event.preventDefault();
    gpu = undefined;
    if (demo.dataset.mode === 'playing' && !canvas.hidden) {
      cancelAnimationFrame(raf);
      canvas.hidden = true;
      void playClip(generation);
    }
  });
  window.addEventListener('pagehide', () => { if (demo.dataset.mode === 'playing') finish(); });
  setView('split');
  updateMotion();
})();
