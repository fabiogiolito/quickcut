// QuickCut demo: a scripted, looping recreation of the app window.
// Times in the "video" are seconds; playback runs at SPEED× so the loop stays short.
const $ = (s) => document.querySelector(s);
const stage = $('#stage'), win = $('#win'), segsEl = $('#segs'), ph = $('#ph'), frame = $('#frame'),
  timeEl = $('#time'), files = $('#files'), titleEl = $('#title'), hud = $('#hud'), cursor = $('#cursor');
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
const SPEED = 2;
const SHOTS = [[0, 3, 'sunset'], [3, 7, 'ocean'], [7, 12, 'meadow']];
const FILM = '<svg viewBox="0 0 16 16"><rect x="1.5" y="2.5" width="13" height="11" rx="2" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M4.5 2.5v11M11.5 2.5v11M1.5 6h3M1.5 10h3M11.5 6h3M11.5 10h3" stroke="currentColor" stroke-width="1.1"/></svg>';

let scale = 1, segs = [], t = 0, playing = false, sel = new Set(), clipCount = 0;
const els = new Map();

// Layout: fixed design size, scaled to fit. Narrow screens get the collapsed-sidebar window.
function layout() {
  const w = stage.clientWidth, compact = w < 640;
  const W = compact ? 560 : 900, H = compact ? 420 : 560;
  scale = w / W;
  win.classList.toggle('compact', compact);
  Object.assign(win.style, { width: W + 'px', height: H + 'px', transform: `scale(${scale})` });
  stage.style.height = H * scale + 'px';
}
new ResizeObserver(layout).observe(stage);
layout();

// Model, mirroring Model.swift
const total = () => segs.reduce((a, s) => a + s.end - s.start, 0);
const startOf = (i) => segs.slice(0, i).reduce((a, s) => a + s.end - s.start, 0);
const idx = (id) => segs.findIndex((s) => s.id === id);
function locate(time) {
  let acc = 0;
  for (let i = 0; i < segs.length; i++) {
    const d = segs[i].end - segs[i].start;
    if (time < acc + d) return { i, off: time - acc };
    acc += d;
  }
  return null;
}
const fmt = (s) => `${Math.floor(s / 60)}:${(s % 60).toFixed(2).padStart(5, '0')}`;

function addSeg(seg, after) {
  const el = document.createElement('div');
  el.className = 'seg';
  el.innerHTML = `<span>${seg.name}</span>`;
  el.style.setProperty('--h', seg.hue);
  el.style.flexGrow = seg.end - seg.start;
  els.set(seg.id, el);
  after ? after.after(el) : segsEl.append(el);
  return el;
}

function render() {
  const tot = total();
  ph.style.left = (tot ? (t / tot) * 100 : 0) + '%';
  timeEl.textContent = `${fmt(t)} / ${fmt(tot)}`;
  const hit = locate(t), s = hit ? segs[hit.i] : segs[segs.length - 1];
  if (s) {
    const src = hit ? s.start + hit.off : s.end - 0.01;
    const [a, b, name] = SHOTS.find(([a, b]) => src < b) || SHOTS[2];
    frame.dataset.shot = name;
    frame.style.setProperty('--p', Math.min(1, (src - a) / (b - a)).toFixed(3));
  }
  win.classList.toggle('playing', playing);
  els.forEach((el, id) => el.classList.toggle('sel', sel.has(id)));
  $('#delBtn').classList.toggle('off', !sel.size || sel.size >= segs.length);
}

let last = performance.now();
function tick(now) {
  const dt = Math.min(now - last, 50) / 1000;
  last = now;
  if (playing) t = Math.min(t + dt * SPEED, total());
  render();
  requestAnimationFrame(tick);
}

// Helpers
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const until = (fn) => new Promise((r) => { const c = () => (fn() ? r() : requestAnimationFrame(c)); c(); });
function center(el) {
  const r = el.getBoundingClientRect(), w = win.getBoundingClientRect();
  return { x: (r.left + r.width / 2 - w.left) / scale, y: (r.top + r.height / 2 - w.top) / scale };
}
async function moveTo({ x, y }, ms = 600, ghost) {
  for (const el of [cursor, ghost]) if (el) el.style.setProperty('--d', ms + 'ms');
  cursor.style.left = x + 'px'; cursor.style.top = y + 'px';
  if (ghost) { ghost.style.left = x - ghost.offsetWidth / 2 + 'px'; ghost.style.top = y - ghost.offsetHeight / 2 + 'px'; }
  await sleep(ms);
}
async function click() { cursor.classList.add('down'); await sleep(120); cursor.classList.remove('down'); }
function key(keys, label, btn) {
  hud.classList.remove('show');
  hud.innerHTML = keys.map((k) => `<kbd${k.length > 1 ? ' class="wide"' : ''}>${k}</kbd>`).join('') + `<span>${label}</span>`;
  void hud.offsetWidth;
  hud.classList.add('show');
  if (btn) { btn.classList.add('flash'); setTimeout(() => btn.classList.remove('flash'), 250); }
}
function fileRow(name, on) {
  const li = document.createElement('li');
  li.className = on ? 'on' : '';
  li.innerHTML = FILM + `<span>${name}</span>`;
  files.append(li);
  return li;
}

// Actions, same rules as the app
function open() {
  fileRow('Beach Trip', true);
  titleEl.textContent = 'Beach Trip';
  clipCount = 1;
  segs = [{ id: 1, name: 'Clip 1', start: 0, end: 12, hue: 0 }];
  addSeg(segs[0]);
  win.classList.add('open');
}
function cut() {
  const hit = locate(t);
  if (!hit) return;
  const left = segs[hit.i], n = ++clipCount;
  const right = { id: n, name: `Clip ${n}`, start: left.start + hit.off, end: left.end, hue: ((n - 1) % 6) * 60 };
  left.end = right.start;
  segs.splice(hit.i + 1, 0, right);
  const lel = els.get(left.id);
  lel.style.transition = 'none';
  lel.style.flexGrow = left.end - left.start;
  const rel = addSeg(right, lel);
  rel.style.transition = 'none';
  void rel.offsetWidth;
  lel.style.transition = rel.style.transition = '';
  rel.classList.add('cutflash');
  setTimeout(() => rel.classList.remove('cutflash'), 700);
}
function selectUnderPlayhead() { const h = locate(t); sel = new Set(h ? [segs[h.i].id] : []); }
function del() {
  if (!sel.size || sel.size >= segs.length) return;
  for (const id of sel) {
    const el = els.get(id);
    el.classList.add('gone');
    el.style.flexGrow = 0;
    els.delete(id);
    setTimeout(() => el.remove(), 400);
  }
  segs = segs.filter((s) => !sel.has(s.id));
  t = Math.min(t, total());
  selectUnderPlayhead();
}
function move(id, target) {
  const before = new Map([...els].map(([k, el]) => [k, el.getBoundingClientRect().left]));
  const hit = locate(t), carried = hit && segs[hit.i].id === id;
  segs.splice(idx(target), 0, segs.splice(idx(id), 1)[0]);
  segs.forEach((s) => segsEl.append(els.get(s.id)));
  if (carried) t = startOf(idx(id)) + hit.off;
  els.forEach((el, k) => { // FLIP: slide each segment from where it was
    el.style.transition = 'none';
    el.style.transform = `translateX(${(before.get(k) - el.getBoundingClientRect().left) / scale}px)`;
    void el.offsetWidth;
    el.style.transition = el.style.transform = '';
  });
}
function reset() {
  segs = []; sel = new Set(); t = 0; playing = false; clipCount = 0;
  els.clear(); segsEl.innerHTML = ''; files.innerHTML = ''; hud.innerHTML = '';
  titleEl.textContent = 'QuickCut';
  win.classList.remove('open');
}

async function run() {
  reset();
  cursor.classList.add('hidden');
  await moveTo({ x: win.offsetWidth * 0.7, y: win.offsetHeight * 0.45 }, 0);
  win.classList.remove('reset');
  await sleep(1200);

  key(['⌘', 'O'], 'Open video');
  await sleep(350);
  open();
  await sleep(1300);

  key(['Space'], 'Play', $('#playBtn'));
  playing = true;
  await until(() => t >= 3);
  key(['⌘', 'B'], 'Cut at playhead', $('#cutBtn'));
  cut();
  await until(() => t >= 7);
  key(['⌘', 'B'], 'Cut at playhead', $('#cutBtn'));
  cut();
  await until(() => t >= 8.6);
  key(['Space'], 'Pause', $('#playBtn'));
  playing = false;
  selectUnderPlayhead();
  await sleep(900);

  // Click the middle clip, delete it.
  cursor.classList.remove('hidden');
  const clip2 = els.get(2);
  await moveTo(center(clip2), 800);
  await click();
  sel = new Set([2]);
  t = startOf(idx(2)) + 2;
  await sleep(700);
  key(['⌫'], 'Delete segment', $('#delBtn'));
  del();
  await sleep(1400);

  // Drag Clip 3 onto Clip 1.
  const clip3 = els.get(3), ghost = clip3.cloneNode(true);
  await moveTo(center(clip3), 700);
  cursor.classList.add('down');
  sel = new Set([3]);
  ghost.className = 'seg ghost';
  ghost.style.width = clip3.offsetWidth + 'px';
  ghost.style.height = clip3.offsetHeight + 'px';
  win.append(ghost);
  await moveTo(center(clip3), 0, ghost);
  clip3.classList.add('lifted');
  hud.classList.remove('show');
  hud.innerHTML = '<span>Drag to reorder</span>';
  await sleep(150);
  const strip = segsEl.getBoundingClientRect(), win0 = win.getBoundingClientRect();
  await moveTo({ x: (strip.left - win0.left) / scale + ghost.offsetWidth / 2, y: center(clip3).y }, 900, ghost); // drop over Clip 1
  cursor.classList.remove('down');
  ghost.remove();
  clip3.classList.remove('lifted');
  move(3, 1);
  await sleep(1000);

  // Save.
  await moveTo({ x: win.offsetWidth * 0.62, y: win.offsetHeight * 0.4 }, 700);
  cursor.classList.add('hidden');
  key(['⌘', 'S'], 'Save “Beach Trip edit.mov”');
  const row = fileRow('Beach Trip edit');
  row.insertAdjacentHTML('beforeend', '<svg class="ring" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-opacity=".25" stroke-width="2"/><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="37.7" stroke-dashoffset="37.7" transform="rotate(-90 8 8)" style="transition:stroke-dashoffset 1s linear"/></svg>');
  await sleep(50);
  row.querySelector('circle:last-child').style.strokeDashoffset = 0;
  await sleep(1100);
  row.querySelector('.ring').remove();
  await sleep(2600);

  win.classList.add('reset');
  await sleep(450);
}

$('#copy').addEventListener('click', async (e) => {
  try { await navigator.clipboard.writeText($('#cmd').textContent); e.target.textContent = 'Copied'; }
  catch { e.target.textContent = 'Select & copy'; }
  setTimeout(() => (e.target.textContent = 'Copy'), 1600);
});

if (reduce) {
  // Static frame: the finished edit, no motion.
  open();
  fileRow('Beach Trip edit');
  t = 3; cut(); t = 7; cut();
  sel = new Set([2]); del();
  move(3, 1);
  sel = new Set(); t = 1.2;
  cursor.classList.add('hidden');
  hud.innerHTML = '<kbd>⌘</kbd><kbd>B</kbd><span>cut</span>&nbsp;&nbsp;<kbd>⌫</kbd><span>delete</span>&nbsp;&nbsp;<kbd>⌘</kbd><kbd>S</kbd><span>save</span>';
  render();
} else {
  requestAnimationFrame(tick);
  (async () => { for (;;) await run(); })();
}
