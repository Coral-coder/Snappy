import Foundation

/// The list of lenses shown in the carousel, assembled from every provider that
/// has something to offer.
final class FilterCatalog {
    private(set) var effects: [LensEffect]
    /// Provider display name for each effect, used to group the carousel.
    private(set) var sections: [(provider: String, range: Range<Int>)] = []

    init(providers: [FilterProvider] = FilterCatalog.defaultProviders) {
        var effects: [LensEffect] = [PassthroughEffect()]
        var sections: [(provider: String, range: Range<Int>)] = [(provider: "Snappy", range: 0..<1)]

        for provider in providers {
            let produced = provider.makeEffects()
            guard !produced.isEmpty else { continue }
            let start = effects.count
            effects.append(contentsOf: produced)
            sections.append((provider: provider.displayName, range: start..<effects.count))
        }

        self.effects = effects
        self.sections = sections
    }

    /// Face lenses first (they are the reason people open a filter app), then the
    /// system Core Image library, then Camera Kit when it is configured.
    static var defaultProviders: [FilterProvider] {
        [
            FaceEffectProvider(),
            SnapCameraKitProvider(),
            CoreImageFilterProvider()
        ]
    }

    func effect(at index: Int) -> LensEffect {
        effects[min(max(0, index), effects.count - 1)]
    }

    func index(of id: String) -> Int? {
        effects.firstIndex { $0.id == id }
    }

    var count: Int { effects.count }
}
