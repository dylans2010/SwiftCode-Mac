import SwiftUI

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
        AdaptivePage {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
        }
    }
}
