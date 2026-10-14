// Compiles every lens in a real WebGL context.
//
// A shader that does not compile is a black viewfinder on someone's phone, and
// GLSL has no type checker short of an actual driver — so this runs the whole
// catalogue through headless Chromium's WebGL implementation. It is the web
// app's equivalent of the native build's "every lens preserves the frame" test.
//
//   node scripts/test_shaders.mjs
//
// Needs playwright. In CI:  npx playwright install --with-deps chromium

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const ROOT = join(resolve(dirname(fileURLToPath(import.meta.url)), '..'), 'web');
const PORT = Number(process.env.SHADER_TEST_PORT ?? 8099);
const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
  '.png': 'image/png', '.webmanifest': 'application/manifest+json'
};

// createRequire rather than a bare import so a globally installed playwright
// (NODE_PATH) works as well as a local devDependency.
const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  console.error('playwright is not installed — skipping shader compilation test');
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

const browser = await chromium.launch({
  args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--no-sandbox']
});
const page = await browser.newPage();
const pageErrors = [];
page.on('pageerror', (error) => pageErrors.push(String(error)));

await page.goto(`http://localhost:${PORT}/index.html`, { waitUntil: 'domcontentloaded' });

const report = await page.evaluate(async () => {
  const { FILTERS, PRELUDE } = await import('./js/filters.js');
  const canvas = document.createElement('canvas');
  canvas.width = 64;
  canvas.height = 64;
  const gl = canvas.getContext('webgl');
  if (!gl) return { fatal: 'no WebGL context in this browser' };

  const VERTEX = `
    attribute vec2 a_pos; varying vec2 v_uv;
    uniform vec2 u_crop; uniform float u_zoom; uniform float u_mirror;
    void main() {
      vec2 s = a_pos * 0.5 + 0.5;
      vec2 d = vec2(s.x, 1.0 - s.y);
      if (u_mirror > 0.5) d.x = 1.0 - d.x;
      v_uv = (d - 0.5) * u_crop / u_zoom + 0.5;
      gl_Position = vec4(a_pos, 0.0, 1.0);
    }`;

  const results = [];
  for (const filter of FILTERS) {
    const fragment = `${PRELUDE}\n${filter.body}\nvoid main() { gl_FragColor = vec4(snappy(v_uv), 1.0); }`;

    const vs = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(vs, VERTEX);
    gl.compileShader(vs);

    const fs = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(fs, fragment);
    gl.compileShader(fs);

    const compiled = gl.getShaderParameter(fs, gl.COMPILE_STATUS);
    let linked = false;
    let log = compiled ? '' : gl.getShaderInfoLog(fs);

    if (compiled) {
      const program = gl.createProgram();
      gl.attachShader(program, vs);
      gl.attachShader(program, fs);
      gl.linkProgram(program);
      linked = gl.getProgramParameter(program, gl.LINK_STATUS);
      if (!linked) log = gl.getProgramInfoLog(program);
      gl.deleteProgram(program);
    }
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    results.push({ id: filter.id, compiled, linked, log: (log || '').trim() });
  }
  return { results };
});

await browser.close();
server.close();

if (report.fatal) {
  console.error(`FATAL: ${report.fatal}`);
  process.exit(1);
}

const failures = report.results.filter((r) => !r.compiled || !r.linked);
for (const failure of failures) {
  console.error(`FAIL ${failure.id}\n  ${failure.log.split('\n').join('\n  ')}\n`);
}
if (pageErrors.length) {
  console.error('page errors:');
  for (const error of pageErrors) console.error(`  ${error}`);
}

console.log(`${report.results.length - failures.length}/${report.results.length} lens shaders compiled and linked`);
process.exit(failures.length || pageErrors.length ? 1 : 0);
