import CoreImage
import UIKit

/// Vector art for the face lenses, drawn once with Core Graphics and cached as a
/// `CIImage`. Keeping the art in code (rather than in PNGs) means the lenses stay
/// sharp at 4K and the app ships without any image assets to license.
enum OverlayArt {
    private static var cache: [String: CIImage] = [:]
    private static let lock = NSLock()

    /// Cached art, already flipped into Core Image's bottom-left origin space so
    /// callers can position it with a plain affine transform.
    static func image(_ kind: Kind) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[kind.rawValue] { return cached }

        let size = kind.canvasSize
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            format.scale = 1
            return format
        }())

        let uiImage = renderer.image { context in
            kind.draw(in: context.cgContext, size: size)
        }
        guard let cgImage = uiImage.cgImage else { return nil }

        let flipped = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1)
                .concatenating(CGAffineTransform(translationX: 0, y: size.height)))
        cache[kind.rawValue] = flipped
        return flipped
    }

    enum Kind: String {
        case sunglasses
        case dogEars
        case dogNose
        case crown
        case heart

        var canvasSize: CGSize {
            switch self {
            case .sunglasses: return CGSize(width: 512, height: 200)
            case .dogEars: return CGSize(width: 512, height: 320)
            case .dogNose: return CGSize(width: 200, height: 160)
            case .crown: return CGSize(width: 512, height: 260)
            case .heart: return CGSize(width: 200, height: 180)
            }
        }

        func draw(in context: CGContext, size: CGSize) {
            switch self {
            case .sunglasses: Self.drawSunglasses(context, size)
            case .dogEars: Self.drawDogEars(context, size)
            case .dogNose: Self.drawDogNose(context, size)
            case .crown: Self.drawCrown(context, size)
            case .heart: Self.drawHeart(context, size)
            }
        }

        private static func drawSunglasses(_ context: CGContext, _ size: CGSize) {
            let lensWidth = size.width * 0.42
            let lensHeight = size.height * 0.62
            let top = size.height * 0.22

            context.setFillColor(UIColor(white: 0.05, alpha: 0.92).cgColor)
            for x in [size.width * 0.02, size.width * 0.56] {
                let rect = CGRect(x: x, y: top, width: lensWidth, height: lensHeight)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: lensHeight * 0.45)
                context.addPath(path.cgPath)
                context.fillPath()
            }

            // Bridge and arms.
            context.setStrokeColor(UIColor(white: 0.05, alpha: 0.92).cgColor)
            context.setLineWidth(size.height * 0.09)
            context.move(to: CGPoint(x: size.width * 0.44, y: top + lensHeight * 0.28))
            context.addLine(to: CGPoint(x: size.width * 0.56, y: top + lensHeight * 0.28))
            context.strokePath()

            // A soft highlight so the lenses do not read as flat black holes.
            context.setFillColor(UIColor(white: 1, alpha: 0.18).cgColor)
            for x in [size.width * 0.08, size.width * 0.62] {
                context.fillEllipse(in: CGRect(x: x, y: top + lensHeight * 0.12,
                                               width: lensWidth * 0.35, height: lensHeight * 0.28))
            }
        }

        private static func drawDogEars(_ context: CGContext, _ size: CGSize) {
            let outer = UIColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1).cgColor
            let inner = UIColor(red: 0.85, green: 0.62, blue: 0.52, alpha: 1).cgColor

            func ear(flipped: Bool) {
                let width = size.width * 0.3
                let x = flipped ? size.width * 0.68 : size.width * 0.02
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x + width * 0.5, y: size.height))
                path.addCurve(to: CGPoint(x: x + (flipped ? width : 0), y: size.height * 0.06),
                              controlPoint1: CGPoint(x: x + width * (flipped ? 1.05 : -0.05), y: size.height * 0.75),
                              controlPoint2: CGPoint(x: x + width * (flipped ? 1.0 : 0.0), y: size.height * 0.3))
                path.addCurve(to: CGPoint(x: x + width * 0.5, y: size.height),
                              controlPoint1: CGPoint(x: x + width * (flipped ? 0.35 : 0.65), y: size.height * 0.28),
                              controlPoint2: CGPoint(x: x + width * (flipped ? 0.30 : 0.70), y: size.height * 0.7))
                context.setFillColor(outer)
                context.addPath(path.cgPath)
                context.fillPath()

                context.saveGState()
                context.translateBy(x: x + width * 0.5, y: size.height * 0.62)
                context.scaleBy(x: 0.45, y: 0.62)
                context.translateBy(x: -(x + width * 0.5), y: -size.height * 0.62)
                context.setFillColor(inner)
                context.addPath(path.cgPath)
                context.fillPath()
                context.restoreGState()
            }

            ear(flipped: false)
            ear(flipped: true)
        }

        private static func drawDogNose(_ context: CGContext, _ size: CGSize) {
            context.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
            let body = CGRect(x: size.width * 0.1, y: size.height * 0.25,
                              width: size.width * 0.8, height: size.height * 0.6)
            context.addPath(UIBezierPath(roundedRect: body, cornerRadius: body.height * 0.5).cgPath)
            context.fillPath()
            context.setFillColor(UIColor(white: 1, alpha: 0.22).cgColor)
            context.fillEllipse(in: CGRect(x: size.width * 0.24, y: size.height * 0.33,
                                           width: size.width * 0.28, height: size.height * 0.2))
        }

        private static func drawCrown(_ context: CGContext, _ size: CGSize) {
            let gold = UIColor(red: 0.98, green: 0.78, blue: 0.19, alpha: 1).cgColor
            let path = UIBezierPath()
            let base = size.height * 0.92
            path.move(to: CGPoint(x: size.width * 0.05, y: base))
            path.addLine(to: CGPoint(x: size.width * 0.05, y: size.height * 0.25))
            path.addLine(to: CGPoint(x: size.width * 0.27, y: size.height * 0.6))
            path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.08))
            path.addLine(to: CGPoint(x: size.width * 0.73, y: size.height * 0.6))
            path.addLine(to: CGPoint(x: size.width * 0.95, y: size.height * 0.25))
            path.addLine(to: CGPoint(x: size.width * 0.95, y: base))
            path.close()
            context.setFillColor(gold)
            context.addPath(path.cgPath)
            context.fillPath()

            context.setFillColor(UIColor(red: 0.85, green: 0.2, blue: 0.32, alpha: 1).cgColor)
            for x in [0.2, 0.5, 0.8] {
                context.fillEllipse(in: CGRect(x: size.width * (x - 0.045), y: size.height * 0.66,
                                               width: size.width * 0.09, height: size.width * 0.09))
            }
        }

        private static func drawHeart(_ context: CGContext, _ size: CGSize) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.95))
            path.addCurve(to: CGPoint(x: size.width * 0.02, y: size.height * 0.32),
                          controlPoint1: CGPoint(x: size.width * 0.2, y: size.height * 0.78),
                          controlPoint2: CGPoint(x: size.width * 0.02, y: size.height * 0.58))
            path.addArc(withCenter: CGPoint(x: size.width * 0.26, y: size.height * 0.3),
                        radius: size.width * 0.24, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addArc(withCenter: CGPoint(x: size.width * 0.74, y: size.height * 0.3),
                        radius: size.width * 0.24, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addCurve(to: CGPoint(x: size.width * 0.5, y: size.height * 0.95),
                          controlPoint1: CGPoint(x: size.width * 0.98, y: size.height * 0.58),
                          controlPoint2: CGPoint(x: size.width * 0.8, y: size.height * 0.78))
            context.setFillColor(UIColor(red: 0.95, green: 0.2, blue: 0.35, alpha: 1).cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
        }
    }
}
