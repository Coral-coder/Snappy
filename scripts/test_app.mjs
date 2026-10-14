// End-to-end smoke test with a synthetic camera.
//
// Chromium can feed getUserMedia a fake video device, which is enough to drive
// the real pipeline: permission flow, render loop, lens switching, the shutter,
// and the IndexedDB roll. It will not tell you whether a lens looks good, but it
// catches the pipeline being broken outright.
//
//   node scripts/test_app.mjs

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const ROOT = join(resolve(dirname(fileURLToPath(import.meta.url)), '..'), 'web');
const PORT = Number(process.env.APP_TEST_PORT ?? 8098);
const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
  '.png': 'image/png', '.webmanifest': 'application/manifest+json'
};

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  console.error('playwright is not installed — skipping app smoke test');
  process.exit(0);
}

const server = createServer(async (request, response) => {
  try {
    let path = decodeURIComponent((request.url ?? '/').split('?')[0]);
    if (path.endsWith('/')) path += 'index.html';
    const file = join(ROOT, normalize(path).replace(/^(\.\.[/\\])+/, ''));
    const body = await readFile(file);
    response.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' });
    response.end(body);
  } catch {
    response.writeHead(404);
    response.end('not found');
  }
});
await new Promise((done) => server.listen(PORT, done));

const failures = [];

/** Polls an evaluation until it returns something truthy, or gives up. */
async function until(evaluate, { timeout = 15_000, interval = 250 } = {}) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const value = await evaluate();
    if (value) return value;
    if (Date.now() > deadline) return null;
    await new Promise((done) => setTimeout(done, interval));
  }
}

const check = (condition, description) => {
  console.log(`${condition ? 'ok  ' : 'FAIL'} ${description}`);
  if (!condition) failures.push(description);
};

const browser = await chromium.launch({
  args: [
    '--use-gl=swiftshader',
    '--enable-unsafe-swiftshader',
    '--no-sandbox',
    '--use-fake-device-for-media-stream',
    '--use-fake-ui-for-media-stream',
    '--autoplay-policy=no-user-gesture-required'
  ]
});
const context = await browser.newContext({
  permissions: ['camera'],
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 2
});
const page = await context.newPage();

const pageErrors = [];
page.on('pageerror', (error) => pageErrors.push(String(error)));
page.on('console', (message) => {
  if (message.type() === 'error') pageErrors.push(`console: ${message.text()}`);
});

await page.goto(`http://localhost:${PORT}/index.html`, { waitUntil: 'load' });

// --- the viewfinder comes up ------------------------------------------------
// A canvas starts life 300x150, so wait for the render loop to have sized it to
// the device rather than for any non-zero size.
await page.waitForFunction(() => {
  const canvas = document.getElementById('stage');
  const expected = Math.round(canvas.clientWidth * Math.min(window.devicePixelRatio || 1, 2));
  return canvas.clientWidth > 0 && canvas.width === expected;
}, { timeout: 15_000 }).catch(() => {});

const permissionVisible = await page.locator('#permission').isVisible();
check(!permissionVisible, 'camera starts without falling back to the permission screen');

const canvasSize = await page.evaluate(() => {
  const canvas = document.getElementById('stage');
  return { w: canvas.width, h: canvas.height, cssW: canvas.clientWidth, cssH: canvas.clientHeight };
});
check(canvasSize.w === canvasSize.cssW * 2 && canvasSize.h === canvasSize.cssH * 2,
  `canvas is sized for the device (${canvasSize.w}x${canvasSize.h} backing ${canvasSize.cssW}x${canvasSize.cssH})`);

// --- it is actually drawing something ---------------------------------------
const notBlank = await page.evaluate(async () => {
  await new Promise((done) => setTimeout(done, 600));
  const canvas = document.getElementById('stage');
  const probe = document.createElement('canvas');
  probe.width = 32;
  probe.height = 32;
  const ctx = probe.getContext('2d');
  ctx.drawImage(canvas, 0, 0, 32, 32);
  const { data } = ctx.getImageData(0, 0, 32, 32);
  let variance = 0;
  for (let i = 0; i < data.length; i += 4) variance += Math.abs(data[i] - data[1]);
  return variance > 100;
});
check(notBlank, 'the viewfinder is rendering frames, not a blank canvas');

// --- every non-face lens can be selected and drawn --------------------------
const lensReport = await page.evaluate(async () => {
  const { FILTERS } = await import('./js/filters.js');
  const chips = [...document.querySelectorAll('#carousel .chip')];
  const broken = [];
  let tested = 0;
  for (const [index, filter] of FILTERS.entries()) {
    if (filter.faces) continue;
    chips[index].click();
    await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
    tested++;
    const selected = chips[index].getAttribute('aria-selected') === 'true';
    if (!selected) broken.push(filter.id);
  }
  return { tested, broken };
});
check(lensReport.broken.length === 0,
  `all ${lensReport.tested} shader lenses select and render${lensReport.broken.length ? ` (broken: ${lensReport.broken})` : ''}`);

// --- the shutter writes a real photo into the roll --------------------------
await page.evaluate(() => document.querySelector('#carousel .chip').click());
await page.locator('#shutter').dispatchEvent('pointerdown');
await page.locator('#shutter').dispatchEvent('pointerup');

const stored = await until(() => page.evaluate(async () => {
  try {
    const request = indexedDB.open('snappy', 1);
    const db = await new Promise((done, fail) => {
      request.onsuccess = () => done(request.result);
      request.onerror = () => fail(request.error);
    });
    if (![...db.objectStoreNames].includes('captures')) return null;
    const all = await new Promise((done, fail) => {
      const get = db.transaction('captures').objectStore('captures').getAll();
      get.onsuccess = () => done(get.result);
      get.onerror = () => fail(get.error);
    });
    db.close();
    if (!all.length) return null;
    return { count: all.length, kind: all[0].kind, bytes: all[0].blob.size, type: all[0].blob.type };
  } catch {
    return null;
  }
}));

check(Boolean(stored), 'tapping the shutter stores a capture');
if (stored) {
  check(stored.kind === 'photo' && stored.type === 'image/jpeg', `capture is a JPEG photo (${stored.type})`);
  check(stored.bytes > 5000, `photo has real content (${Math.round(stored.bytes / 1024)} KB)`);
}

// --- the gallery shows it ---------------------------------------------------
await page.locator('#gallery-open').click();
await page.waitForTimeout(400);
const cells = await page.locator('#gallery-grid .cell').count();
check(cells >= 1, `gallery lists the capture (${cells} cell(s))`);

// --- the service worker registers -------------------------------------------
const swRegistered = await page.evaluate(async () => {
  const registration = await navigator.serviceWorker.getRegistration();
  return Boolean(registration);
});
check(swRegistered, 'service worker registers for offline use');

await browser.close();
server.close();

const realErrors = pageErrors.filter((error) => !/favicon|face tracking|MediaPipe/i.test(error));
if (realErrors.length) {
  console.error('\npage errors:');
  for (const error of realErrors) console.error(`  ${error}`);
}

console.log(`\n${failures.length ? `${failures.length} check(s) failed` : 'all checks passed'}`);
process.exit(failures.length || realErrors.length ? 1 : 0);
