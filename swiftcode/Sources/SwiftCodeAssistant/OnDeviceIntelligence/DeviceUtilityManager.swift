// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/On Device Intelligence/DeviceUtilityManager.swift
//   (Legacy commit d51a8f0d)
//
// Adaptation — capability detection. Legacy derived the capability
// level from a hardcoded OS-version heuristic (macOS 18 → full,
// 17 → limited, older → unsupported). That heuristic is not a real
// capability check, and its thresholds are wrong for the destination:
// the real on-device model is Apple Foundation Models, which ships
// with macOS 26 / iOS 26 (`FoundationModelsProvider`). So the level
// here is read live from `SystemLanguageModel.default.availability`
// behind the same `#if canImport(FoundationModels)` + `#available`
// gates `FoundationModelsProvider` uses — `.available` → full, an
// unavailable reason of `.deviceNotEligible` → unsupported, any other
// unavailable reason (Apple Intelligence off, model still downloading)
// → limited. Where the framework is absent the level is unsupported
// with a reason naming the macOS 26 requirement. `getDeviceModel`
// (sysctl `hw.model`) and `getOSVersion` (ProcessInfo) are Legacy's
// real readings, kept; the sysctl call is Darwin-gated with the same
// uname fallback `OfflineModels.swift` uses on Linux.

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
        // Linux: the machine identifier from uname, as in OfflineModels.swift.
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
