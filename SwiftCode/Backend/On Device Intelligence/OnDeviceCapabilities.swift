import Foundation

struct OnDeviceCapabilities: Codable, Hashable {
    enum CapabilityLevel: String, Codable {
        case unsupported
        case limited
        case full
    }

    var isAppleIntelligenceSupported: Bool
    var isOfflineCapable: Bool
    var supportedTasks: [AppleIntelligenceService.TaskType]
    var capabilityLevel: CapabilityLevel
    var reasonIfUnavailable: String?
}
