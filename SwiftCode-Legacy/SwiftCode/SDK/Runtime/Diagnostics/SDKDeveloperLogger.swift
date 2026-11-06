import Foundation

// MARK: - SDKDeveloperLogger
//
// Developer-facing, high-verbosity diagnostics pipeline (spec §16.2).
//
// Every call appends ONE JSON line to `~/.swiftcode/logs/developer-sdk.log`
// containing: timestamp, the SAME `ERR-XXXXXX` correlation ID carried by the
// user-facing error (this is the bi-directional mapping —
// `SDKUserLogger.log(_:)` and this logger share the ID, so quoting the ID
// from the UI locates the verbose entry here), the stable error code, the
// full diagnostics dictionary, the context dictionary, and process/thread
// info.
//
// Audience: SDK developers, internal maintainers, extension creators. This
// stream MAY include filesystem paths and IPC payload summaries, but it MUST
// still redact credential values — every diagnostics/context value passes
// through `SDKLogRedaction.redactDiagnosticValue(key:value:)` first.
//
// File handling (real, not stubbed):
//   - `~/.swiftcode/logs/` is created on demand (mode 0700).
//   - The log file is opened for append; new files are created mode 0600,
//     and the mode is re-enforced on every open.
//   - When the file exceeds 10 MB it is rotated: `developer-sdk.log.2` is
//     deleted, `.1` → `.2`, current → `.1`, and a fresh file is started.
//   - `fetchEntries(correlationId:)` reads matching lines back (including
//     rotations, oldest first) for the Studio log inspector.
//
// Logging is best-effort and never throws: a logging failure must not break
// the host flow that reported the error.

public actor SDKDeveloperLogger {
    public static let shared = SDKDeveloperLogger()

    /// Rotation threshold: 10 MiB.
    public static let maxLogBytes: UInt64 = 10 * 1024 * 1024
    /// Number of rotated files retained (`.1`, `.2`).
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

    /// Exposed `nonisolated` so Studio can locate the log without awaiting
    /// the actor (it never changes after init).
    public nonisolated let logFileLocation: URL

    /// - Parameters:
    ///   - logDirectory: Override for tests. Defaults to `~/.swiftcode/logs`.
    ///   - maxBytes: Rotation threshold override for tests.
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

    // MARK: - Logging

    /// Appends one JSON line for `error`, carrying `correlationId` verbatim
    /// so it maps 1:1 to the user-facing entry with the same ID.
    ///
    /// - Parameters:
    ///   - error: The typed SDK error (code, user-safe message, suggestion,
    ///     correlation ID, timestamp).
    ///   - diagnostics: Structured internal diagnostics (stack traces, exit
    ///     codes, IPC payload summaries, resource metrics, …). Credential
    ///     values are redacted before writing.
    ///   - context: Free-form context (extension ID, capability, project
    ///     path, …). Credential values are redacted before writing.
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

    // MARK: - Reading

    /// Returns the raw JSON lines whose `correlationId` matches, scanning
    /// `developer-sdk.log.2`, `.1`, then the current file so results read
    /// oldest-first. Used by the Studio log inspector to show the verbose
    /// counterpart of a user-quoted `ERR-XXXXXX` ID.
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

    /// Closes the open file handle, if any. The handle is reopened lazily
    /// on the next `log(_:diagnostics:context:)` call.
    public func flushAndClose() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - Private file handling

    private func writeLine(_ line: String) {
        do {
            try rotateIfNeeded()
            try ensureLogFile()
            guard let handle = fileHandle else { return }
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            // Best-effort: drop the handle so the next event reopens the
            // file, and swallow the failure — logging must never break the
            // host flow that reported the error.
            try? fileHandle?.close()
            fileHandle = nil
        }
    }

    /// Creates `~/.swiftcode/logs/` (mode 0700) and opens
    /// `developer-sdk.log` for append (mode 0600, re-enforced on every open).
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

    /// Rotates when the current file reaches `maxBytes`: deletes `.2`,
    /// moves `.1` → `.2` and current → `.1`. The fresh file is created by
    /// the next `ensureLogFile()` call.
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
