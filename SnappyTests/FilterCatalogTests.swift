import CoreImage
import XCTest
@testable import Snappy

final class FilterCatalogTests: XCTestCase {
    private let context = CIContext(options: [.cacheIntermediates: false])

    private func sampleFrame() -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: 320, height: 568)
        return CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputColor0": CIColor(red: 0.9, green: 0.4, blue: 0.2),
            "inputPoint1": CIVector(x: extent.width, y: extent.height),
            "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.8)
        ])!.outputImage!.cropped(to: extent)
    }

    private func makeContext(for image: CIImage, faces: [TrackedFace] = []) -> EffectContext {
        EffectContext(extent: image.extent, faces: faces, time: .zero, isFrontCamera: true, elapsed: 0)
    }

    func testCatalogAlwaysStartsWithPassthrough() {
        let catalog = FilterCatalog()
        XCTAssertGreaterThan(catalog.count, 1)
        XCTAssertEqual(catalog.effect(at: 0).id, "snappy.none")
    }

    func testCatalogIdentifiersAreUnique() {
        let ids = FilterCatalog().effects.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Two lenses share an id")
    }

    func testSystemFilterLibraryIsNotEmpty() {
        // The whole point of the Core Image provider is that the OS supplies the
        // filters; if this is empty the app has silently lost most of its catalogue.
        let effects = CoreImageFilterProvider().makeEffects()
        XCTAssertGreaterThan(effects.count, 20)
    }

    func testDeniedFiltersAreExcluded() {
        let names = CoreImageFilterProvider.availableFilterNames()
        XCTAssertFalse(names.contains("CIColorCube"))
        XCTAssertFalse(names.contains("CIColorControls"))
    }

    func testFiltersThatNeedASecondImageAreRejected() {
        XCTAssertFalse(CoreImageFilterProvider.isViewfinderCompatible("CISourceOverCompositing"))
        XCTAssertFalse(CoreImageFilterProvider.isViewfinderCompatible("CIBlendWithMask"))
    }

    func testFiltersThatDoNotReturnAFullFrameAreRejected() {
        // CISaliencyMapFilter satisfies every attribute rule and then hands back a
        // fixed 64x64 analysis map. It reached the carousel once; it should not again.
        XCTAssertFalse(CoreImageFilterProvider.isViewfinderCompatible("CISaliencyMapFilter"))
        XCTAssertFalse(CoreImageFilterProvider.availableFilterNames().contains("CISaliencyMapFilter"))
    }

    /// Every lens has to return something renderable at the frame's own extent,
    /// otherwise the recorder writes garbage or the preview goes black.
    func testEveryLensPreservesTheFrameExtent() throws {
        let frame = sampleFrame()
        let faces = [
            TrackedFace(
                bounds: CGRect(x: 90, y: 300, width: 140, height: 170),
                leftEye: CGPoint(x: 130, y: 420),
                rightEye: CGPoint(x: 190, y: 420),
                nose: CGPoint(x: 160, y: 380),
                mouth: CGPoint(x: 160, y: 340),
                roll: 0.1
            )
        ]

        for effect in FilterCatalog().effects {
            let output = effect.apply(to: frame, context: makeContext(for: frame, faces: faces))
            XCTAssertEqual(output.extent, frame.extent, "\(effect.id) changed the frame extent")
            XCTAssertNotNil(
                context.createCGImage(output, from: output.extent),
                "\(effect.id) produced an unrenderable image"
            )
        }
    }

    func testFaceLensesAreHarmlessWithoutAFace() {
        let frame = sampleFrame()
        for effect in FaceEffectProvider().makeEffects() {
            let output = effect.apply(to: frame, context: makeContext(for: frame))
            XCTAssertEqual(output.extent, frame.extent)
        }
    }

    func testAspectFillCropsToTheDrawable() {
        let frame = sampleFrame()
        let target = CGSize(width: 200, height: 200)
        let filled = MetalPreviewView.transform(frame, toFill: target, fill: true)
        XCTAssertEqual(filled.extent, CGRect(origin: .zero, size: target))
    }

    func testAspectFitLetterboxesInsideTheDrawable() {
        let frame = sampleFrame()
        let target = CGSize(width: 200, height: 200)
        let fitted = MetalPreviewView.transform(frame, toFill: target, fill: false)
        XCTAssertLessThanOrEqual(fitted.extent.width, target.width + 0.001)
        XCTAssertLessThanOrEqual(fitted.extent.height, target.height + 0.001)
    }

    func testOverlayArtRendersAndIsCached() throws {
        let first = try XCTUnwrap(OverlayArt.image(.sunglasses))
        let second = try XCTUnwrap(OverlayArt.image(.sunglasses))
        XCTAssertEqual(first.extent, second.extent)
        XCTAssertEqual(first.extent.size, OverlayArt.Kind.sunglasses.canvasSize)
    }

    func testCameraKitIsOffWhenTheSDKIsNotLinked() {
        // The default build ships without Snap's SDK; the provider must degrade to
        // "no lenses" rather than failing.
        XCTAssertTrue(SnapCameraKitProvider().makeEffects().isEmpty || SnapCameraKitProvider.isAvailable)
    }
}
