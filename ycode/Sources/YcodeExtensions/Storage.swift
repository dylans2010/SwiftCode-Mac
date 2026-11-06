import Foundation

// MARK: - Settings + storage (spec §3.5)

public struct ExtensionSettings: Codable, Sendable {
    public var registryBaseURL: String
    public var autoUpdate: Bool
    public var nodeExecutablePath: String?
    public var allowPrerelease: Bool

    public init(registryBaseURL: String = "https://open-vsx.org/api", autoUpdate: Bool = false,
                nodeExecutablePath: String? = nil, allowPrerelease: Bool = false) {
        self.registryBaseURL = registryBaseURL
        self.autoUpdate = autoUpdate
        self.nodeExecutablePath = nodeExecutablePath
        self.allowPrerelease = allowPrerelease
    }
}

/// The single storage root (deviation D-2):
/// `~/Library/Application Support/SwiftCode/ExtensionsV2/`.
public struct ExtensionStorage: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                      in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support")
            self.root = appSupport.appendingPathComponent("SwiftCode/ExtensionsV2")
        }
    }

    public var installedFile: URL { root.appendingPathComponent("installed.json") }
    public var grantsFile: URL { root.appendingPathComponent("grants.json") }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    public var diagnosticsFile: URL { root.appendingPathComponent("diagnostics.jsonl") }
    public var extensionsDirectory: URL { root.appendingPathComponent("extensions") }
    public var stagingDirectory: URL { root.appendingPathComponent("staging") }
    public var backupsDirectory: URL { root.appendingPathComponent("backups") }
    public var hostDirectory: URL { root.appendingPathComponent("host") }

    public func ensureDirectories() throws {
        for directory in [root, extensionsDirectory, stagingDirectory, backupsDirectory, hostDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Atomic write: temp file in the same directory, then move into place.
    public func writeAtomically<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try writeAtomically(data, to: url)
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temp, to: url)
    }

    /// Missing/corrupt -> [] (a broken record file must never prevent launch).
    public func loadInstalled() -> [InstalledExtension] {
        guard let data = try? Data(contentsOf: installedFile),
              let decoded = try? JSONDecoder().decode([InstalledExtension].self, from: data) else {
            return []
        }
        return decoded
    }

    public func saveInstalled(_ installed: [InstalledExtension]) throws {
        try writeAtomically(installed, to: installedFile)
    }

    /// Missing/corrupt -> defaults.
    public func loadSettings() -> ExtensionSettings {
        guard let data = try? Data(contentsOf: settingsFile),
              let decoded = try? JSONDecoder().decode(ExtensionSettings.self, from: data) else {
            return ExtensionSettings()
        }
        return decoded
    }

    public func saveSettings(_ settings: ExtensionSettings) throws {
        try writeAtomically(settings, to: settingsFile)
    }

    /// Never throws: diagnostics must never break the operation they describe.
    public func appendDiagnosticsLine(_ line: String) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: diagnosticsFile.path) {
                let handle = try FileHandle(forWritingTo: diagnosticsFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = (line + "\n").data(using: .utf8) { try handle.write(contentsOf: data) }
            } else {
                try (line + "\n").write(to: diagnosticsFile, atomically: true, encoding: .utf8)
            }
        } catch {
            print("[YcodeExtensions] diagnostics append failed: \(error.localizedDescription)")
        }
    }

    /// Removes all staging entries (called at launch).
    public func cleanStaleStaging() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}

// MARK: - Diagnostics (spec §4.5)

public enum DiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct DiagnosticEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let extensionId: String?
    public let level: DiagnosticLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), extensionId: String? = nil,
                level: DiagnosticLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.extensionId = extensionId
        self.level = level
        self.message = message
    }
}

/// In-memory ring (capped at 2000 entries, oldest dropped) plus an
/// append-only `diagnostics.jsonl`. Messages only — never secrets or
/// file contents.
public final class DiagnosticsService: @unchecked Sendable {
    public static let shared = DiagnosticsService()

    private let storage: ExtensionStorage
    private let lock = NSLock()
    private var entries: [DiagnosticEntry] = []

    public init(storage: ExtensionStorage = ExtensionStorage()) {
        self.storage = storage
    }

    public func log(extensionId: String? = nil, level: DiagnosticLevel, message: String) {
        let entry = DiagnosticEntry(extensionId: extensionId, level: level, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8) {
            storage.appendDiagnosticsLine(line)
        }
#if DEBUG
        print("[ExtV2][\(level.rawValue)] \(extensionId ?? "-"): \(message)")
#endif
    }

    public func info(_ message: String, extensionId: String? = nil) {
        log(extensionId: extensionId, level: .info, message: message)
    }

    public func warning(_ message: String, extensionId: String? = nil) {
        log(extensionId: extensionId, level: .warning, message: message)
    }

    public func error(_ message: String, extensionId: String? = nil) {
        log(extensionId: extensionId, level: .error, message: message)
    }

    public func allEntries() -> [DiagnosticEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    public func entries(for extensionId: String) -> [DiagnosticEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries.filter { $0.extensionId == extensionId }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }

    /// `"[ISO8601] [level] <id>: <message>"` per line.
    public func exportReport() -> String {
        let formatter = ISO8601DateFormatter()
        return allEntries().map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(entry.extensionId ?? "-"): \(entry.message)"
        }.joined(separator: "\n")
    }
}
