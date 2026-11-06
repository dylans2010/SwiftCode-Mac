import SwiftUI

/// Desktop-optimised view modifiers (Legacy
/// `SwiftCode/UI/Styles/Styling/MacDesktopOptimized.swift`, Dylan's own
/// code, ported under MIT).
///
/// Adapted: Legacy read the engine with `@EnvironmentObject`;
/// there is no Combine / `EnvironmentObject` in this codebase, so
/// the modifiers read it with `@Environment(AdaptiveLayoutEngine.self)`
/// (installed by `StylingBootstrap.configureEnvironment`). The
/// `.liquidGlass(...)` styles come from `SwiftCodeUI`'s `LiquidGlass`.
public struct MacDesktopOptimizedModifier: ViewModifier {
    @Environment(AdaptiveLayoutEngine.self) var layoutEngine

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.adaptiveMetrics, layoutEngine.metrics)
    }
}

public struct SourceControlEmbeddedModifier: ViewModifier {
    @Environment(AdaptiveLayoutEngine.self) var layoutEngine

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .liquidGlass(style: .standard, cornerRadius: 12)
            .clipped()
            .environment(\.adaptiveMetrics, layoutEngine.metrics)
    }
}

public struct SimulatorWorkspaceEmbeddedModifier: ViewModifier {
    @Environment(AdaptiveLayoutEngine.self) var layoutEngine

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
