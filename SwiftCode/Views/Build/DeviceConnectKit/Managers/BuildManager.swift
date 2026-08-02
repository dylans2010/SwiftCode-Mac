import Foundation
import Observation

@Observable
@MainActor
public final class BuildManager {
    public static let shared = BuildManager()

    public private(set) var buildStatus: BuildStatus = .idle
    public private(set) var errors: [BuildParser.ParsedIssue] = []
    public private(set) var warnings: [BuildParser.ParsedIssue] = []
    public private(set) var buildDuration: TimeInterval = 0

    private init() {}

    public func startBuild() {
        buildStatus = .building
        errors.removeAll()
        warnings.removeAll()
        buildDuration = 0
    }

    public func finishBuild(success: Bool, rawLogs: String, duration: TimeInterval) {
        buildStatus = success ? .succeeded : .failed
        buildDuration = duration

        let issues = BuildParser.parseXcodebuildOutput(rawLogs)
        self.errors = issues.errors
        self.warnings = issues.warnings
    }
}
