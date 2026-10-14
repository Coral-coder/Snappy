// Offline support.
//
// The app shell is precached so Snappy opens from the home screen with no
// connection at all. MediaPipe's face-tracking model is cached at runtime the
// first time it is fetched, so face lenses keep working offline afterwards.

const VERSION = 'snappy-v1';
const SHELL = `${VERSION}-shell`;
const RUNTIME = `${VERSION}-runtime`;

const SHELL_FILES = [
  './',
  'index.html',
  'styles.css',
  'manifest.webmanifest',
  'js/app.js',
  'js/renderer.js',
  'js/filters.js',
  'js/overlays.js',
  'js/camera.js',
  'js/faces.js',
  'js/store.js',
  'js/recorder.js',
  'js/share.js',
  'icons/icon-180.png',
  'icons/icon-192.png',
  'icons/icon-512.png'
];

// Hosts the face tracker pulls from. Everything else is left alone.
const RUNTIME_HOSTS = ['cdn.jsdelivr.net', 'storage.googleapis.com'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL)
      .then((cache) => cache.addAll(SHELL_FILES))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key !== SHELL && key !== RUNTIME).map((key) => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  const sameOrigin = url.origin === self.location.origin;

  if (!sameOrigin && !RUNTIME_HOSTS.includes(url.hostname)) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) {
        // Refresh the shell quietly in the background so updates land next launch.
        if (sameOrigin) event.waitUntil(update(request));
        return cached;
      }
      return fetch(request)
        .then((response) => store(request, response))
        .catch(() => (request.mode === 'navigate' ? caches.match('index.html') : Response.error()));
    })
  );
});

function store(request, response) {
  if (!response || response.status !== 200 || response.type === 'error') return response;
  const bucket = new URL(request.url).origin === self.location.origin ? SHELL : RUNTIME;
  const copy = response.clone();
  caches.open(bucket).then((cache) => cache.put(request, copy));
  return response;
}

function update(request) {
  return fetch(request)
    .then((response) => store(request, response))
    .catch(() => undefined);
}
