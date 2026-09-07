import CoreImage
import Foundation
import Vision

/// Finds faces and their landmarks in the frames the camera hands us.
///
/// Detection runs on a downscaled copy of the frame and only every `strideFrames`
/// frames; the last result is reused in between. That keeps a face lens at 30fps
/// on older hardware, and the drift over one or two frames is invisible.
final class FaceTracker {
    /// Longest edge, in pixels, of the image handed to Vision.
    private let detectionSize: CGFloat = 480
    private let strideFrames: Int
    private var frameCounter = 0
    private var cached: [TrackedFace] = []
    private let sequenceHandler = VNSequenceRequestHandler()

    init(strideFrames: Int = 2) {
        self.strideFrames = max(1, strideFrames)
    }

    func reset() {
        cached = []
        frameCounter = 0
    }

    /// `image` must already be rotated upright, so Vision's coordinate space and
    /// the Core Image extent line up without any further conversion.
    func faces(in image: CIImage, context: CIContext) -> [TrackedFace] {
        defer { frameCounter += 1 }
        guard frameCounter % strideFrames == 0 else { return cached }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return cached }

        let scale = min(1, detectionSize / max(extent.width, extent.height))
        let small = image
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let smallSize = CGSize(width: extent.width * scale, height: extent.height * scale)

        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3

        do {
            try sequenceHandler.perform([request], on: small)
        } catch {
            return cached
        }

        let observations = (request.results ?? [])
        cached = observations.compactMap { observation in
            Self.trackedFace(from: observation, smallSize: smallSize, scale: scale, extent: extent)
        }
        return cached
    }

    private static func trackedFace(
        from observation: VNFaceObservation,
        smallSize: CGSize,
        scale: CGFloat,
        extent: CGRect
    ) -> TrackedFace? {
        guard scale > 0 else { return nil }
        let inverse = 1 / scale

        func toFrame(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * inverse + extent.origin.x,
                    y: point.y * inverse + extent.origin.y)
        }

        let box = VNImageRectForNormalizedRect(observation.boundingBox,
                                               Int(smallSize.width),
                                               Int(smallSize.height))
        let bounds = CGRect(
            x: box.origin.x * inverse + extent.origin.x,
            y: box.origin.y * inverse + extent.origin.y,
            width: box.width * inverse,
            height: box.height * inverse
        )

        func centroid(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region, region.pointCount > 0 else { return nil }
            let points = region.pointsInImage(imageSize: smallSize)
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let average = CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
            return toFrame(average)
        }

        let landmarks = observation.landmarks
        return TrackedFace(
            bounds: bounds,
            leftEye: centroid(landmarks?.leftEye),
            rightEye: centroid(landmarks?.rightEye),
            nose: centroid(landmarks?.nose),
            mouth: centroid(landmarks?.outerLips),
            roll: CGFloat(observation.roll?.doubleValue ?? 0)
        )
    }
}
