// Adapted from SwiftCode-Legacy SwiftCode/Core/Preview/PreviewConfiguration.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct PreviewConfiguration: Codable, Hashable, Sendable {
    public var deviceName: String
    public var isPortrait: Bool
    public var isDarkMode: Bool
    public var scale: Double // e.g. 0.5, 0.75, 1.0, 1.25
    public var dynamicTypeSize: String // Small, Medium, Large, ExtraLarge

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
