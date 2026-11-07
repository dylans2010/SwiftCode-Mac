import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif
import Observation

@MainActor
@Observable
public final class DeviceUtilityManager {
    public static let shared = DeviceUtilityManager()
    private init() {}

    public func isAppleIntelligenceSupported() -> Bool { getCapabilityLevel() != .unsupported }

    public func getDeviceModel() -> String {
#if canImport(Darwin)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
#else
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
#endif
    }

    public func getOSVersion() -> String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    public func getCapabilityLevel() -> OnDeviceCapabilities.CapabilityLevel {
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .full
            case .unavailable(let reason):
                if case .deviceNotEligible = reason {
                    return .unsupported
                }
                return .limited
            @unknown default:
                return .limited
            }
        }
#endif
        return .unsupported
    }

    public func currentCapabilities() -> OnDeviceCapabilities {
        let level = getCapabilityLevel()
        let reason: String?
        switch level {
        case .full:
            reason = nil
        case .limited:
            reason = "On-device inference is limited right now: Apple Intelligence is turned off or the on-device model is still downloading."
        case .unsupported:
            reason = "Apple Foundation Models is not available on this device. It needs macOS 26 or later on an Apple Intelligence-capable Mac, with Apple Intelligence turned on."
        }
        return OnDeviceCapabilities(
            isAppleIntelligenceSupported: level != .unsupported,
            isOfflineCapable: true,
            supportedTasks: AppleIntelligenceService.TaskType.allCases.filter { level == .full || $0 != .codeAssist },
            capabilityLevel: level,
            reasonIfUnavailable: reason
        )
    }
}
