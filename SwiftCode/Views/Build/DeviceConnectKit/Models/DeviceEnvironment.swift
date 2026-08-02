import Foundation

public struct DeviceEnvironment: Codable, Sendable, Hashable {
    public var xcodePath: String?
    public var xcodeVersion: String?
    public var commandLineToolsVersion: String?
    public var macOSVersion: String
    public var hasiOSSDK: Bool
    public var hasSimulatorSDK: Bool
    public var isSigningSetup: Bool
    public var derivedDataPath: String?
    public var swiftVersion: String?

    public init(
        xcodePath: String? = nil,
        xcodeVersion: String? = nil,
        commandLineToolsVersion: String? = nil,
        macOSVersion: String = "macOS Unknown",
        hasiOSSDK: Bool = false,
        hasSimulatorSDK: Bool = false,
        isSigningSetup: Bool = false,
        derivedDataPath: String? = nil,
        swiftVersion: String? = nil
    ) {
        self.xcodePath = xcodePath
        self.xcodeVersion = xcodeVersion
        self.commandLineToolsVersion = commandLineToolsVersion
        self.macOSVersion = macOSVersion
        self.hasiOSSDK = hasiOSSDK
        self.hasSimulatorSDK = hasSimulatorSDK
        self.isSigningSetup = isSigningSetup
        self.derivedDataPath = derivedDataPath
        self.swiftVersion = swiftVersion
    }
}
