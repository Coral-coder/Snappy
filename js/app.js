// Snappy — wiring.
//
// Owns the render loop, the gestures, and the three sheets. Everything else
// lives in its own module: camera.js, renderer.js, filters.js, faces.js,
// store.js, recorder.js, share.js.

import { FILTERS } from './filters.js';
import { Renderer } from './renderer.js';
import { Camera, cameraSupported, secureContextOK } from './camera.js';
import { FaceTracker } from './faces.js';
import { addCapture, allCaptures, deleteCapture, latestCapture, fileNameFor } from './store.js';
import { CanvasRecorder, recordingSupported, pickMimeType } from './recorder.js';
import { shareFile, download, shareSupported } from './share.js';

const VERSION = '1.0.0';
const MAX_CLIP_SECONDS = 60;
const LENS_KEY = 'snappy.lens';

const el = (id) => document.getElementById(id);
const stage = el('stage');

const video = document.createElement('video');
video.playsInline = true;
video.muted = true;
video.setAttribute('playsinline', '');
video.setAttribute('webkit-playsinline', '');

const camera = new Camera(video);
const tracker = new FaceTracker();
const renderer = new Renderer(stage);
const recorder = new CanvasRecorder(stage);

const state = {
  lensIndex: 0,
  running: false,
  faceLensesHidden: false,
  captures: [],
  viewing: null,
  objectUrls: new Set()
};

// -------------------------------------------------------------- utilities --

let toastTimer;
function toast(message, ms = 2200) {
  const node = el('toast');
  node.textContent = message;
  node.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { node.hidden = true; }, ms);
}

function objectUrl(blob) {
  const url = URL.createObjectURL(blob);
  state.objectUrls.add(url);
  return url;
}

function releaseUrls() {
  for (const url of state.objectUrls) URL.revokeObjectURL(url);
  state.objectUrls.clear();
}

const lens = () => FILTERS[state.lensIndex];

// ---------------------------------------------------------------- carousel --

function buildCarousel() {
  const carousel = el('carousel');
  carousel.innerHTML = '';
  FILTERS.forEach((filter, index) => {
    const chip = document.createElement('button');
    chip.className = 'chip';
    chip.dataset.id = filter.id;
    chip.setAttribute('role', 'tab');
    chip.setAttribute('aria-selected', String(index === state.lensIndex));
    chip.innerHTML = `<span class="glyph">${filter.glyph}</span><span class="label"></span>`;
    chip.querySelector('.label').textContent = filter.name;
    chip.addEventListener('click', () => selectLens(index));
    carousel.appendChild(chip);
  });
}

function syncCarousel() {
  const carousel = el('carousel');
  [...carousel.children].forEach((chip, index) => {
    chip.setAttribute('aria-selected', String(index === state.lensIndex));
    chip.hidden = state.faceLensesHidden && Boolean(FILTERS[index].faces);
  });
  const selected = carousel.children[state.lensIndex];
  selected?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
}

async function selectLens(index) {
  const filter = FILTERS[index];
  if (!filter) return;

  if (filter.faces && !tracker.available) {
    toast('Loading face tracking…', 4000);
    const ok = await tracker.load();
    if (!ok) {
      state.faceLensesHidden = true;
      syncCarousel();
      toast('Face lenses need a connection the first time. The rest work offline.', 4000);
      return;
    }
    toast('Face lenses ready');
  }

  if (!renderer.setFilter(filter)) {
    toast(`${filter.name} is not supported on this device`);
    return;
  }
  state.lensIndex = index;
  try { localStorage.setItem(LENS_KEY, filter.id); } catch { /* private mode */ }
  tracker.reset();
  syncCarousel();
}

function stepLens(direction) {
  const usable = FILTERS
    .map((filter, index) => ({ filter, index }))
    .filter(({ filter }) => !(state.faceLensesHidden && filter.faces));
  const position = usable.findIndex(({ index }) => index === state.lensIndex);
  const next = usable[Math.min(Math.max(position + direction, 0), usable.length - 1)];
  if (next && next.index !== state.lensIndex) selectLens(next.index);
}

// ------------------------------------------------------------- render loop --

function frame(now) {
  if (state.running) requestAnimationFrame(frame);
  if (video.readyState < 2) return;

  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const width = Math.round(stage.clientWidth * dpr);
  const height = Math.round(stage.clientHeight * dpr);
  if (!width || !height) return;

  renderer.mirror = camera.mirrored;
  renderer.faces = lens().faces ? tracker.detect(video, now) : [];
  renderer.draw(video, width, height);

  if (recorder.recording) {
    const seconds = recorder.seconds;
    el('rec-time').textContent = formatClock(seconds);
    if (seconds >= MAX_CLIP_SECONDS) stopRecording();
  }
}

function formatClock(seconds) {
  const whole = Math.floor(seconds);
  return `${String(Math.floor(whole / 60)).padStart(2, '0')}:${String(whole % 60).padStart(2, '0')}`;
}

// ----------------------------------------------------------------- capture --

function flash() {
  const node = document.createElement('div');
  node.className = 'flash fire';
  el('viewfinder').appendChild(node);
  setTimeout(() => node.remove(), 300);
}

function canvasToBlob(canvas, type = 'image/jpeg', quality = 0.92) {
  return new Promise((resolve) => canvas.toBlob(resolve, type, quality));
}

async function makeThumbnail(source) {
  const size = 320;
  const scale = Math.min(size / source.width, size / source.height, 1);
  const thumb = document.createElement('canvas');
  thumb.width = Math.round(source.width * scale);
  thumb.height = Math.round(source.height * scale);
  thumb.getContext('2d').drawImage(source, 0, 0, thumb.width, thumb.height);
  return canvasToBlob(thumb, 'image/jpeg', 0.7);
}

async function takePhoto() {
  if (video.readyState < 2) return;
  flash();

  // The photo keeps the shape of the viewfinder but is rendered at the native
  // resolution of the region the camera is actually showing, so it is limited by
  // the sensor rather than by the screen.
  const screenAspect = stage.clientWidth / stage.clientHeight;
  const videoAspect = video.videoWidth / video.videoHeight;
  const [width, height] = screenAspect < videoAspect
    ? [Math.round(video.videoHeight * screenAspect), video.videoHeight]
    : [video.videoWidth, Math.round(video.videoWidth / screenAspect)];
  const full = renderer.captureFrame(video, Math.max(width, 2), Math.max(height, 2));

  const [blob, thumbnail] = await Promise.all([
    canvasToBlob(full, 'image/jpeg', 0.92),
    makeThumbnail(full)
  ]);
  if (!blob) {
    toast('Could not save that shot');
    return;
  }
  const record = await addCapture({ blob, thumbnail, kind: 'photo', mime: 'image/jpeg' });
  state.captures.unshift(record);
  paintThumbButton(record);
}

async function startRecording() {
  if (recorder.recording) return;
  if (!recordingSupported(stage)) {
    toast('This browser cannot record video — photos still work');
    return;
  }
  const audio = await camera.audioTrack();
  try {
    recorder.start(audio);
  } catch {
    toast('Could not start recording');
    return;
  }
  el('shutter').classList.add('recording');
  el('rec-badge').hidden = false;
  el('rec-time').textContent = '00:00';
  if (navigator.vibrate) navigator.vibrate(12);
}

async function stopRecording() {
  if (!recorder.recording) return;
  const thumbnailSource = stage;
  const result = await recorder.stop();
  el('shutter').classList.remove('recording');
  el('rec-badge').hidden = true;
  camera.releaseAudio();

  if (!result) {
    toast('Nothing was recorded');
    return;
  }
  const thumbnail = await makeThumbnail(thumbnailSource);
  const record = await addCapture({
    blob: result.blob,
    thumbnail,
    kind: 'video',
    mime: result.mime
  });
  state.captures.unshift(record);
  paintThumbButton(record);
}

function paintThumbButton(record) {
  const button = el('gallery-open');
  if (!record) {
    button.style.backgroundImage = '';
    return;
  }
  button.style.backgroundImage = `url(${objectUrl(record.thumbnail ?? record.blob)})`;
}

// ---------------------------------------------------------------- gestures --

function wireGestures() {
  let startX = 0;
  let startY = 0;
  let pinchStart = 0;
  let zoomStart = 1;
  let swiping = false;

  const distance = (touches) =>
    Math.hypot(touches[0].clientX - touches[1].clientX, touches[0].clientY - touches[1].clientY);

  stage.addEventListener('touchstart', (event) => {
    if (event.touches.length === 2) {
      pinchStart = distance(event.touches);
      zoomStart = renderer.zoom;
      swiping = false;
    } else if (event.touches.length === 1) {
      startX = event.touches[0].clientX;
      startY = event.touches[0].clientY;
      swiping = true;
    }
  }, { passive: true });

  stage.addEventListener('touchmove', (event) => {
    if (event.touches.length === 2 && pinchStart) {
      const ratio = distance(event.touches) / pinchStart;
      renderer.zoom = Math.min(Math.max(zoomStart * ratio, 1), 6);
    }
  }, { passive: true });

  stage.addEventListener('touchend', (event) => {
    if (!swiping || event.changedTouches.length !== 1) {
      pinchStart = 0;
      return;
    }
    const dx = event.changedTouches[0].clientX - startX;
    const dy = event.changedTouches[0].clientY - startY;
    if (Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy)) stepLens(dx < 0 ? 1 : -1);
    swiping = false;
  }, { passive: true });

  // Desktop and trackpad, so the thing is testable without a phone.
  stage.addEventListener('wheel', (event) => {
    if (Math.abs(event.deltaX) > Math.abs(event.deltaY) && Math.abs(event.deltaX) > 30) {
      stepLens(event.deltaX > 0 ? 1 : -1);
    }
  }, { passive: true });

  window.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowRight') stepLens(1);
    if (event.key === 'ArrowLeft') stepLens(-1);
    if (event.key === ' ') { event.preventDefault(); takePhoto(); }
  });

  // Shutter: tap for a photo, hold for video.
  const shutter = el('shutter');
  let holdTimer = null;
  let held = false;

  const press = (event) => {
    event.preventDefault();
    held = false;
    holdTimer = setTimeout(() => { held = true; startRecording(); }, 350);
  };
  const release = (event) => {
    event.preventDefault();
    clearTimeout(holdTimer);
    if (held || recorder.recording) stopRecording();
    else takePhoto();
    held = false;
  };

  shutter.addEventListener('pointerdown', press);
  shutter.addEventListener('pointerup', release);
  shutter.addEventListener('pointercancel', () => {
    clearTimeout(holdTimer);
    if (recorder.recording) stopRecording();
  });

  // Stop iOS from zooming the page when fingers land on the chrome.
  document.addEventListener('gesturestart', (event) => event.preventDefault());
  document.addEventListener('dblclick', (event) => event.preventDefault());
}

// ------------------------------------------------------------------ sheets --

function openSheet(id) {
  el(id).hidden = false;
}

function closeSheet(id) {
  el(id).hidden = true;
}

async function openGallery() {
  state.captures = await allCaptures();
  const grid = el('gallery-grid');
  grid.innerHTML = '';
  el('gallery-empty').hidden = state.captures.length > 0;

  for (const record of state.captures) {
    const cell = document.createElement('button');
    cell.className = 'cell';
    cell.style.backgroundImage = `url(${objectUrl(record.thumbnail ?? record.blob)})`;
    cell.setAttribute('aria-label', record.kind === 'video' ? 'Video' : 'Photo');
    if (record.kind === 'video') {
      const play = document.createElement('span');
      play.className = 'play';
      play.textContent = '▶';
      cell.appendChild(play);
    }
    cell.addEventListener('click', () => openViewer(record));
    grid.appendChild(cell);
  }
  openSheet('gallery');
}

function openViewer(record) {
  state.viewing = record;
  const host = el('viewer-stage');
  host.innerHTML = '';
  const url = objectUrl(record.blob);

  if (record.kind === 'video') {
    const player = document.createElement('video');
    player.src = url;
    player.controls = true;
    player.playsInline = true;
    player.autoplay = true;
    player.loop = true;
    host.appendChild(player);
  } else {
    const image = document.createElement('img');
    image.src = url;
    image.alt = 'Capture';
    host.appendChild(image);
  }
  openSheet('viewer');
}

function closeViewer() {
  el('viewer-stage').innerHTML = '';
  state.viewing = null;
  closeSheet('viewer');
}

function describeCapabilities() {
  const list = el('capability-list');
  const mime = pickMimeType();
  const rows = [
    ['Live filters', 'WebGL, every frame'],
    ['Photos', `Up to ${video.videoWidth || '—'}px wide`],
    ['Video', recordingSupported(stage) ? `Yes (${mime?.split(';')[0]})` : 'Not supported by this browser'],
    ['Share sheet', shareSupported() ? 'Yes' : 'Downloads instead'],
    ['Face lenses', tracker.state === 'ready' ? 'Ready' : tracker.state === 'unavailable' ? 'Unavailable' : 'Loads when first used'],
    ['Works offline', navigator.serviceWorker ? 'Yes, after first load' : 'No service worker']
  ];
  list.innerHTML = '';
  for (const [label, value] of rows) {
    const item = document.createElement('li');
    item.innerHTML = `<strong>${label}</strong> — <span class="muted">${value}</span>`;
    list.appendChild(item);
  }

  const summary = el('lens-summary');
  summary.innerHTML = '';
  const plain = FILTERS.filter((f) => !f.faces).length;
  const faces = FILTERS.filter((f) => f.faces).length;
  for (const [label, value] of [['Shader lenses', plain], ['Face lenses', faces]]) {
    const item = document.createElement('li');
    item.innerHTML = `<strong>${label}</strong> — <span class="muted">${value}</span>`;
    summary.appendChild(item);
  }
  el('face-status').textContent = tracker.state === 'unavailable'
    ? 'Face tracking could not load on this device, so those lenses are hidden.'
    : 'Face lenses download a tracking model the first time you pick one, then work offline.';
  el('version-line').textContent = `Snappy ${VERSION}`;
}

function wireChrome() {
  el('flip').addEventListener('click', async () => {
    try {
      await camera.flip();
      tracker.reset();
    } catch {
      toast('No second camera on this device');
    }
  });

  el('gallery-open').addEventListener('click', openGallery);
  el('gallery-close').addEventListener('click', () => closeSheet('gallery'));
  el('settings-open').addEventListener('click', () => { describeCapabilities(); openSheet('settings'); });
  el('settings-close').addEventListener('click', () => closeSheet('settings'));
  el('viewer-close').addEventListener('click', closeViewer);

  el('viewer-share').addEventListener('click', async () => {
    if (!state.viewing) return;
    const result = await shareFile(state.viewing.blob, fileNameFor(state.viewing));
    if (result === 'downloaded') toast('Saved to your downloads');
  });

  el('viewer-save').addEventListener('click', () => {
    if (!state.viewing) return;
    download(state.viewing.blob, fileNameFor(state.viewing));
    toast('Saved to your downloads');
  });

  el('viewer-delete').addEventListener('click', async () => {
    if (!state.viewing) return;
    await deleteCapture(state.viewing.id);
    closeViewer();
    await openGallery();
    paintThumbButton(await latestCapture());
  });

  el('permission-retry').addEventListener('click', boot);

  // Pause the camera while the app is in the background; iOS suspends the
  // stream anyway and holding it keeps the green dot on.
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      state.running = false;
      if (!recorder.recording) camera.stop();
    } else if (!camera.stream) {
      boot();
    }
  });

  window.addEventListener('pagehide', () => {
    releaseUrls();
    camera.stopAll();
  });
}

// -------------------------------------------------------------------- boot --

function showPermission(message) {
  el('permission-detail').textContent = message;
  el('permission').hidden = false;
}

async function boot() {
  el('permission').hidden = true;

  if (!cameraSupported()) {
    showPermission('This browser has no camera API. On iOS, open Snappy in Safari.');
    return;
  }
  if (!secureContextOK()) {
    showPermission('A camera needs a secure connection. Open the https:// address.');
    return;
  }

  try {
    await camera.start();
  } catch (error) {
    const denied = error?.name === 'NotAllowedError' || error?.name === 'SecurityError';
    showPermission(denied
      ? 'Camera access was refused. Allow it for this site in Settings, then tap below.'
      : 'No camera could be opened on this device.');
    return;
  }

  state.running = true;
  requestAnimationFrame(frame);
  el('hold-hint').hidden = !recordingSupported(stage);
  paintThumbButton(await latestCapture());
}

function restoreLens() {
  let saved = null;
  try { saved = localStorage.getItem(LENS_KEY); } catch { /* private mode */ }
  const index = FILTERS.findIndex((filter) => filter.id === saved);
  // Face lenses are not restored on launch: they would pull a model download
  // before the viewfinder is even up.
  state.lensIndex = index > 0 && !FILTERS[index].faces ? index : 0;
  renderer.setFilter(FILTERS[state.lensIndex]);
}

function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch(() => { /* offline support is optional */ });
  });
}

restoreLens();
buildCarousel();
syncCarousel();
wireGestures();
wireChrome();
registerServiceWorker();
boot();
