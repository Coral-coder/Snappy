# The web app

## Why it exists

The native build is better in almost every technical way, and you cannot install
it without a $99/yr Apple Developer account, a registered device UDID and a
signing certificate. A web app added to the home screen has none of those
requirements and still gets a full-screen camera with its own icon. For a
filter camera that is a good trade.

## The frame path

```
getUserMedia ──▶ <video> ──▶ WebGL (lens shader) ──▶ 2D canvas ──┬──▶ screen
                     │                                           ├──▶ MediaRecorder
                     └──▶ MediaPipe landmarks ──▶ 2D overlay ────┴──▶ toBlob (photo)
```

Same rule as the native app: **the frame is filtered once, and that one frame is
what you see, what gets recorded and what gets saved.** The visible canvas is the
single source of truth — `captureStream()` records it and `toBlob()` photographs
it — so a lens cannot look one way in the viewfinder and another in the file.

The one deliberate exception is resolution. Preview renders at screen size
(capped at 2× device pixel ratio) because that is all you can see and it keeps
the frame rate up. The shutter re-runs the *identical* pipeline into a detached
canvas at the camera's native resolution, so photos are limited by the sensor,
not the display. `Renderer.captureFrame()` swaps the output canvas underneath
the draw call to do this without the viewfinder flickering through a resize.

## Lenses

### Soften and Younger

These two deserve a note: they are what a filter camera gets judged on, and
their failure is silent — a mistuned one compiles, runs, and looks exactly like
None.

The base is a cheap bilateral blur: three rings of samples, each weighted by
how close it is in colour to the centre pixel, so flat areas average out while
eyes, lashes, lips and the face's outline keep their contrast. The colour sigma
is deliberately loose; tighten it and the filter protects the very grain it
exists to remove.

What makes them read as *younger* rather than merely blurred is that the fine
detail is treated asymmetrically. Lines, pores, crow's feet and under-eye
shadow all sit **darker** than the skin around them, while highlights are what
make skin look fresh. So the frame is split into structure and detail, and the
dark half of the detail is crushed (down to 6% for Soften, 2% for Younger)
while most of the light half is kept. Blurring both halves equally is what
produces the plastic-mask look.

Two more passes finish it: chroma is taken from the blurred frame and luma from
the detail that was kept, so blotches and redness even out without softening
any structure (red excess over green is pulled down further, which is what
takes the heat out of a complexion); and the darker midtones get a lift, so
hollows and the shadow side of a line fade while highlights stay put. Younger
adds a little sheen in the highlights, a stronger shadow lift, and more
aggressive colour evening.

`scripts/test_shaders.mjs` measures all of this rather than trusting it. It
renders two cards — one of heavy grain with a hard vertical edge, one of skin
tone with thin shallow lines and one thick dark lash — and asserts that texture
and fine lines drop while the edge and the lash survive. Current numbers:

| Lens | Texture removed | Fine lines removed | Edge kept | Lash kept |
| --- | --- | --- | --- | --- |
| Soften | 65% | 63% | 99% | 97% |
| Younger | 72% | 74% | 99% | 93% |
| Glow | 41% | 54% | 101% | 62% |

The first cut of Soften scored 29% on texture, because of exactly the
sigma mistake described above. It compiled and it shipped nothing.

`filters.js` is the catalogue: each lens is a GLSL function body,
`vec3 snappy(vec2 uv)`, that gets a shared prelude prepended (sampling helpers,
luma, a Sobel operator, an aspect-corrected `warp()` used by the distortions).
Shaders compile lazily — the first time you swipe onto a lens — and are cached
per lens for the session.

Uniforms the prelude exposes: the frame texture, output resolution, elapsed
time, aspect ratio, and the current face (eye positions, centre, radius). Lenses
that set `faces: true` are hidden until the tracker is available.

Geometry lives in the vertex shader: mirroring for the front camera, digital
zoom, and the aspect-fill crop. That keeps `v_uv` in the video's own texture
space, which means MediaPipe's normalized landmarks can be fed straight into the
shader with no conversion. Overlay art needs the opposite direction, so
`Renderer.mapToScreen()` inverts the same transform.

## Face tracking

iOS Safari has no Vision framework and no `FaceDetector`, so face lenses use
MediaPipe's face landmarker. It is several megabytes, which is why it is:

- **lazy** — fetched the first time you select a face lens, never at startup;
- **cached** — the service worker keeps the wasm and model, so it is a one-time
  download;
- **optional** — if it fails to load, those seven lenses hide themselves and the
  rest are unaffected.

Detection runs on every other frame; the previous result is reused in between.
At 30fps that is invisible and roughly halves the cost.

## Storage

Captures go to IndexedDB (`store.js`) as blobs with a small JPEG thumbnail
generated at capture time, so the gallery grid never decodes full-resolution
video frames. Nothing is uploaded; there is no server. Reaching the system photo
library is a share-sheet action the user takes per shot.

Be aware that iOS can evict site data for a web app that goes unused for a long
time. That is a genuine difference from a native app's container, and the reason
the gallery pushes share and download rather than treating itself as permanent
storage.

## Hosting

### Turning Pages on (once)

A workflow token cannot create a Pages site: `actions/configure-pages` with
`enablement: true` returns *Resource not accessible by integration* on a
repository that has never had Pages enabled. Someone with admin access has to
do it once, in **Settings → Pages → Source**:

- **Deploy from a branch → `gh-pages` → `/ (root)`** — served by the branch the
  deploy workflow force-pushes.
- **GitHub Actions** — served by the Pages deployment the same workflow also
  attempts.

The workflow publishes both ways on every run, so either setting works and
neither has to be matched to the workflow. Whichever one is not configured
fails harmlessly inside the job.

Diagnosing it from outside: when Pages is enabled with a branch source, GitHub
registers its own `pages-build-deployment` workflow in the Actions tab. If the
only workflows listed are this repository's own, Pages has never been turned on.

### What gets served

GitHub Pages serves `web/` verbatim — there is no build step and no bundler, so
what is in the repository is what runs. Every path is relative because project
Pages sites live under `/<repo>/`.

The deploy workflow rewrites the service worker's cache name to the commit SHA.
Without that, a returning phone would keep serving the previous build out of the
cache forever.

`scripts/check_web.mjs` runs in CI and catches the failure mode that an
unbundled app is most prone to: a path that does not exist. It verifies every
service-worker precache entry, every manifest icon, every relative `src`/`href`
in the markup and every relative import, plus the iOS-specific meta tags and the
coherence of the lens catalogue.

## iOS specifics worth knowing

- `apple-mobile-web-app-capable` and `apple-mobile-web-app-status-bar-style` are
  what make the home-screen launch full screen with a dark status bar.
  `viewport-fit=cover` plus `env(safe-area-inset-*)` keep the controls clear of
  the notch and the home indicator.
- A home-screen web app is a separate storage and permission context from
  Safari: camera permission is asked again on first launch, and the roll does
  not carry over from the browser tab.
- Camera access requires a secure context. GitHub Pages is HTTPS, so this is
  only a problem when testing over plain `http://` on a LAN address — use
  `localhost` or a tunnel.
