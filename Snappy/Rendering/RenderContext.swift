import CoreImage
import Metal

/// One Metal device / Core Image context shared by the viewfinder, the photo
/// writer and the video recorder. Creating a `CIContext` is expensive and the
/// filter caches live inside it, so there is exactly one for the whole app.
final class RenderContext {
    static let shared = RenderContext()

    let device: MTLDevice?
    let commandQueue: MTLCommandQueue?
    let ciContext: CIContext
    let workingColorSpace = CGColorSpaceCreateDeviceRGB()
    let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()

        let options: [CIContextOption: Any] = [
            .workingColorSpace: workingColorSpace,
            .cacheIntermediates: false,
            .name: "SnappyRenderContext"
        ]

        if let queue = commandQueue {
            self.ciContext = CIContext(mtlCommandQueue: queue, options: options)
        } else {
            // Simulator without a Metal device, or a very unusual failure. Core Image
            // still works on the CPU/OpenGL path, just slower.
            self.ciContext = CIContext(options: options)
        }
    }
}
