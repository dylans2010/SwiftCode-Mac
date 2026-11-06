// Ported from Legacy `SwiftCode/UI/Styles/Styling/MacDesktopOptimized.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

public struct MacDesktopOptimizedModifier: ViewModifier {
    @EnvironmentObject var layoutEngine: AdaptiveLayoutEngine

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.adaptiveMetrics, layoutEngine.metrics)
    }
}

public struct SourceControlEmbeddedModifier: ViewModifier {
    @EnvironmentObject var layoutEngine: AdaptiveLayoutEngine

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipped()
            .environment(\.adaptiveMetrics, layoutEngine.metrics)
    }
}

public struct SimulatorWorkspaceEmbeddedModifier: ViewModifier {
    @EnvironmentObject var layoutEngine: AdaptiveLayoutEngine

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.adaptiveMetrics, layoutEngine.metrics)
    }
}

extension View {
    public func macDesktopOptimized() -> some View {
        self.modifier(MacDesktopOptimizedModifier())
    }

    public func sourceControlEmbedded() -> some View {
        self.modifier(SourceControlEmbeddedModifier())
    }

    public func simulatorWorkspaceEmbedded() -> some View {
        self.modifier(SimulatorWorkspaceEmbeddedModifier())
    }
}
