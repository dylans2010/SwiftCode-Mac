import Foundation

public actor PreviewRenderer {
    public init() {}

    public struct ViewportMetrics: Sendable {
        public let width: Double
        public let height: Double
        public let scaleFactor: Double
        public let insetsTop: Double
        public let insetsBottom: Double
    }

    public func calculateViewport(forDevice name: String, isPortrait: Bool, globalScale: Double) async -> ViewportMetrics {
        var baseWidth = 393.0
        var baseHeight = 852.0
        var insetsTop = 59.0
        var insetsBottom = 34.0

        if name.contains("iPad") {
            baseWidth = 820.0
            baseHeight = 1180.0
            insetsTop = 24.0
            insetsBottom = 20.0
        } else if name.contains("Watch") {
            baseWidth = 198.0
            baseHeight = 242.0
            insetsTop = 0.0
            insetsBottom = 0.0
        } else if name.contains("Vision") {
            baseWidth = 1200.0
            baseHeight = 800.0
            insetsTop = 0.0
            insetsBottom = 0.0
        }

        let w = isPortrait ? baseWidth : baseHeight
        let h = isPortrait ? baseHeight : baseWidth

        return ViewportMetrics(
            width: w,
            height: h,
            scaleFactor: globalScale,
            insetsTop: insetsTop,
            insetsBottom: insetsBottom
        )
    }
}
