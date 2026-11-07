import Foundation

public enum StringsCompilerHook {
    public enum Choice: String, Sendable { case xcstringstool, swiftcode }

    public static let settingName = "SWIFTCODE_STRINGS_COMPILER"
    public static let toolSettingName = "SWIFTCODE_STRINGS_TOOL"
    public static let wrapperName = "xcstringstool"
    public static let searchPathVariable = "__XCODE_BUILT_PRODUCTS_DIR_PATHS"

    static func last(_ name: String, _ settings: [(String, String)]) -> String? { settings.last { $0.0 == name }?.1 }

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

    public static func wrapperScript(swiftcode: String) -> String {
        "#!/bin/sh\n# Written by SwiftCode: the String Catalog compiler swift-build runs (SWIFTCODE_STRINGS_COMPILER=swiftcode).\n"
            + "exec '\(swiftcode.replacingOccurrences(of: "'", with: "'\\''"))' strings \"$@\"\n"
    }

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

    public static func overrides(settings: [(String, String)], environment: [String: String] = ProcessInfo.processInfo.environment) -> [(String, String)] {
        #if os(macOS)
        return []
        #else
        guard choice(settings: settings, environment: environment) == .swiftcode, last("STRINGS_FILE_INPUT_ENCODING", settings) == nil else { return [] }
        return [("STRINGS_FILE_INPUT_ENCODING", "$(InputFileTextEncoding:default=utf-8)")]
        #endif
    }
}
