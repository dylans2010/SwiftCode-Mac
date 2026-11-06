// Ported from Legacy `SwiftCode/UI/Styles/Styling/AdaptiveGrid.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> `.background(.thinMaterial, in:
// RoundedRectangle(...))`: no liquidGlass modifier exists in the destination
// (Legacy LiquidGlass.swift is PARTIAL, another scope); this is the destination's
// own card treatment (WorkersMainView.swift precedent).
// Wiring: the app root must inject AdaptiveLayoutEngine.shared as an
// environmentObject (MacDesktopOptimizedModifier reads it) and wrap pages in
// AdaptivePage/AdaptiveDashboardPage/AdaptiveEditorPage/AdaptiveSettingsPage;
// AdaptiveGrid/AdaptiveSplitLayout/AdaptiveSheet are used directly by callers.

import SwiftUI

public struct AdaptiveGrid<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    @Environment(\.adaptiveMetrics) var metrics
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let content: (Data.Element) -> Content

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.id = id
        self.content = content
    }

    public var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: metrics.currentBreakpoint.standardSpacing), count: metrics.currentBreakpoint.defaultColumns)

        LazyVGrid(columns: columns, spacing: metrics.currentBreakpoint.standardSpacing) {
            ForEach(data, id: id) { item in
                content(item)
            }
        }
        .padding(metrics.currentBreakpoint.standardPadding)
    }
}
