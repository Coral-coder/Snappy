# Snappy

A camera app for filters. That is the whole product.

No feed, no friends list, no streaks, no account, no ads, no analytics, no
network calls. You open it, you get a viewfinder with a filter carousel, you take
a photo or hold for video, and it lands in the app's own roll. Sharing is the
system share sheet — so Instagram, Messages, AirDrop, whatever the OS offers —
and it only happens when you tap Share.

## Where the filters come from

| Source | Status | Notes |
| --- | --- | --- |
| **iOS Core Image library** | shipped | Enumerated from the OS at runtime, not hard-coded. Roughly 40–60 usable looks: Noir, Comic, Thermal, X-Ray, Crystallize, Pixellate, Kaleidoscope, halftones, distortions… |
| **Snappy face lenses** | shipped | Vision face tracking plus Core Graphics art: Shades, Puppy, Royalty, Smitten, Big Eyes, Alien, Squish. |
| **Snap Camera Kit** (real Snapchat Lenses) | adapter included, off by default | Needs a Snap developer account, an API token and lens groups. See [docs/CAMERA_KIT.md](docs/CAMERA_KIT.md). |

Worth saying plainly: **there is no public API that hands an app the Snapchat
public lens catalogue.** Snap's Camera Kit is the only supported route to real
Snap AR Lenses, it is commercial, and what you get is the lens *groups* you
configure — not a mirror of Snapchat. Extracting lens bundles out of the
Snapchat app would break Snap's terms, so this app does not do that. The
built-in providers are what make it useful on day one; Camera Kit is the seam
for when you have credentials.

## Getting it running

Needs a Mac with Xcode 16 and an iPhone (the camera does not exist in the
simulator, though the app builds and the tests run there).

```bash
make bootstrap   # installs XcodeGen, generates Snappy.xcodeproj
make open        # opens it in Xcode
```

Before building to a device, create `Config/Local.xcconfig` (gitignored):

```
SNAPPY_BUNDLE_ID = com.yourname.snappy
SNAPPY_TEAM_ID = ABCDE12345
```

`make test` runs the unit tests on a simulator.

## Getting it onto a phone, without TestFlight

Once, to set up signing (Apple only lets your own account create a signing
certificate, so this part cannot be automated away entirely — but it is one
command and three clicks):

```bash
scripts/setup_signing.sh
```

It generates the key, walks you through the three Apple pages, builds the `.p12`
and uploads all three GitHub secrets for you.

After that, bump `VERSION` on `main` and push. GitHub Actions builds a signed ad hoc `.ipa`,
publishes an over-the-air install page, and attaches the build to a Release
(tagging it for you):

```bash
echo 0.1.1 > VERSION && git commit -am "0.1.1" && git push
```

Open the install page in Safari on the iPhone and tap Install. The device's UDID
has to be in the ad hoc provisioning profile first — Apple's rule, not ours.
Full setup, the three secrets it needs, and the alternatives (own host,
Enterprise programme, sideloading) are in
[docs/AD_HOC_DISTRIBUTION.md](docs/AD_HOC_DISTRIBUTION.md).

## Layout

```
Snappy/
  App/         entry point and routing
  Camera/      AVCaptureSession, frame pipeline, recorder, view model
  Filters/     lens protocol, Core Image provider, face lenses, Camera Kit seam
  Rendering/   Metal-backed viewfinder and the shared CIContext
  Capture/     on-device roll, thumbnails, save-to-Photos
  Sharing/     the share sheet, which is all the "social" there is
  UI/          camera, carousel, gallery, settings
scripts/       signing, export options, OTA manifest, install page, app icon
docs/          architecture, ad hoc distribution, Camera Kit
```

Design notes and the reasoning behind the frame path are in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Deliberate limits

- Portrait only. A filter app that fights you about rotation is not a better app.
- Videos are capped at 60 seconds.
- Photos are grabbed from the live filtered frame, so they are at video
  resolution (1080p) rather than the sensor's full still resolution. That is the
  price of the preview being exactly truthful; it is a defensible trade for a
  filter app and a bad one for a photography app.
