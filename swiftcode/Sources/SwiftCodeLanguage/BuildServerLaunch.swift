import Foundation
import SwiftCodeDebug
import SwiftCodeSubprocess

public enum BuildServerLaunch {
    public static let defaultsKey = "SwiftCode.buildServer"

    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 defaults: UserDefaults = .standard) -> Bool {
        if let v = environment["SWIFTCODE_BUILD_SERVER"] { return !["0", "no", "false", "off"].contains(v.lowercased()) }
        return defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                              executableURL: URL? = Bundle.main.executableURL) -> String? {
        let fm = FileManager.default
        if let p = environment["SWIFTCODE_BSP"], fm.isExecutableFile(atPath: p) { return p }
        if let dir = executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            for c in [dir.appendingPathComponent("swiftcode-bsp"), dir.deletingLastPathComponent().appendingPathComponent("Helpers/swiftcode-bsp")]
            where fm.isExecutableFile(atPath: c.path) {
                return c.path
            }
        }
        for dir in (environment["PATH"] ?? "").split(separator: ":") where fm.isExecutableFile(atPath: "\(dir)/swiftcode-bsp") {
            return "\(dir)/swiftcode-bsp"
        }
        return nil
    }

    public static let initializationOptions: JSON = ["bypassWorkspaceTrust": true]

    public static func argv(server: String, container: URL, scheme: String? = nil, destination: String? = nil) -> [String] {
        var a = ["serve", container.standardizedFileURL.path]
        if let scheme { a += ["--scheme", scheme] }
        if let destination { a += ["--destination", destination] }
        return HostTool.commandOnHost(tool: server, arguments: a)
    }

    public static func configJSON(argv: [String]) -> JSON {
        [
            "name": "SwiftCode",
            "version": "0.1",
            "bspVersion": "2.2.0",
            "languages": ["swift", "c", "objective-c", "cpp", "objective-cpp"],
            "argv": .array(argv.map(JSON.string)),
        ]
    }

    public static func workspaceFolder(for container: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home = environment["HOME"] ?? NSHomeDirectory()
        #if os(macOS)
        let root = home + "/Library/Caches/SwiftCode/BuildServer"
        #else
        let root = (environment["XDG_CACHE_HOME"] ?? home + "/.cache") + "/swiftcode/build-server"
        #endif
        let path = container.standardizedFileURL.path
        let name = container.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "_")
        return URL(fileURLWithPath: root).appendingPathComponent("\(name)-\(hash(path))")
    }

    @discardableResult
    public static func writeConfig(argv: [String], into folder: URL) throws -> URL {
        let dir = folder.appendingPathComponent(".bsp")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("swiftcode.json")
        try configJSON(argv: argv).encoded().write(to: file, options: .atomic)
        return file
    }

    public static func prepareWorkspaceFolder(container: URL, scheme: String? = nil, destination: String? = nil,
                                              environment: [String: String] = ProcessInfo.processInfo.environment,
                                              defaults: UserDefaults = .standard) -> URL? {
        guard ["xcodeproj", "xcworkspace"].contains(container.pathExtension), isEnabled(environment: environment, defaults: defaults),
              let server = locate(environment: environment) else { return nil }
        let folder = workspaceFolder(for: container, environment: environment)
        do {
            try writeConfig(argv: argv(server: server, container: container, scheme: scheme, destination: destination), into: folder)
        } catch {
            return nil
        }
        return folder
    }

    static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", h)
    }
}
