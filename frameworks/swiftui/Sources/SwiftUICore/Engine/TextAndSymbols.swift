import Foundation

package struct SymbolMetrics: Sendable {
    package var size: CGSize
    package var baselineOffset: CGFloat
    package var naturalSize: CGSize

    package init(size: CGSize, baselineOffset: CGFloat, naturalSize: CGSize) {
        self.size = size
        self.baselineOffset = baselineOffset
        self.naturalSize = naturalSize
    }
}

package protocol SymbolProvider {
    func symbol(named name: String, font: TextFont) -> SymbolMetrics?
    var spacingAbove: SpacingPreference { get }
    var spacingBelow: SpacingPreference { get }
}

package struct StubSymbolProvider: SymbolProvider {
    package var symbols: [String: SymbolMetrics]
    package var spacingAbove = SpacingPreference(kind: .image, towardStandard: 7.0 / 3, towardText: 0)
    package var spacingBelow = SpacingPreference(kind: .image, towardStandard: 10.0 / 3, towardText: 0)

    package init(symbols: [String: SymbolMetrics] = [:]) { self.symbols = symbols }

    package func symbol(named name: String, font: TextFont) -> SymbolMetrics? { symbols[name] }
}
