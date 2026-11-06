// Adapted from SwiftCode-Legacy SwiftCode/Core/Simulator/SimulatorConfiguration.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct SimulatorConfiguration: Codable, Hashable, Sendable {
    public var preferredOrientation: String // Portrait, Landscape
    public var connectHardwareKeyboard: Bool
    public var showFrameRateCounter: Bool
    public var defaultRuntimePlatform: String // iOS, tvOS, watchOS, visionOS
    public var maxConsoleLogLines: Int

    public init(
        preferredOrientation: String = "Portrait",
        connectHardwareKeyboard: Bool = true,
        showFrameRateCounter: Bool = false,
        defaultRuntimePlatform: String = "iOS",
        maxConsoleLogLines: Int = 1000
    ) {
        self.preferredOrientation = preferredOrientation
        self.connectHardwareKeyboard = connectHardwareKeyboard
        self.showFrameRateCounter = showFrameRateCounter
        self.defaultRuntimePlatform = defaultRuntimePlatform
        self.maxConsoleLogLines = maxConsoleLogLines
    }
}
