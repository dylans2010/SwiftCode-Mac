import Foundation

/// Which asset catalog compiler a build uses (`specs/formats/assets-car.md`,
/// "SwiftCode implementation"): Apple's `actool`, which swift-build runs as
/// `$(ASSETCATALOG_EXEC)`, or SwiftCode's own `swiftcode assets compile`, which
/// accepts the same command line.
///
/// The setting is `SWIFTCODE_ASSET_COMPILER` = `actool` | `swiftcode`, as a build
/// setting on the command line (`swiftcode build … SWIFTCODE_ASSET_COMPILER=swiftcode`,
/// `swiftcodebuild … SWIFTCODE_ASSET_COMPILER=swiftcode`) or in the environment. The
/// default is `actool` on macOS and `swiftcode` elsewhere. The `swiftcode` binary is
/// `SWIFTCODE_ASSETS_TOOL` (setting or environment), else the `swiftcode` next to the
/// running executable, else the first on `PATH`. A project or command line
/// that sets `ASSETCATALOG_EXEC` itself is left alone.
public enum AssetCompilerHook {
    public enum Choice: String, Sendable { case actool, swiftcode }

    public static let settingName = "SWIFTCODE_ASSET_COMPILER"
    public static let toolSettingName = "SWIFTCODE_ASSETS_TOOL"
    /// The name of the wrapper the hook writes (swift-build takes one path,
    /// and reads the tool's version under `com.apple.<file name>.version`).
    public static let wrapperName = "actool"

    static func last(_ name: String, _ settings: [(String, String)]) -> String? { settings.last { $0.0 == name }?.1 }

    public static func choice(settings: [(String, String)], environment: [String: String] = ProcessInfo.processInfo.environment) -> Choice {
        if let v = last(settingName, settings) ?? environment[settingName], let c = Choice(rawValue: v.lowercased()) { return c }
        #if os(macOS)
        return .actool
        #else
        return .swiftcode
        #endif
    }

    /// The `swiftcode` executable to run, or nil when none is found.
    public static func swiftcodeExecutable(settings: [(String, String)] = [], environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let fm = FileManager.default
        if let p = last(toolSettingName, settings) ?? environment[toolSettingName] { return fm.isExecutableFile(atPath: p) ? p : nil }
        let me = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let sibling = me.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("swiftcode").path
        if fm.isExecutableFile(atPath: sibling) { return sibling }
        for dir in (environment["PATH"] ?? "").split(separator: ":") where fm.isExecutableFile(atPath: "\(dir)/swiftcode") { return "\(dir)/swiftcode" }
        return nil
    }

    /// `#!/bin/sh` that runs `swiftcode assets compile` with every argument.
    public static func wrapperScript(swiftcode: String) -> String {
        "#!/bin/sh\n# Written by SwiftCode: the asset catalog compiler swift-build runs (SWIFTCODE_ASSET_COMPILER=swiftcode).\n"
            + "exec '\(swiftcode.replacingOccurrences(of: "'", with: "'\\''"))' assets compile \"$@\"\n"
    }

    /// The build-setting overrides that make swift-build run SwiftCode's
    /// compiler: `ASSETCATALOG_EXEC` naming a wrapper written into
    /// `directory`. Empty when the choice is `actool`, when
    /// `ASSETCATALOG_EXEC` is already set, or when no `swiftcode` is found.
    public static func overrides(settings: [(String, String)], directory: URL,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) -> [(String, String)] {
        guard choice(settings: settings, environment: environment) == .swiftcode, last("ASSETCATALOG_EXEC", settings) == nil,
              let swiftcode = swiftcodeExecutable(settings: settings, environment: environment) else { return [] }
        let wrapper = directory.appendingPathComponent(wrapperName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(wrapperScript(swiftcode: swiftcode).utf8).write(to: wrapper, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        } catch {
            return []
        }
        return [("ASSETCATALOG_EXEC", wrapper.path)]
    }
}
