import Foundation

public actor SDKDeveloperLogger {
    public static let shared = SDKDeveloperLogger()

    public static let maxLogBytes: UInt64 = 10 * 1024 * 1024
    public static let retainedRotations = 2

    private static var defaultLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftcode/logs", isDirectory: true)
    }

    private let logDirectory: URL
    private let logFileURL: URL
    private let maxBytes: UInt64
    private let isoFormatter: ISO8601DateFormatter
    private var fileHandle: FileHandle?

    public nonisolated let logFileLocation: URL

    public init(logDirectory: URL? = nil, maxBytes: UInt64 = SDKDeveloperLogger.maxLogBytes) {
        let directory = logDirectory ?? Self.defaultLogDirectory
        self.logDirectory = directory
        let fileURL = directory.appendingPathComponent("developer-sdk.log", isDirectory: false)
        self.logFileURL = fileURL
        self.logFileLocation = fileURL
        self.maxBytes = maxBytes
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }

    public func log(
        _ error: SDKError,
        diagnostics: [String: String] = [:],
        context: [String: String] = [:]
    ) {
        let redactedDiagnostics = Dictionary(
            uniqueKeysWithValues: diagnostics.map {
                ($0.key, SDKLogRedaction.redactDiagnosticValue(key: $0.key, value: $0.value))
            }
        )
        let redactedContext = Dictionary(
            uniqueKeysWithValues: context.map {
                ($0.key, SDKLogRedaction.redactDiagnosticValue(key: $0.key, value: $0.value))
            }
        )

        var payload: [String: Any] = [
            "timestamp": isoFormatter.string(from: error.timestamp),
            "correlationId": error.correlationId,
            "code": error.code.rawValue,
            "message": error.message,
            "sdkVersion": "1.0.0",
            "diagnostics": redactedDiagnostics,
            "context": redactedContext,
            "process": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "name": ProcessInfo.processInfo.processName,
                "thread": currentThreadLabel(),
            ] as [String: Any],
        ]
        if let suggestion = error.suggestion, !suggestion.isEmpty {
            payload["suggestion"] = suggestion
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8)
        else {
            return
        }
        writeLine(line)
    }

    public func fetchEntries(correlationId: String) -> [String] {
        guard !correlationId.isEmpty else { return [] }
        let baseName = logFileURL.lastPathComponent
        let directory = logFileURL.deletingLastPathComponent()
        let urls = [".2", ".1", ""].map {
            directory.appendingPathComponent(baseName + $0, isDirectory: false)
        }
        let exact = "\"correlationId\":\"\(correlationId)\""
        let spaced = "\"correlationId\": \"\(correlationId)\""
        var matches: [String] = []
        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for rawLine in text.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty,
                      line.contains(exact) || line.contains(spaced)
                else { continue }
                matches.append(line)
            }
        }
        return matches
    }

    public func flushAndClose() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func writeLine(_ line: String) {
        do {
            try rotateIfNeeded()
            try ensureLogFile()
            guard let handle = fileHandle else { return }
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            try? fileHandle?.close()
            fileHandle = nil
        }
    }

    private func ensureLogFile() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDirectory.path) {
            try fm.createDirectory(
                at: logDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        if fm.fileExists(atPath: logFileURL.path) {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logFileURL.path)
        } else {
            fm.createFile(atPath: logFileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if fileHandle == nil {
            let handle = try FileHandle(forWritingTo: logFileURL)
            try? handle.seekToEnd()
            fileHandle = handle
        }
    }

    private func rotateIfNeeded() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: logFileURL.path),
              let size = (try? fm.attributesOfItem(atPath: logFileURL.path)[.size]) as? UInt64,
              size >= maxBytes
        else { return }

        try? fileHandle?.close()
        fileHandle = nil

        let baseName = logFileURL.lastPathComponent
        let directory = logFileURL.deletingLastPathComponent()
        let oldest = directory.appendingPathComponent(baseName + ".2", isDirectory: false)
        let previous = directory.appendingPathComponent(baseName + ".1", isDirectory: false)

        if fm.fileExists(atPath: oldest.path) {
            try? fm.removeItem(at: oldest)
        }
        if fm.fileExists(atPath: previous.path) {
            try? fm.moveItem(at: previous, to: oldest)
        }
        try? fm.moveItem(at: logFileURL, to: previous)
    }

    private func currentThreadLabel() -> String {
        if let name = Thread.current.name, !name.isEmpty { return name }
        return Thread.isMainThread ? "main" : "background"
    }
}
