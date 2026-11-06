import Foundation
import SwiftCodeBuild

/// Which xcodebuild-compatible tool runs a project's or workspace's tests.
/// With SwiftCode's build system chosen (swift-build), tests go through
/// `swiftcodebuild`, which writes the coverage summary the test report's
/// Coverage page reads (`SWIFTCODE_COVERAGE_SUMMARY`). With xcodebuild chosen,
/// when no `swiftcodebuild` is found, or when the runner's tool was set
/// explicitly, the runner is left as it is.
public enum TestRunnerSelection {
    /// `SWIFTCODE_BUILD_TOOL`, else `swiftcodebuild` next to the running
    /// executable, else `swiftcodebuild` on `PATH`.
    public static func locateSwiftCodebuild(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        executableDirectory: String? = Bundle.main.executableURL?.deletingLastPathComponent().path) -> String? {
        let fm = FileManager.default
        if let p = environment["SWIFTCODE_BUILD_TOOL"], fm.isExecutableFile(atPath: p) { return p }
        if let d = executableDirectory, fm.isExecutableFile(atPath: d + "/swiftcodebuild") { return d + "/swiftcodebuild" }
        for dir in (environment["PATH"] ?? "").split(separator: ":") where fm.isExecutableFile(atPath: "\(dir)/swiftcodebuild") {
            return "\(dir)/swiftcodebuild"
        }
        return nil
    }

    /// The runner for a preference: `swiftcodebuild` replaces xcodebuild for
    /// swift-build when it can be found.
    public static func runner(_ base: TestRunner, preference: BuildSystemPreference, locate: () -> String? = { locateSwiftCodebuild() }) -> TestRunner {
        // A runner whose tool was set explicitly (tests, stubs) is kept.
        guard preference == .swiftBuild, base.xcodebuild == TestRunner().xcodebuild, let tool = locate() else { return base }
        var r = base
        r.xcodebuild = [tool]
        return r
    }
}
