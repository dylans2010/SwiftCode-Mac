import SwiftUI

public struct MacDesktopOptimizedModifier: ViewModifier {
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
}
