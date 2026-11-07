import Foundation

public struct OnDeviceCapabilities: Codable, Hashable {
    public enum CapabilityLevel: String, Codable {
        case unsupported
        case limited
        case full
    }

    public var isAppleIntelligenceSupported: Bool
    public var isOfflineCapable: Bool
    public var supportedTasks: [AppleIntelligenceService.TaskType]
    public var capabilityLevel: CapabilityLevel
    public var reasonIfUnavailable: String?

    public init(
        isAppleIntelligenceSupported: Bool,
        isOfflineCapable: Bool,
        supportedTasks: [AppleIntelligenceService.TaskType],
        capabilityLevel: CapabilityLevel,
        reasonIfUnavailable: String?
    ) {
        self.isAppleIntelligenceSupported = isAppleIntelligenceSupported
        self.isOfflineCapable = isOfflineCapable
        self.supportedTasks = supportedTasks
        self.capabilityLevel = capabilityLevel
        self.reasonIfUnavailable = reasonIfUnavailable
    }
}
