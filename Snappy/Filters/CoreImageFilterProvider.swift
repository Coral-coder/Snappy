import CoreImage
import Foundation

/// Exposes the filter library that already ships with iOS.
///
/// iOS includes a couple of hundred `CIFilter`s. Rather than hard-coding a list
/// that rots with every OS release, this provider asks Core Image what it has
/// (`CIFilter.filterNames(inCategories:)`), keeps the ones that can run on a
/// single input image, and wraps each one as a lens. New system filters in a
/// future iOS release show up automatically.
struct CoreImageFilterProvider: FilterProvider {
    let id = "system.coreimage"
    let displayName = "iOS Core Image"

    /// Categories worth putting in a camera carousel. Compositing, reduction and
    /// generator categories are deliberately left out: they either need a second
    /// image or do not produce a picture at all.
    static let categories: [String] = [
        kCICategoryColorEffect,
        kCICategoryStylize,
        kCICategoryHalftoneEffect,
        kCICategoryDistortionEffect,
        kCICategoryBlur,
        kCICategorySharpen,
        kCICategoryColorAdjustment
    ]

    /// Filters that are technically compatible but useless in a viewfinder:
    /// no-ops, things that need a real still image, or effects that are far too
    /// slow to run per frame.
    static let denyList: Set<String> = [
        "CIColorCube", "CIColorCubeWithColorSpace", "CIColorCubesMixedWithMask",
        "CIColorCurves", "CIColorMap", "CIColorPolynomial", "CIColorMatrix",
        "CIColorClamp", "CIColorControls", "CIWhitePointAdjust", "CIVibrance",
        "CIGammaAdjust", "CIExposureAdjust", "CIHueAdjust", "CITemperatureAndTint",
        "CIToneCurve", "CIToneMapHeadroom", "CILinearToSRGBToneCurve",
        "CISRGBToneCurveToLinear", "CIDepthOfField", "CIMedianFilter",
        "CIMotionBlur", "CIZoomBlur", "CIGlassDistortion", "CIDisplacementDistortion",
        "CIAreaAverage", "CIAreaHistogram", "CIPersonSegmentation",
        "CIEdgePreserveUpsampleFilter", "CILabDeltaE", "CIMorphologyGradient",
        "CIMorphologyMinimum", "CIMorphologyMaximum", "CIMorphologyRectangleMinimum",
        "CIMorphologyRectangleMaximum", "CIConvolution3X3", "CIConvolution5X5",
        "CIConvolution7X7", "CIConvolution9Horizontal", "CIConvolution9Vertical",
        "CIConvolutionRGB3X3", "CIConvolutionRGB5X5", "CIConvolutionRGB7X7",
        "CIConvolutionRGB9Horizontal", "CIConvolutionRGB9Vertical",
        "CIGaussianGradient", "CIMaskedVariableBlur", "CIBokehBlur"
    ]

    /// The handful the app promotes to the front of the carousel, in order.
    /// Everything else keeps Core Image's own ordering behind them.
    static let featured: [String] = [
        "CIPhotoEffectNoir",
        "CIComicEffect",
        "CIThermal",
        "CIXRay",
        "CIPhotoEffectProcess",
        "CIPhotoEffectInstant",
        "CICrystallize",
        "CIPixellate",
        "CIHexagonalPixellate",
        "CIBumpDistortion",
        "CIHoleDistortion",
        "CITwirlDistortion",
        "CIKaleidoscope",
        "CIEdgeWork",
        "CILineOverlay",
        "CIColorPosterize",
        "CIPointillize",
        "CIDotScreen",
        "CICMYKHalftone",
        "CIVignetteEffect",
        "CIGloom",
        "CIBloom"
    ]

    func makeEffects() -> [LensEffect] {
        let available = Self.availableFilterNames()
        var ordered: [String] = []
        var seen = Set<String>()

        for name in Self.featured where available.contains(name) {
            ordered.append(name)
            seen.insert(name)
        }
        for name in available.sorted() where !seen.contains(name) {
            ordered.append(name)
        }

        return ordered.compactMap { CoreImageLens(filterName: $0) }
    }

    /// Every system filter that takes one image in, produces one image out, and
    /// has a sensible default for the rest of its inputs.
    static func availableFilterNames() -> Set<String> {
        var names = Set<String>()
        for category in categories {
            for name in CIFilter.filterNames(inCategory: category) where isViewfinderCompatible(name) {
                names.insert(name)
            }
        }
        return names
    }

    /// A filter is usable in the viewfinder only if it takes one image, can fill in
    /// the rest of its inputs, *and* gives back an image at least as big as the one
    /// it was handed. That last check is not pedantry: filters like
    /// `CISaliencyMapFilter` satisfy every attribute rule and then return a fixed
    /// 64x64 analysis map, which would break both the preview and the recorder.
    static func isViewfinderCompatible(_ name: String) -> Bool {
        guard !denyList.contains(name), let filter = CIFilter(name: name) else { return false }
        guard hasUsableInputs(filter) else { return false }
        return producesAFullFrame(filter)
    }

    private static func hasUsableInputs(_ filter: CIFilter) -> Bool {
        let attributes = filter.attributes
        var takesInputImage = false

        for key in filter.inputKeys {
            if key == kCIInputImageKey {
                takesInputImage = true
                continue
            }
            guard let attribute = attributes[key] as? [String: Any] else { return false }
            let className = attribute[kCIAttributeClass] as? String

            switch className {
            case "CIImage":
                // Needs a second image (background, mask, gradient) we do not have.
                return false
            case "CIVector", "CIColor", "NSNumber", "NSData", "NSValue", "NSString", "AVCameraCalibrationData":
                // These are all fine as long as the filter can supply a default, or
                // the geometric keys we fill in ourselves below.
                if attribute[kCIAttributeDefault] == nil
                    && !CoreImageLens.geometryKeys.contains(key) {
                    return false
                }
            default:
                if attribute[kCIAttributeDefault] == nil { return false }
            }
        }
        return takesInputImage
    }

    /// Runs the filter over a probe frame and checks the extent it reports. Extents
    /// are computed lazily by Core Image, so nothing is actually rendered here.
    private static func producesAFullFrame(_ filter: CIFilter) -> Bool {
        let probeExtent = CGRect(x: 0, y: 0, width: 640, height: 480)
        let probe = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: probeExtent)

        filter.setValue(probe, forKey: kCIInputImageKey)
        CoreImageLens.configureGeometry(filter, inputKeys: Set(filter.inputKeys), extent: probeExtent)

        guard let output = filter.outputImage else { return false }
        // An infinite extent is fine — the lens crops it back to the frame.
        return output.extent.contains(probeExtent)
    }
}

/// Wraps one system `CIFilter` as a lens.
final class CoreImageLens: LensEffect {
    /// Keys the lens fills in from the frame geometry instead of the filter's default,
    /// so effects stay centred no matter the capture resolution.
    static let geometryKeys: Set<String> = ["inputCenter", "inputExtent", "inputPoint0", "inputPoint1"]

    let id: String
    let name: String
    let symbol: String
    private let filter: CIFilter
    private let inputKeys: Set<String>

    init?(filterName: String) {
        guard let filter = CIFilter(name: filterName) else { return nil }
        self.filter = filter
        self.id = "coreimage.\(filterName)"
        self.name = Self.friendlyName(for: filterName, filter: filter)
        self.symbol = Self.symbol(for: filterName)
        self.inputKeys = Set(filter.inputKeys)
    }

    func apply(to image: CIImage, context: EffectContext) -> CIImage {
        let extent = image.extent
        filter.setValue(image, forKey: kCIInputImageKey)
        Self.configureGeometry(filter, inputKeys: inputKeys, extent: extent)

        guard let output = filter.outputImage else { return image }
        // Several filters (blurs, distortions) return an infinite or grown extent.
        // Clamp back to the frame so the recorder and the preview agree.
        return output.cropped(to: extent)
    }

    /// Fills in the inputs that depend on the size of the frame rather than on
    /// taste. Shared with the compatibility probe so a filter is vetted with
    /// exactly the parameters it will be used with.
    static func configureGeometry(_ filter: CIFilter, inputKeys: Set<String>, extent: CGRect) {
        if inputKeys.contains("inputCenter") {
            filter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: "inputCenter")
        }
        if inputKeys.contains("inputExtent") {
            filter.setValue(CIVector(cgRect: extent), forKey: "inputExtent")
        }
        if inputKeys.contains("inputPoint0") {
            filter.setValue(CIVector(x: extent.midX * 0.5, y: extent.midY), forKey: "inputPoint0")
        }
        if inputKeys.contains("inputPoint1") {
            filter.setValue(CIVector(x: extent.midX * 1.5, y: extent.midY), forKey: "inputPoint1")
        }
        // Radii and widths default to values tuned for small images; scale them to
        // the frame so a filter looks the same on 1080p and 4K.
        if inputKeys.contains("inputRadius"), let attribute = filter.attributes["inputRadius"] as? [String: Any] {
            let base = CGFloat((attribute[kCIAttributeDefault] as? NSNumber)?.doubleValue ?? 10)
            let maximum = CGFloat((attribute[kCIAttributeSliderMax] as? NSNumber)?.doubleValue ?? Double(base * 4))
            filter.setValue(min(maximum, base * extent.width / 640), forKey: "inputRadius")
        }
        if inputKeys.contains("inputScale"), filter.name == "CIBumpDistortion" {
            filter.setValue(0.5, forKey: "inputScale")
        }
    }

    /// Core Image ships localized display names; fall back to de-camel-casing.
    static func friendlyName(for filterName: String, filter: CIFilter) -> String {
        if let display = filter.attributes[kCIAttributeFilterDisplayName] as? String, !display.isEmpty {
            return display
                .replacingOccurrences(of: "Photo Effect ", with: "")
                .replacingOccurrences(of: " Effect", with: "")
                .replacingOccurrences(of: " Distortion", with: "")
        }
        return filterName.replacingOccurrences(of: "CI", with: "")
    }

    static func symbol(for filterName: String) -> String {
        switch filterName {
        case "CIPhotoEffectNoir", "CIPhotoEffectMono": return "circle.lefthalf.filled"
        case "CIComicEffect", "CILineOverlay", "CIEdgeWork": return "scribble"
        case "CIThermal": return "thermometer.medium"
        case "CIXRay": return "waveform.path.ecg"
        case "CICrystallize", "CIPointillize": return "sparkles"
        case "CIPixellate", "CIHexagonalPixellate": return "squareshape.split.3x3"
        case "CIBloom", "CIGloom": return "sun.max"
        case "CIKaleidoscope", "CITriangleKaleidoscope": return "camera.aperture"
        case "CIVignetteEffect": return "circle.dashed"
        default:
            return filterName.contains("Distortion") ? "tornado" : "camera.filters"
        }
    }
}
