// Ported from Legacy `SwiftCode/ViewModels/BuildViewModel.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Landed by fix W-V2 (A6 slice: BuildToolbarView declares `@State var viewModel: BuildViewModel`).
// REWIRED, not verbatim: Legacy's build() used XcodeBuildService + BuildLogLineParser,
// neither of which exists anywhere — not even in Legacy itself. The production
// equivalents are XcodeBuildManager.runBuild(projectURL:scheme:configuration:) (the
// real xcodebuild driver, same target family) and BuildDiagnosticsParser (parses the
// finished log into diagnostics). Behaviour difference, stated plainly: Legacy
// streamed log lines and parsed diagnostics per line as they arrived; here the
// diagnostics are parsed from the finished log, so they appear at completion rather
// than streaming. End state (isBuilding / buildLog / diagnostics / success) is the same.
// The toolbar does not call build() today (the viewModel is declared but unused);
// this keeps the type real and callable.

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
