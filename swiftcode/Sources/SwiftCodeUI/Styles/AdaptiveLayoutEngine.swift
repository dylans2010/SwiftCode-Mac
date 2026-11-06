import SwiftUI
import Observation

/// Adaptive layout engine (Legacy
/// `SwiftCode/UI/Styles/Styling/AdaptiveLayoutEngine.swift`, Dylan's own
/// code, ported under MIT).
///
/// Adapted: Legacy used `ObservableObject` + Combine (`@Published`,
/// `@EnvironmentObject`); no Combine exists anywhere in
/// `swiftcode-ide` / `SwiftCodeUI` / `SwiftCodeIDECore`, so this is
/// `@Observable` (Observation framework) and is read with
/// `@Environment(AdaptiveLayoutEngine.self)` (see
/// `MacDesktopOptimized.swift`) and installed with
/// `.environment(AdaptiveLayoutEngine.shared)` (see
/// `StylingBootstrap.configureEnvironment`). The update rule is
/// Legacy's: metrics are replaced only when the width/height moved
/// by more than 1pt, fullscreen changed, or the appearance changed.
@Observable
@MainActor
public final class AdaptiveLayoutEngine {
    public static let shared = AdaptiveLayoutEngine()

    public var metrics = AdaptiveWindowMetrics()

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
