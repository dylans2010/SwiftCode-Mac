// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/On Device Intelligence/OnDeviceCapabilities.swift
//   (Legacy commit d51a8f0d)
//
// Ported unchanged in shape. The level itself is computed by
// `DeviceUtilityManager` from the live Foundation Models availability,
// not from a hardcoded OS-version table (see that file).

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
