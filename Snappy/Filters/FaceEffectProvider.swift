import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Snappy's own face lenses: the "put a thing on your head" effects, built on
/// Vision landmarks plus Core Image distortions. No third-party SDK, no network,
/// no account.
struct FaceEffectProvider: FilterProvider {
    let id = "snappy.face"
    let displayName = "Face Lenses"

    func makeEffects() -> [LensEffect] {
        [
            OverlayLens(id: "snappy.face.sunglasses", name: "Shades", symbol: "sunglasses",
                        pieces: [.init(art: .sunglasses, anchor: .eyes, widthRatio: 1.15, offset: CGVector(dx: 0, dy: 0))]),
            OverlayLens(id: "snappy.face.dog", name: "Puppy", symbol: "pawprint",
                        pieces: [
                            .init(art: .dogEars, anchor: .aboveHead, widthRatio: 1.5, offset: CGVector(dx: 0, dy: 0.18)),
                            .init(art: .dogNose, anchor: .nose, widthRatio: 0.32, offset: CGVector(dx: 0, dy: 0))
                        ]),
            OverlayLens(id: "snappy.face.crown", name: "Royalty", symbol: "crown",
                        pieces: [.init(art: .crown, anchor: .aboveHead, widthRatio: 1.05, offset: CGVector(dx: 0, dy: 0.12))]),
            OverlayLens(id: "snappy.face.hearts", name: "Smitten", symbol: "heart.fill",
                        pieces: [
                            .init(art: .heart, anchor: .leftEye, widthRatio: 0.3, offset: .zero),
                            .init(art: .heart, anchor: .rightEye, widthRatio: 0.3, offset: .zero)
                        ]),
            BigEyesLens(),
            AlienLens(),
            SquishLens()
        ]
    }
}

/// Composites cached vector art onto each detected face.
final class OverlayLens: LensEffect {
    struct Piece {
        enum Anchor {
            case eyes, leftEye, rightEye, nose, mouth, aboveHead, faceCenter
        }

        var art: OverlayArt.Kind
        var anchor: Anchor
        /// Width of the art as a multiple of the face width.
        var widthRatio: CGFloat
        /// Extra offset, as a multiple of the face width/height.
        var offset: CGVector
    }

    let id: String
    let name: String
    let symbol: String
    let requiresFaceTracking = true
    private let pieces: [Piece]
    private let composite = CIFilter.sourceOverCompositing()

    init(id: String, name: String, symbol: String, pieces: [Piece]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.pieces = pieces
    }

    func apply(to image: CIImage, context: EffectContext) -> CIImage {
        guard !context.faces.isEmpty else { return image }
        var result = image

        for face in context.faces {
            for piece in pieces {
                guard
                    let art = OverlayArt.image(piece.art),
                    let anchor = anchorPoint(piece.anchor, face: face)
                else { continue }

                let artExtent = art.extent
                guard artExtent.width > 0 else { continue }

                let targetWidth = face.bounds.width * piece.widthRatio
                let scale = targetWidth / artExtent.width
                let position = CGPoint(
                    x: anchor.x + piece.offset.dx * face.bounds.width,
                    y: anchor.y + piece.offset.dy * face.bounds.height
                )

                var transform = CGAffineTransform(translationX: -artExtent.midX, y: -artExtent.midY)
                transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                transform = transform.concatenating(CGAffineTransform(rotationAngle: face.roll))
                transform = transform.concatenating(CGAffineTransform(translationX: position.x, y: position.y))

                composite.inputImage = art.transformed(by: transform)
                composite.backgroundImage = result
                result = composite.outputImage ?? result
            }
        }
        return result.cropped(to: image.extent)
    }

    private func anchorPoint(_ anchor: Piece.Anchor, face: TrackedFace) -> CGPoint? {
        switch anchor {
        case .leftEye:
            return face.leftEye
        case .rightEye:
            return face.rightEye
        case .nose:
            return face.nose ?? CGPoint(x: face.bounds.midX, y: face.bounds.midY)
        case .mouth:
            return face.mouth
        case .faceCenter:
            return CGPoint(x: face.bounds.midX, y: face.bounds.midY)
        case .aboveHead:
            return CGPoint(x: face.bounds.midX, y: face.bounds.maxY)
        case .eyes:
            if let left = face.leftEye, let right = face.rightEye {
                return CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
            }
            return CGPoint(x: face.bounds.midX, y: face.bounds.minY + face.bounds.height * 0.66)
        }
    }
}

/// Bulges both eyes with `CIBumpDistortion`.
final class BigEyesLens: LensEffect {
    let id = "snappy.face.bigeyes"
    let name = "Big Eyes"
    let symbol = "eyes"
    let requiresFaceTracking = true

    private let left = CIFilter.bumpDistortion()
    private let right = CIFilter.bumpDistortion()

    func apply(to image: CIImage, context: EffectContext) -> CIImage {
        Self.bulgeEyes(image, faces: context.faces, left: left, right: right, scale: 0.55)
    }

    static func bulgeEyes(
        _ image: CIImage,
        faces: [TrackedFace],
        left: any CIBumpDistortion,
        right: any CIBumpDistortion,
        scale: Float
    ) -> CIImage {
        guard let face = faces.first else { return image }
        var result = image
        let radius = Float(face.bounds.width * 0.22)

        if let point = face.leftEye {
            left.inputImage = result
            left.center = point
            left.radius = radius
            left.scale = scale
            result = left.outputImage ?? result
        }
        if let point = face.rightEye {
            right.inputImage = result
            right.center = point
            right.radius = radius
            right.scale = scale
            result = right.outputImage ?? result
        }
        return result.cropped(to: image.extent)
    }
}

/// Big eyes plus a green cast — the classic cheap alien.
final class AlienLens: LensEffect {
    let id = "snappy.face.alien"
    let name = "Alien"
    let symbol = "person.fill.questionmark"
    let requiresFaceTracking = true

    private let left = CIFilter.bumpDistortion()
    private let right = CIFilter.bumpDistortion()
    private let tint = CIFilter.colorMatrix()

    func apply(to image: CIImage, context: EffectContext) -> CIImage {
        let bulged = BigEyesLens.bulgeEyes(image, faces: context.faces, left: left, right: right, scale: 0.85)
        tint.inputImage = bulged
        tint.rVector = CIVector(x: 0.5, y: 0.2, z: 0, w: 0)
        tint.gVector = CIVector(x: 0.15, y: 1.0, z: 0.25, w: 0)
        tint.bVector = CIVector(x: 0, y: 0.25, z: 0.55, w: 0)
        return (tint.outputImage ?? bulged).cropped(to: image.extent)
    }
}

/// Squeezes the whole face inward. Unflattering, which is the point.
final class SquishLens: LensEffect {
    let id = "snappy.face.squish"
    let name = "Squish"
    let symbol = "arrow.down.right.and.arrow.up.left"
    let requiresFaceTracking = true

    private let pinch = CIFilter.pinchDistortion()

    func apply(to image: CIImage, context: EffectContext) -> CIImage {
        guard let face = context.faces.first else { return image }
        pinch.inputImage = image
        pinch.center = CGPoint(x: face.bounds.midX, y: face.bounds.midY)
        pinch.radius = Float(face.bounds.width * 0.9)
        pinch.scale = 0.45
        return (pinch.outputImage ?? image).cropped(to: image.extent)
    }
}
