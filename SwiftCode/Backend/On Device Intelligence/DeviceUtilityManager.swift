import Foundation
import UIKit

@MainActor
final class DeviceUtilityManager: ObservableObject {
    static let shared = DeviceUtilityManager()
    private init() {}

    func isAppleIntelligenceSupported() -> Bool { getCapabilityLevel() != .unsupported }
    func getDeviceModel() -> String { UIDevice.current.model }
    func getiOSVersion() -> String { UIDevice.current.systemVersion }

    func getCapabilityLevel() -> OnDeviceCapabilities.CapabilityLevel {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion >= 18 { return .full }
        if version.majorVersion >= 17 { return .limited }
        return .unsupported
    }

    func currentCapabilities() -> OnDeviceCapabilities {
        let level = getCapabilityLevel()
        return OnDeviceCapabilities(
            isAppleIntelligenceSupported: level != .unsupported,
            isOfflineCapable: true,
            supportedTasks: AppleIntelligenceService.TaskType.allCases.filter { level == .full || $0 != .codeAssist },
            capabilityLevel: level,
            reasonIfUnavailable: level == .unsupported ? "Apple Intelligence is not available on this device" : nil
        )
    }
}
