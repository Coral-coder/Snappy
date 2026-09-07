import CoreImage
import CoreMedia
import Foundation

/// A face the tracker found in the current frame, in the coordinate space of the
/// `CIImage` being filtered (origin bottom-left, pixels).
struct TrackedFace: Equatable {
    var bounds: CGRect
    var leftEye: CGPoint?
    var rightEye: CGPoint?
    var nose: CGPoint?
    var mouth: CGPoint?
    /// Head roll in radians, positive counter-clockwise. Zero when unknown.
    var roll: CGFloat = 0

    /// Rough width of the face used to scale overlays.
    var scale: CGFloat { bounds.width }
}

/// Everything an effect might need beyond the pixels themselves.
struct EffectContext {
    var extent: CGRect
    var faces: [TrackedFace]
    var time: CMTime
    var isFrontCamera: Bool
    /// Seconds since the effect was selected, for animated lenses.
    var elapsed: TimeInterval
}

/// A single selectable look in the carousel.
///
/// Effects are stateful on purpose (they cache `CIFilter` instances), so they
/// are reference types and are only ever touched from the video queue.
protocol LensEffect: AnyObject {
    var id: String { get }
    var name: String { get }
    /// SF Symbol shown on the carousel button.
    var symbol: String { get }
    /// True when the effect needs face landmarks; the tracker is skipped entirely
    /// when the selected effect does not need them.
    var requiresFaceTracking: Bool { get }

    func apply(to image: CIImage, context: EffectContext) -> CIImage
}

extension LensEffect {
    var requiresFaceTracking: Bool { false }
    var symbol: String { "camera.filters" }
}

/// A source of lenses. Providers are asked for their catalogue once at launch.
///
/// Two ship in the app: the iOS system Core Image library and Snappy's own
/// face lenses. `SnapCameraKitProvider` is a third that lights up when the Snap
/// Camera Kit SDK is linked — see docs/CAMERA_KIT.md.
protocol FilterProvider {
    var id: String { get }
    var displayName: String { get }
    /// Providers that cannot run (missing SDK, missing credentials) return an
    /// empty array rather than failing; the app just shows fewer lenses.
    func makeEffects() -> [LensEffect]
}

/// The identity lens. Always first in the carousel so "no filter" is one swipe away.
final class PassthroughEffect: LensEffect {
    let id = "snappy.none"
    let name = "None"
    let symbol = "circle.slash"

    func apply(to image: CIImage, context: EffectContext) -> CIImage { image }
}
