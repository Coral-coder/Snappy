# Real Snapchat Lenses: Snap Camera Kit

## The short version

There is exactly one supported way to run actual Snapchat Lenses outside
Snapchat: **Snap's Camera Kit SDK**. There is no public API that hands you the
Snapchat public lens catalogue, and pulling lens bundles out of the Snapchat app
is both technically brittle and a violation of Snap's terms — Snappy does not do
it and will not.

So the filter catalogue in this app comes from two places today:

| Source | What you get | Cost |
| --- | --- | --- |
| **iOS Core Image** (shipped, on by default) | ~40–60 usable system filters, enumerated from the OS at runtime | none |
| **Snappy face lenses** (shipped, on by default) | Vision-tracked overlays and distortions | none |
| **Snap Camera Kit** (adapter included, off by default) | Real Snap AR Lenses, the ones built in Lens Studio | Snap account + commercial terms |

## What Camera Kit actually gives you

Worth being precise, because it is easy to assume "Camera Kit" means "every lens
in Snapchat":

- Lenses reach your app through **lens groups** you configure in the Camera Kit
  portal. You control what is in a group — typically lenses you or your partners
  built and published from **Lens Studio**, plus whatever Snap makes available to
  your account.
- The full public Snapchat catalogue is *not* licensed for redistribution
  wholesale. Assume you are curating a group, not mirroring Snapchat.
- Camera Kit is commercial: there is a free tier measured in monthly unique
  users, and past it you need an agreement with Snap. Check Snap's current terms
  before shipping anything.

Everything above changes at Snap's discretion — verify against
<https://docs.snap.com/camera-kit> rather than trusting this file.

## Wiring it up

1. **Get credentials.** Create an app in the Snap developer portal, note the
   application id and the API token, and create at least one lens group.
2. **Add the SDK.** Camera Kit ships as a binary distribution (CocoaPods or Swift
   Package, depending on Snap's current packaging). Add `SCSDKCameraKit` to the
   `Snappy` target — via a `packages:`/`dependencies:` entry in `project.yml` if
   it is an SPM release, or a Podfile alongside the generated project if not.
3. **Turn the code on.** In `Config/Local.xcconfig`:

   ```
   SNAPPY_EXTRA_SWIFT_FLAGS = SNAP_CAMERA_KIT
   ```

   That compilation condition is what activates the guarded code in
   `Snappy/Filters/SnapCameraKitProvider.swift`.
4. **Add the credentials to Info.plist.** Put them in the `info.properties`
   block in `project.yml` so they survive project regeneration:

   ```yaml
   SCCameraKitApplicationID: your-application-id
   SCCameraKitAPIToken: your-api-token
   SCCameraKitLensGroupIDs:
     - your-lens-group-id
   ```

   These are client credentials, not secrets in the "keep out of git" sense, but
   they identify your account and its quota — treat them the way you would an
   analytics key, and keep them in `Local.xcconfig`/a private overlay if the
   repository is public.

## The one structural catch

Snappy's own lenses are pure functions: `CIImage` in, `CIImage` out
(`LensEffect.apply(to:context:)`). Camera Kit does not work that way — it takes
over the capture session and renders lenses through its own pipeline into its own
output view.

So a Camera Kit lens cannot simply be dropped into `FramePipeline`. The
integration is a *mode switch*: when a `CameraKitLens` is selected, the app tears
down `CameraSession` + `MetalPreviewView` and stands up Camera Kit's session and
preview instead, then switches back when a built-in lens is selected.

`SnapCameraKitProvider` and `CameraKitLens` are the seams for that: the provider
vends carousel entries, and `CameraKitLens.apply` is deliberately a pass-through
that is never called. The pipeline swap itself (a `CameraKitPipeline` type) is
the part you write once you have the SDK in hand and can build against its real
API — it is not stubbed out here, because a stub written against an SDK nobody
can compile is worse than an honest empty seam.

Until then, `SnapCameraKitProvider.makeEffects()` returns an empty array, the
Settings screen says so, and the rest of the app is unaffected.
