import Foundation

public struct ConnectedDevice: Identifiable, Codable, Sendable, Hashable {
    public var id: String { udid }
    public let name: String
    public let model: String
    public let productType: String
    public let platform: String
    public let osVersion: String
    public let buildVersion: String
    public let architecture: String
    public let udid: String

    // Connection
    public let isConnected: Bool
    public let isAvailable: Bool
    public let isBusy: Bool
    public let isOffline: Bool
    public let isWireless: Bool
    public let isUSB: Bool

    // Development Mode
    public let isDeveloperModeEnabled: Bool
    public let isTrusted: Bool
    public let isDeploymentSupported: Bool
    public let isSigningCompatible: Bool

    public init(
        name: String,
        model: String,
        productType: String,
        platform: String,
        osVersion: String,
        buildVersion: String,
        architecture: String,
        udid: String,
        isConnected: Bool = true,
        isAvailable: Bool = true,
        isBusy: Bool = false,
        isOffline: Bool = false,
        isWireless: Bool = false,
        isUSB: Bool = true,
        isDeveloperModeEnabled: Bool = true,
        isTrusted: Bool = true,
        isDeploymentSupported: Bool = true,
        isSigningCompatible: Bool = true
    ) {
        self.name = name
        self.model = model
        self.productType = productType
        self.platform = platform
        self.osVersion = osVersion
        self.buildVersion = buildVersion
        self.architecture = architecture
        self.udid = udid
        self.isConnected = isConnected
        self.isAvailable = isAvailable
        self.isBusy = isBusy
        self.isOffline = isOffline
        self.isWireless = isWireless
        self.isUSB = isUSB
        self.isDeveloperModeEnabled = isDeveloperModeEnabled
        self.isTrusted = isTrusted
        self.isDeploymentSupported = isDeploymentSupported
        self.isSigningCompatible = isSigningCompatible
    }
}
