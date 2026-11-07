import Foundation

public struct PreviewConfiguration: Codable, Hashable, Sendable {
    public var deviceName: String
    public var isPortrait: Bool
    public var isDarkMode: Bool
    public var scale: Double
    public var dynamicTypeSize: String

    public init(
        deviceName: String = "iPhone 16 Pro",
        isPortrait: Bool = true,
        isDarkMode: Bool = false,
        scale: Double = 1.0,
        dynamicTypeSize: String = "Medium"
    ) {
        self.deviceName = deviceName
        self.isPortrait = isPortrait
        self.isDarkMode = isDarkMode
        self.scale = scale
        self.dynamicTypeSize = dynamicTypeSize
    }
}
