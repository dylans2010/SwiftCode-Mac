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

        if metrics.windowWidth != width || metrics.windowHeight != height || metrics.isFullscreen != isFullscreen || metrics.appearance != appearance {
            metrics = newMetrics
        }
    }
}
