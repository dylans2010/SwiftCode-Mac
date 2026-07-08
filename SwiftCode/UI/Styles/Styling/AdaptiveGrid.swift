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
