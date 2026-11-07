import Foundation

public enum SwiftCodeRelease {
    public static let version = "1.0.0-beta.2"
    public static let marketingVersion = "1.0.0 Beta"

    public static func versionLine(tool: String) -> String { "\(tool) \(version)" }

    public static func handleVersionFlag(tool: String, arguments: [String] = CommandLine.arguments) {
        guard arguments.count == 2, arguments[1] == "--version" else { return }
        print(versionLine(tool: tool))
        exit(0)
    }
}

extension SwiftCodeRelease {
    public static func pathWithBundledHelpers(executable: URL, path: String?, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        let helpers = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Helpers").path
        guard fileExists(helpers) else { return nil }
        return helpers + ":" + (path ?? "/usr/bin:/bin:/usr/sbin:/sbin")
    }

    public static func packageEnvironment(executable: URL, environment: [String: String],
                                          fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String: String] {
        let bin = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        let wrappers = bin.deletingLastPathComponent().appendingPathComponent("libexec/swiftcode-host").path
        guard fileExists(wrappers) else { return [:] }
        var first = [bin.path]
        if !(environment["FLATPAK_ID"] ?? "").isEmpty { first.insert(wrappers, at: 0) }
        let path = environment["PATH"] ?? "/usr/bin:/bin"
        guard !path.hasPrefix(first.joined(separator: ":") + ":") else { return [:] }
        return ["PATH": (first + [path]).joined(separator: ":"),
                "SWIFTCODE": bin.appendingPathComponent("swiftcode").path,
                "SWIFTCODE_SWB": bin.appendingPathComponent("swiftcode-swb").path].filter { environment[$0.key] == nil || $0.key == "PATH" }
    }

    public static func adoptBundledHelpers() {
        guard let exe = Bundle.main.executableURL else { return }
        let environment = ProcessInfo.processInfo.environment
        #if os(macOS)
        if let path = pathWithBundledHelpers(executable: exe, path: environment["PATH"]) { setenv("PATH", path, 1) }
        #else
        for (name, value) in packageEnvironment(executable: exe, environment: environment) { setenv(name, value, 1) }
        #endif
    }
}
