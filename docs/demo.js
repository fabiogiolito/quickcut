// QuickCut demo: a scripted, looping recreation of the app window.
// Times in the "video" are seconds; playback runs at SPEED× so the loop stays short.
const $ = (s) => document.querySelector(s);
const stage = $('#stage'), win = $('#win'), segsEl = $('#segs'), ph = $('#ph'), frame = $('#frame'),
  timeEl = $('#time'), files = $('#files'), titleEl = $('#title'), hud = $('#hud'), cursor = $('#cursor'), menu = $('#menu');
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
const SPEED = 2;
const SHOTS = [[0, 3, 'sunset'], [3, 7, 'ocean'], [7, 12, 'meadow']];
const FILM = '<svg viewBox="0 0 16 16"><rect x="1.5" y="2.5" width="13" height="11" rx="2" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M4.5 2.5v11M11.5 2.5v11M1.5 6h3M1.5 10h3M11.5 6h3M11.5 10h3" stroke="currentColor" stroke-width="1.1"/></svg>';

let scale = 1, takes = [], cur = null, segs = [], t = 0, playing = false, sel = new Set();
const els = new Map();

// Layout: fixed design size, scaled to fit the stage's width and height, centred.
function layout() {
  const w = stage.clientWidth, h = stage.clientHeight, compact = w < 640;
  const W = compact ? 580 : 900, H = compact ? 440 : 560;
  stage.style.aspectRatio = `${W} / ${H}`;
  scale = Math.min(w / W, h / H);
  win.classList.toggle('compact', compact);
  Object.assign(win.style, { width: W + 'px', height: H + 'px',
    transform: `translate(${(w - W * scale) / 2}px, ${(h - H * scale) / 2}px) scale(${scale})` });
}
new ResizeObserver(layout).observe(stage);
layout();

// Model, mirroring Model.swift. A take's `src` is where its file starts in the shared source footage.
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
let nextId = 1;
const seg = (n, start, end) => ({ id: nextId++, name: `Clip ${n}`, start, end, hue: ((n - 1) % 6) * 60 });

function segEl(s, after) {
  const el = document.createElement('div');
  el.className = 'seg';
  el.innerHTML = `<span>${s.name}</span>`;
  el.style.setProperty('--h', s.hue);
  el.style.flexGrow = s.end - s.start;
  els.set(s.id, el);
  after ? after.after(el) : segsEl.append(el);
  return el;
}

function render() {
  const tot = total();
  ph.style.left = (tot ? (t / tot) * 100 : 0) + '%';
  timeEl.textContent = `${fmt(t)} / ${fmt(tot)}`;
  const hit = locate(t), s = hit ? segs[hit.i] : segs[segs.length - 1];
  if (s) {
    const src = cur.src + (hit ? s.start + hit.off : s.end - 0.01);
    const [a, b, name] = SHOTS.find(([, b]) => src < b) || SHOTS[2];
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
const say = (label) => key([], label);

// Actions, same rules as the app
function addTake(name, src, dur) {
  const tk = { name, src, segs: [seg(1, 0, dur)], clipCount: 1, row: document.createElement('li') };
  tk.row.innerHTML = FILM + `<span>${name}</span>`;
  files.append(tk.row);
  takes.push(tk);
  return tk;
}
function showTake(tk) {
  if (cur) cur.segs = segs;
  cur = tk; segs = tk.segs; t = 0; sel = new Set(); playing = false;
  els.clear(); segsEl.innerHTML = '';
  segs.forEach((s) => segEl(s));
  takes.forEach((x) => x.row.classList.toggle('on', x === tk));
  titleEl.textContent = tk.name;
  win.classList.add('open');
}
// Export: the new file shows up in the sidebar right away with a progress ring, like the app.
async function exportAs(name, src, dur) {
  const tk = addTake(name, src, dur);
  tk.row.insertAdjacentHTML('beforeend', '<svg class="ring" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-opacity=".25" stroke-width="2"/><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="37.7" stroke-dashoffset="37.7" transform="rotate(-90 8 8)" style="transition:stroke-dashoffset 1s linear"/></svg>');
  const ring = tk.row.querySelector('.ring');
  if (!reduce) { await sleep(50); ring.lastChild.style.strokeDashoffset = 0; await sleep(1100); }
  ring.remove();
  return tk;
}
function cut() {
  const hit = locate(t);
  if (!hit) return;
  const left = segs[hit.i], right = seg(++cur.clipCount, left.start + hit.off, left.end);
  left.end = right.start;
  segs.splice(hit.i + 1, 0, right);
  const lel = els.get(left.id);
  lel.style.transition = 'none';
  lel.style.flexGrow = left.end - left.start;
  const rel = segEl(right, lel);
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
  sel = new Set();
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
  takes = []; cur = null; segs = []; sel = new Set(); t = 0; playing = false;
  els.clear(); segsEl.innerHTML = ''; files.innerHTML = ''; hud.innerHTML = '';
  titleEl.textContent = 'QuickCut';
  win.classList.remove('open');
  menu.classList.remove('show');
}

async function run() {
  reset();
  cursor.classList.add('hidden');
  await moveTo({ x: win.offsetWidth * 0.7, y: win.offsetHeight * 0.45 }, 0);
  win.classList.remove('reset');
  await sleep(1000);

  // Open, play, cut into three clips.
  key(['⌘', 'O'], 'Open video');
  await sleep(350);
  showTake(addTake('Beach Trip', 0, 12));
  await sleep(1100);
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
  await sleep(700);

  // Right-click Clip 2 → Save Clip: it lands in the sidebar as its own file.
  const [c1, c2, c3] = segs;
  cursor.classList.remove('hidden');
  await moveTo(center(els.get(c2.id)), 800);
  say('Right-click › Save Clip');
  await click();
  const p = center(els.get(c2.id));
  Object.assign(menu.style, { left: p.x + 'px', top: p.y - 92 + 'px' });
  menu.classList.add('show');
  await sleep(500);
  const item = $('#saveClipItem');
  await moveTo(center(item), 450);
  item.classList.add('hi');
  await click();
  await sleep(120);
  menu.classList.remove('show');
  item.classList.remove('hi');
  const clipTake = await exportAs('Beach Trip Clip 2', c2.start, c2.end - c2.start);
  await sleep(500);

  // Drag Clip 3 onto Clip 1 to swap their order.
  const el3 = els.get(c3.id), ghost = el3.cloneNode(true);
  await moveTo(center(el3), 700);
  cursor.classList.add('down');
  sel = new Set([c3.id]);
  ghost.className = 'seg ghost';
  ghost.style.width = el3.offsetWidth + 'px';
  ghost.style.height = el3.offsetHeight + 'px';
  win.append(ghost);
  await moveTo(center(el3), 0, ghost);
  el3.classList.add('lifted');
  say('Drag to reorder');
  await sleep(150);
  const strip = segsEl.getBoundingClientRect(), w0 = win.getBoundingClientRect();
  await moveTo({ x: (strip.left - w0.left) / scale + ghost.offsetWidth / 2, y: center(el3).y }, 900, ghost); // drop over Clip 1
  cursor.classList.remove('down');
  ghost.remove();
  el3.classList.remove('lifted');
  move(c3.id, c1.id);
  await sleep(1000);

  // Open the saved clip from the sidebar, trim its end off.
  await moveTo(center(clipTake.row), 800);
  await click();
  say('Open the saved clip');
  showTake(clipTake);
  await sleep(1000);
  key(['Space'], 'Play', $('#playBtn'));
  playing = true;
  await until(() => t >= 2.4);
  key(['⌘', 'B'], 'Cut at playhead', $('#cutBtn'));
  cut();
  await until(() => t >= 3.1);
  key(['Space'], 'Pause', $('#playBtn'));
  playing = false;
  selectUnderPlayhead();
  await sleep(800);
  key(['⌫'], 'Delete segment', $('#delBtn'));
  del();
  await sleep(1200);

  // Save.
  await moveTo({ x: win.offsetWidth * 0.62, y: win.offsetHeight * 0.4 }, 600);
  cursor.classList.add('hidden');
  key(['⌘', 'S'], 'Save “Beach Trip Clip 2 edit.mov”');
  await exportAs('Beach Trip Clip 2 edit', clipTake.src, total());
  await sleep(2400);

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
  showTake(addTake('Beach Trip', 0, 12));
  t = 3; cut(); t = 7; cut();
  const [c1, c2, c3] = segs;
  addTake('Beach Trip Clip 2', 3, 4);
  addTake('Beach Trip Clip 2 edit', 3, 2.4);
  move(c3.id, c1.id);
  t = 1.2;
  cursor.classList.add('hidden');
  hud.innerHTML = '<span>Cut, delete, reorder, save. That’s it.</span>';
  render();
} else {
  requestAnimationFrame(tick);
  (async () => { for (;;) await run(); })();
}
