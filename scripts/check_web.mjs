// Sanity checks for the web app, run in CI.
//
// There is no bundler here on purpose — the browser loads the ES modules
// directly — so the thing most likely to break a deploy is a path that does not
// exist: a module the service worker precaches but nobody ships, an icon the
// manifest promises, a script tag pointing at a renamed file. This catches that
// before it reaches a phone.

import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const web = join(root, 'web');
const problems = [];

function check(relativePath, why) {
  if (!existsSync(join(web, relativePath))) problems.push(`${why}: web/${relativePath} is missing`);
}

// --- every file the service worker precaches must exist -------------------
const sw = readFileSync(join(web, 'sw.js'), 'utf8');
const shellBlock = sw.match(/const SHELL_FILES = \[([\s\S]*?)\];/);
if (!shellBlock) {
  problems.push('sw.js: could not find SHELL_FILES');
} else {
  const files = [...shellBlock[1].matchAll(/'([^']+)'/g)].map((m) => m[1]).filter((f) => f !== './');
  for (const file of files) check(file, 'service worker precache');
  console.log(`service worker precaches ${files.length + 1} entries`);
}

// --- every icon the manifest promises must exist --------------------------
const manifest = JSON.parse(readFileSync(join(web, 'manifest.webmanifest'), 'utf8'));
for (const icon of manifest.icons) check(icon.src, 'manifest icon');
if (manifest.start_url !== './') problems.push('manifest: start_url must stay relative for project Pages');
if (manifest.display !== 'standalone') problems.push('manifest: display must be standalone for a home-screen app');
console.log(`manifest declares ${manifest.icons.length} icons`);

// --- the markup must not point at anything that moved ---------------------
const html = readFileSync(join(web, 'index.html'), 'utf8');
for (const [, href] of html.matchAll(/(?:href|src)="(?!https?:|data:|#)([^"]+)"/g)) check(href, 'index.html');

for (const meta of ['apple-mobile-web-app-capable', 'apple-mobile-web-app-status-bar-style', 'viewport-fit=cover']) {
  if (!html.includes(meta)) problems.push(`index.html: missing ${meta}, which iOS needs for a home-screen app`);
}
if (!html.includes('rel="apple-touch-icon"')) problems.push('index.html: missing apple-touch-icon; iOS would use a screenshot');

// --- modules must at least parse, and import real files -------------------
const modules = ['app', 'renderer', 'filters', 'overlays', 'camera', 'faces', 'store', 'recorder', 'share'];
for (const name of modules) {
  const path = join(web, 'js', `${name}.js`);
  if (!existsSync(path)) {
    problems.push(`js/${name}.js is missing`);
    continue;
  }
  const source = readFileSync(path, 'utf8');
  for (const [, spec] of source.matchAll(/from\s+'(\.\/[^']+)'/g)) {
    if (!existsSync(join(web, 'js', spec))) problems.push(`js/${name}.js imports ${spec}, which does not exist`);
  }
}

// --- the lens catalogue has to be coherent --------------------------------
const { FILTERS } = await import(new URL('../web/js/filters.js', import.meta.url));
const ids = FILTERS.map((f) => f.id);
if (new Set(ids).size !== ids.length) problems.push('filters.js: duplicate lens ids');
if (ids[0] !== 'none') problems.push('filters.js: the first lens should be the unfiltered one');
for (const filter of FILTERS) {
  if (!/vec3\s+snappy\s*\(\s*vec2\s+uv\s*\)/.test(filter.body)) {
    problems.push(`filters.js: ${filter.id} does not define vec3 snappy(vec2 uv)`);
  }
  const open = (filter.body.match(/\{/g) ?? []).length;
  const close = (filter.body.match(/\}/g) ?? []).length;
  if (open !== close) problems.push(`filters.js: ${filter.id} has unbalanced braces in its shader`);
  if (!filter.name || !filter.glyph) problems.push(`filters.js: ${filter.id} is missing a name or glyph`);
}
console.log(`lens catalogue: ${FILTERS.length} lenses, ${FILTERS.filter((f) => f.faces).length} of them face lenses`);

if (problems.length) {
  console.error(`\n${problems.length} problem(s):`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log('\nweb app checks passed');
