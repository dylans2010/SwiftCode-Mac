import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public struct EditorRecovery: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var path: String
        public var baseHash: UInt64
        public var text: String
    }

    public let directory: String

    public init(directory: String) { self.directory = directory }

    public static var standard: EditorRecovery {
        let env = ProcessInfo.processInfo.environment
        #if os(macOS)
        let base = NSHomeDirectory() + "/Library/Application Support/SwiftCode"
        #else
        let base = (env["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory() + "/.local/state") + "/swiftcode"
        #endif
        return EditorRecovery(directory: base + "/recovery")
    }

    private func file(for path: String) -> String {
        directory + "/" + String(EditorFile.hash(Data(path.utf8)), radix: 16) + ".json"
    }

    @discardableResult
    public func keep(path: String, baseHash: UInt64, text: String) -> Bool {
        guard let data = try? JSONEncoder().encode(Entry(path: path, baseHash: baseHash, text: text)) else { return false }
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let target = file(for: path)
            if !FileManager.default.fileExists(atPath: target) {
                guard FileManager.default.createFile(atPath: target, contents: nil, attributes: [.posixPermissions: 0o600]) else { return false }
            }
            try EditorFile.writeAtomically(data, to: target)
            return true
        } catch {
            return false
        }
    }

    public func entry(for path: String) -> Entry? {
        guard let data = FileManager.default.contents(atPath: file(for: path)),
              let e = try? JSONDecoder().decode(Entry.self, from: data), e.path == path else { return nil }
        return e
    }

    public func discard(path: String) { try? FileManager.default.removeItem(atPath: file(for: path)) }
}
