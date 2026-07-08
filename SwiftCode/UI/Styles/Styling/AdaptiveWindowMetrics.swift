import SwiftUI

public struct AdaptiveWindowMetrics: Sendable {
    public var windowWidth: CGFloat = 0
    public var windowHeight: CGFloat = 0
    public var contentWidth: CGFloat = 0
    public var contentHeight: CGFloat = 0
    public var displayScale: CGFloat = 1.0
    public var isFullscreen: Bool = false
    public var currentBreakpoint: AdaptiveBreakpoint = .regularDesktop

    public init() {}
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
