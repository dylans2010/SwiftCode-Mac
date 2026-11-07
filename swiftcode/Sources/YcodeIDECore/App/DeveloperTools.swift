import Foundation
import YcodeSubprocess

public enum DeveloperTools {
    public struct Tool: Equatable, Sendable {
        public var name: String
        public var url: URL
    }

    public static let order = ["Instruments", "Device Hub", "Icon Composer", "Accessibility Inspector", "FileMerge", "Create ML"]

    public static func tools(inDeveloperDirectory dir: URL, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Tool] {
        order.compactMap { name in
            let url = dir.appendingPathComponent("Applications").appendingPathComponent(name + ".app")
            return exists(url.path) ? Tool(name: name, url: url) : nil
        }
    }

    public static func activeDeveloperDirectory() -> URL? {
        if let d = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !d.isEmpty { return URL(fileURLWithPath: d) }
        MainThreadGuard.blockingCall("xcode-select -p")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["-p"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !s.isEmpty ? URL(fileURLWithPath: s) : nil
    }

    @MainActor public static var installed: [Tool] {
        if let cached { return cached }
        prefetch()
        return []
    }

    @MainActor private static var cached: [Tool]?

    nonisolated static func lookUp() -> [Tool] { activeDeveloperDirectory().map { tools(inDeveloperDirectory: $0) } ?? [] }

    @MainActor public static func prefetch() {
        guard cached == nil, !fetching else { return }
        fetching = true
        Task {
            let list = await Task.detached { lookUp() }.value
            cached = list
            fetching = false
        }
    }

    @MainActor private static var fetching = false
}
