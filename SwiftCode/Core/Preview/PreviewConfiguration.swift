import Foundation

/// Defines options and orientations used to render SwiftUI previews.
public struct PreviewConfiguration: Codable, Sendable, Hashable {
    public enum PreviewPlatform: String, Codable, CaseIterable, Sendable {
        case iOS
        case watchOS
        case tvOS
        case macOS
        case visionOS
    }

    public enum DeviceOrientation: String, Codable, CaseIterable, Sendable {
        case portrait
        case landscapeLeft
        case landscapeRight
        case portraitUpsideDown
    }

    public enum InterfaceStyle: String, Codable, CaseIterable, Sendable {
        case light
        case dark
    }

    public var platform: PreviewPlatform
    public var deviceName: String
    public var orientation: DeviceOrientation
    public var interfaceStyle: InterfaceStyle
    public var zoomScale: Double // e.g. 1.0, 0.75, 0.5
    public var showSafeArea: Bool

    public init(
        platform: PreviewPlatform = .iOS,
        deviceName: String = "iPhone 16 Pro",
        orientation: DeviceOrientation = .portrait,
        interfaceStyle: InterfaceStyle = .light,
        zoomScale: Double = 1.0,
        showSafeArea: Bool = true
    ) {
        self.platform = platform
        self.deviceName = deviceName
        self.orientation = orientation
        self.interfaceStyle = interfaceStyle
        self.zoomScale = zoomScale
        self.showSafeArea = showSafeArea
    }

    public static let `default` = PreviewConfiguration()
}
