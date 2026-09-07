import CoreImage
import MetalKit
import SwiftUI
import UIKit

/// Draws the filtered `CIImage` straight onto a Metal drawable.
///
/// The viewfinder never uses `AVCaptureVideoPreviewLayer`: what you see has to
/// be the same pixels that get written to the photo or the movie, otherwise the
/// filter preview lies about the result.
final class MetalPreviewView: MTKView {
    private let renderContext: RenderContext
    private var currentImage: CIImage?
    /// `.aspectFill` matches how a camera app is expected to behave; the frame is
    /// cropped to the view rather than letterboxed.
    var fillsView: Bool = true

    init(renderContext: RenderContext = .shared) {
        self.renderContext = renderContext
        super.init(frame: .zero, device: renderContext.device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        isPaused = true
        enableSetNeedsDisplay = false
        autoResizeDrawable = true
        backgroundColor = .black
        isOpaque = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Hand a new frame to the view. Safe to call from any thread.
    func present(_ image: CIImage) {
        if Thread.isMainThread {
            currentImage = image
            draw()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.currentImage = image
                self?.draw()
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard
            let image = currentImage,
            let commandQueue = renderContext.commandQueue,
            let drawable = currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let drawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let scaled = Self.transform(image, toFill: drawableSize, fill: fillsView)

        renderContext.ciContext.render(
            scaled,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: drawableSize),
            colorSpace: renderContext.outputColorSpace
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Centre the frame in the drawable, scaling to fill (or fit) and cropping
    /// whatever falls outside.
    static func transform(_ image: CIImage, toFill size: CGSize, fill: Bool) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, size.width > 0, size.height > 0 else { return image }

        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height
        let scale = fill ? max(scaleX, scaleY) : min(scaleX, scaleY)

        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        let originX = (size.width - scaledWidth) / 2
        let originY = (size.height - scaledHeight) / 2

        return image
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: originX, y: originY))
            .cropped(to: CGRect(origin: .zero, size: size))
    }
}

/// SwiftUI wrapper. The view model owns the view so it can push frames into it
/// without going through `@Published` (which would allocate and diff at 30-60fps).
struct CameraPreview: UIViewRepresentable {
    let view: MetalPreviewView

    func makeUIView(context: Context) -> MetalPreviewView { view }
    func updateUIView(_ uiView: MetalPreviewView, context: Context) {}
}
