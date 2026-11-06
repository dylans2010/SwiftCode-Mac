import Foundation

/// Which String Catalog compiler a build uses (`specs/ide/string-catalog.md`,
/// "SwiftCode implementation"): Xcode's `xcstringstool`, which swift-build runs
/// for `.xcstrings` files, or SwiftCode's `swiftcode strings`, which accepts the same
/// `compile` and `generate-symbols` command lines.
///
/// The setting is `SWIFTCODE_STRINGS_COMPILER` = `xcstringstool` | `swiftcode`, as a
/// build setting on the command line or in the environment. The default is
/// `swiftcode` off macOS, and on macOS when the selected Xcode has no
/// `xcstringstool`. The `swiftcode` binary is `SWIFTCODE_STRINGS_TOOL` (setting or
/// environment), else the one `AssetCompilerHook` finds.
///
/// swift-build has no build setting naming the tool: it looks `xcstringstool`
/// up in its executable search paths, the first of which come from the
/// client's `__XCODE_BUILT_PRODUCTS_DIR_PATHS` environment variable. The hook
/// writes a wrapper named `xcstringstool` and puts its folder there, in the
/// environment of the swift-build process.
public enum StringsCompilerHook {
    public enum Choice: String, Sendable { case xcstringstool, swiftcode }

    public static let settingName = "SWIFTCODE_STRINGS_COMPILER"
    public static let toolSettingName = "SWIFTCODE_STRINGS_TOOL"
    public static let wrapperName = "xcstringstool"
    public static let searchPathVariable = "__XCODE_BUILT_PRODUCTS_DIR_PATHS"

    static func last(_ name: String, _ settings: [(String, String)]) -> String? { settings.last { $0.0 == name }?.1 }

    /// Whether the selected Xcode (`DEVELOPER_DIR`, else the `xcode-select`
    /// link, else `/Applications/Xcode.app`) has an `xcstringstool`.
    public static func xcodeHasStringsTool(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let fm = FileManager.default
        var dev = environment["DEVELOPER_DIR"]
        if dev == nil, let link = try? fm.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link") { dev = link }
        let base = dev ?? "/Applications/Xcode.app/Contents/Developer"
        return ["usr/bin/xcstringstool", "Toolchains/XcodeDefault.xctoolchain/usr/bin/xcstringstool"]
            .contains { fm.isExecutableFile(atPath: (base as NSString).appendingPathComponent($0)) }
    }

    public static func choice(settings: [(String, String)], environment: [String: String] = ProcessInfo.processInfo.environment) -> Choice {
        if let v = last(settingName, settings) ?? environment[settingName], let c = Choice(rawValue: v.lowercased()) { return c }
        #if os(macOS)
        return xcodeHasStringsTool(environment: environment) ? .xcstringstool : .swiftcode
        #else
        return .swiftcode
        #endif
    }

    public static func swiftcodeExecutable(settings: [(String, String)] = [], environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let p = last(toolSettingName, settings) ?? environment[toolSettingName] { return FileManager.default.isExecutableFile(atPath: p) ? p : nil }
        return AssetCompilerHook.swiftcodeExecutable(settings: settings, environment: environment)
    }

    /// `#!/bin/sh` that runs `swiftcode strings` with every argument.
    public static func wrapperScript(swiftcode: String) -> String {
        "#!/bin/sh\n# Written by SwiftCode: the String Catalog compiler swift-build runs (SWIFTCODE_STRINGS_COMPILER=swiftcode).\n"
            + "exec '\(swiftcode.replacingOccurrences(of: "'", with: "'\\''"))' strings \"$@\"\n"
    }

    /// The environment for the swift-build process: `base` with the
    /// wrapper's folder (`directory`) first in `__XCODE_BUILT_PRODUCTS_DIR_PATHS`.
    /// Nil when the choice is `xcstringstool` or no `swiftcode` is found.
    public static func environment(settings: [(String, String)], directory: URL,
                                   base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String]? {
        guard choice(settings: settings, environment: base) == .swiftcode,
              let swiftcode = swiftcodeExecutable(settings: settings, environment: base) else { return nil }
        let wrapper = directory.appendingPathComponent(wrapperName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(wrapperScript(swiftcode: swiftcode).utf8).write(to: wrapper, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        } catch {
            return nil
        }
        var env = base
        env[searchPathVariable] = directory.path + (base[searchPathVariable].map { ":" + $0 } ?? "")
        return env
    }

    /// Build-setting overrides that go with SwiftCode's compiler. Off macOS,
    /// swift-build cannot guess a `.strings` file's encoding, so files with
    /// no encoding of their own (the compiled tables) are read as UTF-8:
    /// `STRINGS_FILE_INPUT_ENCODING = $(InputFileTextEncoding:default=utf-8)`,
    /// unless the setting is given.
    public static func overrides(settings: [(String, String)], environment: [String: String] = ProcessInfo.processInfo.environment) -> [(String, String)] {
        #if os(macOS)
        return []
        #else
        guard choice(settings: settings, environment: environment) == .swiftcode, last("STRINGS_FILE_INPUT_ENCODING", settings) == nil else { return [] }
        return [("STRINGS_FILE_INPUT_ENCODING", "$(InputFileTextEncoding:default=utf-8)")]
        #endif
    }
}
