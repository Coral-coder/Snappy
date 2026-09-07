# How Snappy is put together

## The frame path

```
AVCaptureSession ──▶ CMSampleBuffer ──▶ FramePipeline ──┬──▶ MetalPreviewView (screen)
   CameraSession        (video queue)                   ├──▶ VideoRecorder  (.mp4)
                                                        └──▶ pendingPhoto   (.jpg)
```

One rule drives the design: **what you see is what gets saved.** There is no
`AVCaptureVideoPreviewLayer` and no `AVCapturePhotoOutput`. Every frame is
filtered once, then that same `CIImage` goes to the screen, to the recorder and —
when you press the shutter — to the JPEG encoder. A filter can never look one way
in the viewfinder and another way in the file.

Everything on the frame path runs on `CameraSession.videoQueue`. `FramePipeline`
is confined to that queue; the view model mutates it by hopping onto it. The only
lock in the whole path is the one guarding the recorder's `isRecording` flag,
because that is the one piece of state the main actor also touches.

## Filters

`LensEffect` is the unit: an id, a name, and `apply(to:context:)`. `EffectContext`
carries the frame extent, the tracked faces, the timestamp and how long the lens
has been selected (for animated effects).

`FilterProvider` vends lenses. Three exist:

- **`CoreImageFilterProvider`** asks the OS what filters it has
  (`CIFilter.filterNames(inCategory:)`), keeps the ones that take a single image
  and can supply defaults for everything else, and wraps each as a lens. It is
  not a hard-coded list, so a new system filter in a future iOS version shows up
  on its own. Geometric inputs (`inputCenter`, `inputExtent`, `inputRadius`) are
  rescaled to the frame so a filter looks the same at 1080p and 4K.
- **`FaceEffectProvider`** is Snappy's own: Vision landmarks
  (`FaceTracker`) plus either Core Graphics art composited per face
  (`OverlayLens`) or a Core Image distortion anchored to the eyes.
- **`SnapCameraKitProvider`** is the seam for real Snap Lenses. It returns
  nothing unless the SDK is linked — see [CAMERA_KIT.md](CAMERA_KIT.md).

Face tracking only runs when the selected lens sets `requiresFaceTracking`, on a
downscaled copy of the frame, every other frame. That is what keeps a face lens
at full frame rate.

## Storage and sharing

Captures land in the app's own `Application Support/Captures` directory, not in
the system photo library. `CaptureStore` lists that directory; saving to Photos
(`PHPhotoLibrary`, add-only authorisation) and sharing (`UIActivityViewController`)
are both explicit, per-capture actions.

The app makes no network calls of its own. Sharing to Instagram, Messages,
wherever, happens through the system share sheet, which means the OS decides what
is offered and Snappy never sees a token or an account.

## Project generation

There is no `.xcodeproj` in the repository; `project.yml` is the source of truth
and XcodeGen generates the project (`make project`). That keeps merge conflicts
out of the pbxproj and lets CI configure signing by writing a single xcconfig.
Build settings you would normally hunt for in Xcode live in `Config/Base.xcconfig`.
