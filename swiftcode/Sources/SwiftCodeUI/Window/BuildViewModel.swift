import Foundation
import Observation
import SwiftCodeBuild
import SwiftCodeSDK
import SwiftCodeIDECore

@Observable
@MainActor
public class BuildViewModel {
    public var isBuilding = false
    public var buildLog = ""
    public var diagnostics: [BuildDiagnostic] = []

    public init() {}

    public func build(projectURL: URL, scheme: String) async {
        isBuilding = true
        buildLog = ""
        diagnostics = []

        await XcodeBuildManager.shared.runBuild(projectURL: projectURL, scheme: scheme, configuration: "Debug")
        isBuilding = false
        buildLog = XcodeBuildManager.shared.buildLogs.joined(separator: "\n")
        diagnostics = BuildDiagnosticsParser().parse(output: buildLog).map { diag in
            BuildDiagnostic(
                severity: {
                    switch diag.severity {
                    case .error: return .error
                    case .warning: return .warning
                    case .note, .suggestion: return .note
                    }
                }(),
                filePath: diag.location?.filePath ?? "",
                line: diag.location?.line ?? 0,
                column: diag.location?.column ?? 0,
                message: diag.message
            )
        }
        if XcodeBuildManager.shared.currentStatus == .succeeded {
            LoggingTool.info("Build finished: true")
        } else {
            LoggingTool.error("Build failed: status \(XcodeBuildManager.shared.currentStatus.rawValue)")
        }
    }
}
