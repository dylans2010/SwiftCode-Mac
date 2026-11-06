import Foundation

// MARK: - Persistent state, kept separate from SwiftCode's core resources
//
// Layout under ~/Library/Application Support/SwiftCode/ExtensionsV2/:
//   installed.json      — installed records (the manager's source of truth)
//   grants.json         — permission grants, keyed by extension id
//   settings.json       — registry URL, auto-update, Node path
//   diagnostics.jsonl   — append-only diagnostic entries
//   staging/            — in-progress installs, never a final location
//   extensions/<id>/    — one extracted package per installed extension
//   backups/<id>.backup — previous version kept until an update commits
public struct ExtV2Storage: Sendable {
    public struct Settings: Codable, Sendable {
        public var registryBaseURL: String
        public var autoUpdate: Bool
        public var nodeExecutablePath: String?
        public var allowPrerelease: Bool

        public init(
            registryBaseURL: String = "https://open-vsx.org/api",
            autoUpdate: Bool = false, nodeExecutablePath: String? = nil,
            allowPrerelease: Bool = false
        ) {
            self.registryBaseURL = registryBaseURL
            self.autoUpdate = autoUpdate
            self.nodeExecutablePath = nodeExecutablePath
            self.allowPrerelease = allowPrerelease
        }
    }

    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.root = base.appendingPathComponent("SwiftCode/ExtensionsV2", isDirectory: true)
        }
    }

    public var installedFile: URL { root.appendingPathComponent("installed.json") }
    public var grantsFile: URL { root.appendingPathComponent("grants.json") }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    public var diagnosticsFile: URL { root.appendingPathComponent("diagnostics.jsonl") }
    public var extensionsDirectory: URL { root.appendingPathComponent("extensions", isDirectory: true) }
    public var stagingDirectory: URL { root.appendingPathComponent("staging", isDirectory: true) }
    public var backupsDirectory: URL { root.appendingPathComponent("backups", isDirectory: true) }

    public func ensureDirectories() throws {
        for dir in [root, extensionsDirectory, stagingDirectory, backupsDirectory] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Atomic write: temp file in the same directory, then replace. A crash
    /// mid-write leaves the previous file intact, never a half-written one.
    public func writeAtomically<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }

    public func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func loadInstalled() -> [ExtV2InstalledExtension] {
        (try? load([ExtV2InstalledExtension].self, from: installedFile)) ?? []
    }

    public func saveInstalled(_ installed: [ExtV2InstalledExtension]) throws {
        try writeAtomically(installed, to: installedFile)
    }

    public func loadSettings() -> Settings {
        (try? load(Settings.self, from: settingsFile)) ?? Settings()
    }

    public func saveSettings(_ settings: Settings) throws {
        try writeAtomically(settings, to: settingsFile)
    }

    public func appendDiagnosticsLine(_ line: String) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: diagnosticsFile.path) {
                try "".write(to: diagnosticsFile, atomically: true, encoding: .utf8)
            }
            let handle = try FileHandle(forWritingTo: diagnosticsFile)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            // Diagnostics must never break the operation they describe.
            print("[ExtV2Storage] Could not append diagnostics: \(error)")
        }
    }

    /// Removes stale staging directories left by interrupted installs.
    /// Safe to run at launch: staging is never a live install location.
    public func cleanStaleStaging() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
