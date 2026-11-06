// Ported from Legacy `SwiftCode/UI/Styles/Styling/AdaptiveWindowMetrics.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

public struct AdaptiveWindowMetrics: Sendable {
    public var windowWidth: CGFloat = 0
    public var windowHeight: CGFloat = 0
    public var contentWidth: CGFloat = 0
    public var contentHeight: CGFloat = 0
    public var displayScale: CGFloat = 1.0
    public var isFullscreen: Bool = false
    public var currentBreakpoint: AdaptiveBreakpoint = .regularDesktop
    public var appearance: Appearance = .light

    public enum Appearance: Sendable {
        case light
        case dark
    }

    public init() {}

    // Convenience computed properties for adaptive layout
    public var standardPadding: CGFloat { currentBreakpoint.standardPadding }
    public var standardSpacing: CGFloat { currentBreakpoint.standardSpacing }
    public var isCompact: Bool { currentBreakpoint == .compactDesktop }
}

public struct AdaptiveWindowMetricsKey: EnvironmentKey {
    public static let defaultValue = AdaptiveWindowMetrics()
}

extension EnvironmentValues {
    public var adaptiveMetrics: AdaptiveWindowMetrics {
        get { self[AdaptiveWindowMetricsKey.self] }
        set { self[AdaptiveWindowMetricsKey.self] = newValue }
    }
}
