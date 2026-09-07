import CoreImage
import Foundation

#if SNAP_CAMERA_KIT
import SCSDKCameraKit
#endif

/// Adapter for Snap's Camera Kit — the only supported way to run real Snapchat
/// Lenses outside Snapchat.
///
/// Camera Kit is a closed-source binary SDK that needs a Snap developer account,
/// an application token and one or more *lens groups* configured in the Camera Kit
/// portal. It is therefore not linked by default: `makeEffects()` returns an empty
/// array and the carousel simply shows the built-in lenses. Setup lives in
/// docs/CAMERA_KIT.md.
///
/// Note on the pipeline: Camera Kit does not expose a "CIImage in, CIImage out"
/// hook. It takes over the capture session and renders lenses itself, so a
/// Camera Kit lens is not applied through `LensEffect.apply(to:context:)` —
/// selecting one switches the app to `CameraKitPipeline` instead. `CameraKitLens`
/// below is the carousel entry that triggers that switch; its `apply` is a
/// pass-through and is never called while the Camera Kit pipeline is running.
struct SnapCameraKitProvider: FilterProvider {
    let id = "snap.camerakit"
    let displayName = "Snap Camera Kit"

    /// Lens group IDs from the Camera Kit portal. Read from Info.plist so the
    /// values are configuration, not code.
    static var configuredGroupIDs: [String] {
        (Bundle.main.object(forInfoDictionaryKey: "SCCameraKitLensGroupIDs") as? [String]) ?? []
    }

    static var applicationID: String? {
        Bundle.main.object(forInfoDictionaryKey: "SCCameraKitApplicationID") as? String
    }

    static var apiToken: String? {
        Bundle.main.object(forInfoDictionaryKey: "SCCameraKitAPIToken") as? String
    }

    /// True when the SDK is linked *and* credentials are present.
    static var isAvailable: Bool {
        #if SNAP_CAMERA_KIT
        return apiToken?.isEmpty == false && !configuredGroupIDs.isEmpty
        #else
        return false
        #endif
    }

    func makeEffects() -> [LensEffect] {
        #if SNAP_CAMERA_KIT
        guard Self.isAvailable else { return [] }
        // The repository loads asynchronously; CameraKitPipeline publishes the real
        // list once the group observer fires. Until then the carousel shows nothing
        // from this provider.
        return CameraKitLensStore.shared.cachedLenses.map(CameraKitLens.init(lens:))
        #else
        return []
        #endif
    }
}

#if SNAP_CAMERA_KIT
/// Carousel entry backed by a real Snap lens.
final class CameraKitLens: LensEffect {
    let id: String
    let name: String
    let symbol = "sparkles"
    let lens: Lens

    init(lens: Lens) {
        self.lens = lens
        self.id = "camerakit.\(lens.id)"
        self.name = lens.name ?? "Lens"
    }

    /// Never invoked: Camera Kit renders this lens in its own pipeline.
    func apply(to image: CIImage, context: EffectContext) -> CIImage { image }
}

/// Holds the lenses the Camera Kit repository has handed us so far.
final class CameraKitLensStore {
    static let shared = CameraKitLensStore()
    private(set) var cachedLenses: [Lens] = []
    private let lock = NSLock()

    func replace(with lenses: [Lens]) {
        lock.lock()
        cachedLenses = lenses
        lock.unlock()
    }
}
#endif
