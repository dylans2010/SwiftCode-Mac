// Ported from Legacy `SwiftCode/UI/Styles/Styling/AdaptiveEditorPage.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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
