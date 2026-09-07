import CoreImage
import CoreMedia
import Foundation
import ImageIO
import QuartzCore

/// Everything that happens to a frame between the camera and the screen.
///
/// This object is confined to `CameraSession.videoQueue`: only the frame callback
/// touches it, and the view model mutates it by hopping onto that queue. That is
/// what keeps the pipeline lock-free at 30-60fps.
final class FramePipeline {
    private let renderContext: RenderContext
    private let tracker = FaceTracker()
    let recorder = VideoRecorder()

    var effect: LensEffect = PassthroughEffect() {
        didSet {
            guard effect !== oldValue else { return }
            effectSelectedAt = CACurrentMediaTime()
            tracker.reset()
        }
    }
    var isFrontCamera = true
    private var effectSelectedAt = CACurrentMediaTime()

    /// Set to capture the next filtered frame as a still.
    var pendingPhoto: ((CIImage) -> Void)?

    init(renderContext: RenderContext = .shared) {
        self.renderContext = renderContext
    }

    /// Returns the filtered frame, ready to be drawn.
    func process(_ sampleBuffer: CMSampleBuffer) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let source = CIImage(cvPixelBuffer: pixelBuffer)

        let faces = effect.requiresFaceTracking
            ? tracker.faces(in: source, context: renderContext.ciContext)
            : []

        let context = EffectContext(
            extent: source.extent,
            faces: faces,
            time: time,
            isFrontCamera: isFrontCamera,
            elapsed: CACurrentMediaTime() - effectSelectedAt
        )
        let filtered = effect.apply(to: source, context: context)

        if let pendingPhoto {
            self.pendingPhoto = nil
            pendingPhoto(filtered)
        }

        if recorder.isRecording {
            recorder.append(image: filtered,
                            at: time,
                            context: renderContext.ciContext,
                            colorSpace: renderContext.outputColorSpace)
        }

        return filtered
    }

    /// JPEG for the photo library / share sheet. Runs off the video queue.
    func encodeJPEG(_ image: CIImage, quality: CGFloat = 0.92) -> Data? {
        renderContext.ciContext.jpegRepresentation(
            of: image,
            colorSpace: renderContext.outputColorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }
}
