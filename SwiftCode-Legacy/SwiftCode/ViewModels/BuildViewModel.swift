import Foundation
import Observation

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

        do {
            let success = try await XcodeBuildService.shared.build(projectURL: projectURL, scheme: scheme, configuration: .debug) { line in
                Task { @MainActor in
                    self.buildLog += line
                    if let diag = BuildLogLineParser.shared.parse(line) {
                        self.diagnostics.append(diag)
                    }
                }
            }
            LoggingTool.info("Build finished: \(success)")
        } catch {
            LoggingTool.error("Build failed: \(error)")
        }
        isBuilding = false
    }
}
