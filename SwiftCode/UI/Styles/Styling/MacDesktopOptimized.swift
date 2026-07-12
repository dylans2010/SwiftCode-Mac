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
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .clipped()
            .environment(\.adaptiveMetrics, layoutEngine.metrics)
            .animation(.easeInOut(duration: 0.2), value: layoutEngine.metrics.windowWidth)
    }
}

public struct SimulatorWorkspaceEmbeddedModifier: ViewModifier {
    @EnvironmentObject var layoutEngine: AdaptiveLayoutEngine

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .clipped()
            .environment(\.adaptiveMetrics, layoutEngine.metrics)
            .animation(.easeInOut(duration: 0.2), value: layoutEngine.metrics.windowWidth)
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
