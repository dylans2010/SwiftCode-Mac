import Foundation
import SwiftCodeBuild
import SwiftCodeWorkspace

extension SchemeDiagnostics {
    public var buildSettings: [(String, String)] {
        var s: [(String, String)] = []
        if addressSanitizer { s.append(("ENABLE_ADDRESS_SANITIZER", "YES")) }
        if threadSanitizer { s.append(("ENABLE_THREAD_SANITIZER", "YES")) }
        if undefinedBehaviorSanitizer { s.append(("ENABLE_UNDEFINED_BEHAVIOR_SANITIZER", "YES")) }
        return s
    }

    public func applyLaunchEnvironment(_ env: inout [String: String]) {
        guard addressSanitizer, stackUseAfterReturn else { return }
        let option = "detect_stack_use_after_return=1"
        if let existing = env["ASAN_OPTIONS"], !existing.isEmpty {
            if !existing.contains("detect_stack_use_after_return") { env["ASAN_OPTIONS"] = existing + ":" + option }
        } else {
            env["ASAN_OPTIONS"] = option
        }
    }

    public static func schemeAction(for action: BuildRequest.Action) -> String? {
        switch action {
        case .clean: nil
        case .test, .buildForTesting, .testWithoutBuilding: "TestAction"
        case .build, .analyze: "LaunchAction"
        }
    }
}
