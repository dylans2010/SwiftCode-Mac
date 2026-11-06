import SwiftUI

/// Adaptive split layout (Legacy
/// `SwiftCode/UI/Styles/Styling/AdaptiveSplitLayout.swift`, Dylan's own
/// code, ported under MIT). Direct port: a `NavigationSplitView` with
/// sidebar and detail.

public struct AdaptiveSplitLayout<Sidebar: View, Detail: View>: View {
    let sidebar: Sidebar
    let detail: Detail

    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.detail = detail()
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }
}
