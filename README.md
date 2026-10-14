# Snappy

A camera app for filters. That is the whole product.

No feed, no friends list, no streaks, no account, no ads, no analytics. You open
it, you get a viewfinder with a filter carousel, you take a photo or hold for
video, and it lands in your own roll. Sharing is the system share sheet — so
Instagram, Messages, AirDrop, Save Image, whatever the OS offers — and only when
you tap Share.

There are two builds in this repository.

| | Web app | Native iOS app |
| --- | --- | --- |
| Install | Open the link, Add to Home Screen | Signed `.ipa`, ad hoc over the air |
| Needs an Apple Developer account | No | Yes, $99/yr |
| Filters | 30 WebGL lenses | ~60 Core Image lenses + face lenses |
| Where it runs | Any modern phone or desktop | iPhone, iOS 17+ |
| Source | [`web/`](web) | [`Snappy/`](Snappy) |

**The web app is the one you can have right now.** Apple gates native installs
behind a paid account and device registration; a home-screen web app needs none
of it.

## Install the web app

On the iPhone, open the site in **Safari**:

```
https://coral-coder.github.io/Snappy/
```

> **First time only:** GitHub Pages has to be switched on by hand — a workflow
> token is not permitted to create a Pages site. In the repository:
> **Settings → Pages → Source → "Deploy from a branch" → `gh-pages` → `/ (root)`
> → Save.** The branch is already built and pushed by CI; the switch just tells
> GitHub to serve it. "GitHub Actions" works as a source too — the deploy
> workflow publishes both ways.

Tap the Share button, then **Add to Home Screen**. It then launches full screen
with its own icon, no browser chrome, and works with no connection.

The first launch asks for camera access. Everything after that is local: frames
are filtered on the GPU in your browser, captures go into on-device storage, and
there is no server in this app to send anything to.

## What the web app does

- **30 lenses**, compiled as WebGL fragment shaders and swiped through like a
  carousel: Noir, Thermal, X-Ray, Comic, Crystal, Hex, Halftone, Kaleido, Twirl,
  Bulge, Glitch, Duotone, Chrome and the rest.
- **7 face lenses** — Big Eyes, Alien, Squish, Shades, Puppy, Royalty, Smitten —
  tracked with MediaPipe face landmarks.
- **Photos at full camera resolution**, not screen resolution: the shutter
  re-renders the identical pipeline at the sensor's size.
- **Hold-to-record video** with audio, where the browser supports it.
- **An on-device roll** in IndexedDB, with share, download and delete.
- **Pinch to zoom**, swipe to change lens, tap for a photo.
- **Offline**: a service worker precaches the whole app shell.

## Honest limits of the web build

- **Video recording depends on the browser.** Recording a canvas needs
  `MediaRecorder` plus `captureStream`; older iOS versions have one or neither.
  Snappy feature-detects it and hides the hold-to-record hint when it is
  missing. Photos always work.
- **Face lenses download a tracking model the first time you pick one** (a few MB
  from a CDN). After that the service worker keeps it offline. With no
  connection on first use, those lenses hide themselves and the other 23 carry
  on.
- **Saving to the camera roll goes through the share sheet** — the web has no
  direct write to Photos. Share → Save Image.
- **iOS can clear site data** for a web app left unused for a long stretch.
  Anything you want to keep, share or download out of Snappy.
- **No sensor-level control.** Torch, manual focus and true optical zoom are not
  exposed to web pages on iOS; zoom here is digital, done in the shader.

## The native app

Still here, still builds, and gives you the things the web cannot: Core Image's
whole system filter library enumerated at runtime, Vision face tracking, and
`AVAssetWriter` recording. It needs a paid Apple Developer account to reach a
phone.

```bash
make bootstrap      # XcodeGen + generate Snappy.xcodeproj
make open           # Xcode
scripts/setup_signing.sh   # one command for certificate, profile, CI secrets
```

Then bump `VERSION` on `main` and push: CI builds a signed ad hoc `.ipa`,
attaches it to a Release, and
[`/install/`](https://coral-coder.github.io/Snappy/install/) installs it over the
air. Details in [docs/AD_HOC_DISTRIBUTION.md](docs/AD_HOC_DISTRIBUTION.md).

## Layout

```
web/                 the web app — no build step, the browser loads the modules
  js/renderer.js     WebGL pipeline: video → lens shader → canvas
  js/filters.js      the lens catalogue, as shader source
  js/faces.js        MediaPipe landmarks, loaded on demand
  js/overlays.js     Canvas 2D art for the face lenses
  sw.js              offline shell
Snappy/              the native iOS app (SwiftUI + AVFoundation + Core Image)
scripts/             icon generation, web checks, iOS signing and packaging
docs/                architecture, web app notes, ad hoc distribution, Camera Kit
```

Design notes: [docs/WEB_APP.md](docs/WEB_APP.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Deliberate limits

- Portrait only. A filter app that fights you about rotation is not a better app.
- Videos are capped at 60 seconds.
- Photos match the viewfinder exactly, which is the point: both builds filter
  each frame once and send that same frame to the screen, the recorder and the
  encoder, so the preview can never lie about the result.
