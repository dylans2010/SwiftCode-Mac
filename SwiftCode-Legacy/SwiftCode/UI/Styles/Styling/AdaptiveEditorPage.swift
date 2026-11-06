import SwiftUI

public struct AdaptiveEditorPage<Sidebar: View, Content: View, Inspector: View>: View {
    let sidebar: Sidebar
    let content: Content
    let inspector: Inspector

    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Inspector
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.inspector = inspector()
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            content
                .inspector(isPresented: .constant(true)) {
                    inspector
                }
        }
    }
}
