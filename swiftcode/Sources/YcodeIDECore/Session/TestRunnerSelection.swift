import Foundation
import YcodeBuild

public enum TestRunnerSelection {
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

    public static func runner(_ base: TestRunner, preference: BuildSystemPreference, locate: () -> String? = { locateSwiftCodebuild() }) -> TestRunner {
        guard preference == .swiftBuild, base.xcodebuild == TestRunner().xcodebuild, let tool = locate() else { return base }
        var r = base
        r.xcodebuild = [tool]
        return r
    }
}
