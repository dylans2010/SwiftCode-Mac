// Ported from Legacy `SwiftCode/UI/Styles/Styling/AdaptiveLayoutEngine.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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
import Combine

@MainActor
public final class AdaptiveLayoutEngine: ObservableObject {
    public static let shared = AdaptiveLayoutEngine()

    @Published public var metrics = AdaptiveWindowMetrics()

    private init() {}

    public func updateMetrics(width: CGFloat, height: CGFloat, scale: CGFloat, isFullscreen: Bool, appearance: AdaptiveWindowMetrics.Appearance = .light) {
        var newMetrics = AdaptiveWindowMetrics()
        newMetrics.windowWidth = width
        newMetrics.windowHeight = height
        newMetrics.contentWidth = width
        newMetrics.contentHeight = height
        newMetrics.displayScale = scale
        newMetrics.isFullscreen = isFullscreen
        newMetrics.currentBreakpoint = AdaptiveBreakpoint.breakpoint(for: width)
        newMetrics.appearance = appearance

        let widthChanged = abs(metrics.windowWidth - width) > 1.0
        let heightChanged = abs(metrics.windowHeight - height) > 1.0
        let fullscreenChanged = metrics.isFullscreen != isFullscreen
        let appearanceChanged = metrics.appearance != appearance

        if widthChanged || heightChanged || fullscreenChanged || appearanceChanged {
            metrics = newMetrics
        }
    }
}
