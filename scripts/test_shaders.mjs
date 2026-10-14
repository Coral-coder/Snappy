// Compiles every lens in a real WebGL context, then checks that the smoothing
// lenses actually smooth.
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

// --- behaviour: a beauty filter that does nothing also compiles ------------
//
// Soften and Younger are the lenses this app gets judged on, and their failure
// mode is silent: tune the colour sigma too tight and the filter protects the
// very detail it exists to remove, leaving something indistinguishable from
// None on a phone. So render two test cards and measure the actual claims —
// skin texture and fine lines go, real edges stay.
const behaviour = await page.evaluate(async () => {
  const { FILTERS, PRELUDE } = await import('./js/filters.js');
  const N = 720;
  const SKIN = [226, 182, 152];

  let seed = 1;
  const random = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;

  // Card one: flat halves with heavy grain and one hard vertical edge.
  const grainCard = document.createElement('canvas');
  grainCard.width = grainCard.height = N;
  {
    const ctx = grainCard.getContext('2d');
    const image = ctx.createImageData(N, N);
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const base = x < N / 2 ? 70 : 190;
        const value = Math.max(0, Math.min(255, base + (random() - 0.5) * 60));
        const i = (y * N + x) * 4;
        image.data[i] = image.data[i + 1] = image.data[i + 2] = value;
        image.data[i + 3] = 255;
      }
    }
    ctx.putImageData(image, 0, 0);
  }

  // Card two: skin tone, faint grain, thin dark lines standing in for fine
  // lines, and one thick dark line standing in for a lash or a brow.
  const LINE_ROWS = [120, 200, 280, 360, 440, 520];
  const LASH_ROW = 620;
  const lineCard = document.createElement('canvas');
  lineCard.width = lineCard.height = N;
  {
    const ctx = lineCard.getContext('2d');
    const image = ctx.createImageData(N, N);
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const noise = (random() - 0.5) * 16;
        const i = (y * N + x) * 4;
        image.data[i] = SKIN[0] + noise;
        image.data[i + 1] = SKIN[1] + noise;
        image.data[i + 2] = SKIN[2] + noise;
        image.data[i + 3] = 255;
      }
    }
    // Fine lines: two pixels tall, shallow. A lash: seven pixels, deep.
    const paint = (row, thickness, drop) => {
      for (let y = row; y < row + thickness; y++) {
        for (let x = 60; x < N - 60; x++) {
          const i = (y * N + x) * 4;
          image.data[i] -= drop;
          image.data[i + 1] -= drop * 0.95;
          image.data[i + 2] -= drop * 0.9;
        }
      }
    };
    for (const row of LINE_ROWS) paint(row, 2, 30);
    paint(LASH_ROW, 7, 140);
    ctx.putImageData(image, 0, 0);
  }

  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = N;
  const gl = canvas.getContext('webgl', { preserveDrawingBuffer: true });
  if (!gl) return null;

  const VERTEX = `attribute vec2 a_pos; varying vec2 v_uv;
    uniform vec2 u_crop; uniform float u_zoom; uniform float u_mirror;
    void main() { vec2 s = a_pos * 0.5 + 0.5; vec2 d = vec2(s.x, 1.0 - s.y);
    if (u_mirror > 0.5) d.x = 1.0 - d.x;
    v_uv = (d - 0.5) * u_crop / u_zoom + 0.5; gl_Position = vec4(a_pos, 0.0, 1.0); }`;

  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);

  const render = (filter, card) => {
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, card);

    const fragment = `${PRELUDE}\n${filter.body}\nvoid main(){ gl_FragColor = vec4(snappy(v_uv), 1.0); }`;
    const vs = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(vs, VERTEX);
    gl.compileShader(vs);
    const fs = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(fs, fragment);
    gl.compileShader(fs);
    const program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.useProgram(program);

    const attribute = gl.getAttribLocation(program, 'a_pos');
    gl.enableVertexAttribArray(attribute);
    gl.vertexAttribPointer(attribute, 2, gl.FLOAT, false, 0, 0);
    const at = (name) => gl.getUniformLocation(program, name);
    gl.uniform1i(at('u_tex'), 0);
    gl.uniform2f(at('u_res'), N, N);
    gl.uniform1f(at('u_time'), 0);
    gl.uniform1f(at('u_aspect'), 1);
    gl.uniform1f(at('u_hasFace'), 0);
    gl.uniform2f(at('u_eyeL'), 0.4, 0.4);
    gl.uniform2f(at('u_eyeR'), 0.6, 0.4);
    gl.uniform2f(at('u_faceC'), 0.5, 0.5);
    gl.uniform1f(at('u_faceR'), 0.25);
    gl.uniform2f(at('u_crop'), 1, 1);
    gl.uniform1f(at('u_zoom'), 1);
    gl.uniform1f(at('u_mirror'), 0);
    gl.viewport(0, 0, N, N);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    const pixels = new Uint8Array(N * N * 4);
    gl.readPixels(0, 0, N, N, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    return pixels;
  };

  // readPixels gives rows bottom-up; convert a card row to a buffer row.
  const rowOf = (y) => N - 1 - y;
  const at = (pixels, x, y) => pixels[(rowOf(y) * N + x) * 4];

  const grain = (pixels) => {
    let sum = 0;
    let count = 0;
    for (let y = 100; y < N - 100; y += 2) {
      for (let x = 40; x < N / 2 - 60; x++) {
        sum += Math.abs(at(pixels, x, y) - at(pixels, x + 1, y));
        count++;
      }
    }
    return sum / count;
  };

  const edge = (pixels) => {
    let left = 0;
    let right = 0;
    let count = 0;
    for (let y = 100; y < N - 100; y += 2) {
      for (let x = 40; x < N / 2 - 60; x++) {
        left += at(pixels, x, y);
        right += at(pixels, x + N / 2 + 20, y);
        count++;
      }
    }
    return (right - left) / count;
  };

  // How far a dark line still sits below the skin a few pixels above it.
  const lineDepth = (pixels, row, thickness) => {
    let sum = 0;
    let count = 0;
    for (let x = 120; x < N - 120; x += 3) {
      const onLine = at(pixels, x, row + Math.floor(thickness / 2));
      const around = (at(pixels, x, row - 14) + at(pixels, x, row + thickness + 14)) / 2;
      sum += around - onLine;
      count++;
    }
    return sum / count;
  };

  const measure = {};
  for (const id of ['none', 'soften', 'younger', 'glow']) {
    const filter = FILTERS.find((f) => f.id === id);
    if (!filter) continue;
    const grainPixels = render(filter, grainCard);
    const linePixels = render(filter, lineCard);
    measure[id] = {
      grain: grain(grainPixels),
      edge: edge(grainPixels),
      wrinkle: LINE_ROWS.reduce((total, row) => total + lineDepth(linePixels, row, 2), 0) / LINE_ROWS.length,
      lash: lineDepth(linePixels, LASH_ROW, 7)
    };
  }
  return measure;
});

const behaviourProblems = [];
if (!behaviour) {
  behaviourProblems.push('could not measure the smoothing lenses');
} else {
  const base = behaviour.none;
  // [id, min texture removed, min fine lines removed, min edge kept, min lash kept]
  const bars = [
    ['soften', 0.5, 0.3, 0.9, 0.75],
    ['younger', 0.55, 0.5, 0.85, 0.65],
    ['glow', 0.25, 0.0, 0.9, 0.5]
  ];
  for (const [id, minGrain, minWrinkle, minEdge, minLash] of bars) {
    const result = behaviour[id];
    if (!result) continue;
    const smoothing = 1 - result.grain / base.grain;
    const lines = 1 - result.wrinkle / base.wrinkle;
    const retention = result.edge / base.edge;
    const lash = result.lash / base.lash;
    console.log(
      `${id}: ${(smoothing * 100).toFixed(0)}% less texture, ` +
      `${(lines * 100).toFixed(0)}% of fine lines gone, ` +
      `${(retention * 100).toFixed(0)}% edge contrast and ${(lash * 100).toFixed(0)}% lash contrast kept`
    );
    if (smoothing < minGrain) behaviourProblems.push(`${id} removes only ${(smoothing * 100).toFixed(0)}% of the texture (wanted ${minGrain * 100}%)`);
    if (lines < minWrinkle) behaviourProblems.push(`${id} removes only ${(lines * 100).toFixed(0)}% of the fine lines (wanted ${minWrinkle * 100}%)`);
    if (retention < minEdge) behaviourProblems.push(`${id} loses the hard edge: ${(retention * 100).toFixed(0)}% kept`);
    if (lash < minLash) behaviourProblems.push(`${id} blurs the lash away: ${(lash * 100).toFixed(0)}% kept`);
  }
}

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

for (const problem of behaviourProblems) console.error(`FAIL ${problem}`);

console.log(`${report.results.length - failures.length}/${report.results.length} lens shaders compiled and linked`);
process.exit(failures.length || behaviourProblems.length || pageErrors.length ? 1 : 0);
