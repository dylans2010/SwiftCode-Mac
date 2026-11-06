import SwiftUI

/// Styling bootstrap (Legacy
/// `SwiftCode/UI/Styles/Styling/StylingBootstrap.swift`, Dylan's own
/// code, ported under MIT).
///
/// Adapted: Legacy installed the engine with `.environmentObject`;
/// this installs it with `.environment(AdaptiveLayoutEngine.shared)`
/// (Observation, no Combine). `StylingRegistry` is ported alongside
/// (`StylingRegistry.swift`); its `registerDefaults()` is an empty
/// no-op in Legacy and stays one.
///
/// Wiring: call `StylingBootstrap.initialize()` once at app start,
/// and wrap the root view with `configureEnvironment(_:)` at the App
/// entry — the layout engine and liquid-glass environment must be
/// installed above every view that uses `.macDesktopOptimized()` or
/// `.liquidGlass(...)`.
public struct StylingBootstrap {
    public static func initialize() {
        StylingRegistry.shared.registerDefaults()
    }

    @MainActor
    public static func configureEnvironment<V: View>(_ view: V) -> some View {
        view
            .environment(AdaptiveLayoutEngine.shared)
            .liquidGlassEnabled(true)
            .liquidGlassStyle(.standard)
    }
}
