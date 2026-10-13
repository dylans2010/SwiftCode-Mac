import Foundation
import DiagnosticsKit
import BuildKit
import WorkspaceKit

public struct ToolCheckResult: Sendable {
    public let name: String
    public let available: Bool
    public let path: String
    public let version: String?
}

public struct DoctorReport: Sendable {
    public let osVersion: String
    public let architecture: String
    public let sdkRoot: String
    public let sdkRootExists: Bool
    public let tools: [ToolCheckResult]
    public let diagnostics: [Diagnostic]
    public let isHealthy: Bool
}

public final class SDKDoctor: Sendable {
    public init() {}

    public func diagnose(sdkRoot: String? = nil) -> DoctorReport {
        let config = SDKConfiguration.standard(sdkRoot: sdkRoot)
        let toolchain = Toolchain.standard
        let engine = DiagnosticEngine()

        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        let arch = "x86_64 (Intel)"
        #else
        let arch = "unknown"
        #endif

        let rootExists = FileManager.default.fileExists(atPath: config.sdkRoot)
        if !rootExists {
            engine.emit(
                code: .workspacePathNotFound,
                severity: .warning,
                message: "SDK Root not found at '\(config.sdkRoot)'",
                remediation: "Set SWIFTCODE_SDK_ROOT or verify installation path"
            )
        }

        var toolResults: [ToolCheckResult] = []
        let discovered = toolchain.discoverTools()
        for name in ["swift", "swiftc", "xcodebuild", "clang", "git", "node", "npm", "python3"] {
            if let info = discovered[name], info.isAvailable {
                toolResults.append(ToolCheckResult(name: name, available: true, path: info.path, version: info.version))
            } else {
                toolResults.append(ToolCheckResult(name: name, available: false, path: "", version: nil))
                let sev: DiagnosticSeverity = (name == "swift" || name == "git") ? .error : .warning
                engine.emit(
                    code: .buildToolMissing,
                    severity: sev,
                    message: "Required developer tool '\(name)' not found in standard paths",
                    remediation: "Install via Command Line Tools ('xcode-select --install') or Homebrew"
                )
            }
        }

        let isHealthy = !engine.hasErrors
        return DoctorReport(
            osVersion: osVer,
            architecture: arch,
            sdkRoot: config.sdkRoot,
            sdkRootExists: rootExists,
            tools: toolResults,
            diagnostics: engine.allDiagnostics,
            isHealthy: isHealthy
        )
    }
}
