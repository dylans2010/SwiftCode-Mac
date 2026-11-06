import Foundation

// MARK: - SDKAuditLog
//
// Ported from Legacy `SwiftCode/SDK/Assist/Audit/SDKAuditLog.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Append-only audit trail for security-relevant SDK host events. The log
// is a JSON-lines file; `record()` never throws (a logging failure is
// reported through the OS log, never back to the caller). Detail strings
// MUST NEVER contain secrets — identifiers only.

public enum SDKAuditEventType: String, Sendable, Codable {
    case permissionRequested
    case permissionGranted
    case permissionDenied
    case permissionRevoked
    case assistDenied
    case cloudModelDenied
    case apiKeyCreated
    case apiKeyRevoked
    case apiKeyScopeFailure
    case apiKeyAuthFailure
    case entitlementGranted
    case entitlementRevoked
    case extensionInstalled
    case extensionUpdated
    case extensionDisabled
    case extensionUninstalled
    case runtimeTerminated
    case securityValueAdded
    case securityValueUsed
    case securityValueDeleted
    case securityValuesWipedOnUninstall
    case securityPermissionDenied
}

public struct SDKAuditEvent: Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let type: SDKAuditEventType
    public let extensionID: String?
    public let capabilityRaw: String?
    public let detail: String?
    public let correlationId: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: SDKAuditEventType,
        extensionID: String? = nil,
        capabilityRaw: String? = nil,
        detail: String? = nil,
        correlationId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.extensionID = extensionID
        self.capabilityRaw = capabilityRaw
        self.detail = detail
        self.correlationId = correlationId
    }
}

/// Append-only JSON-lines audit log at
/// `~/Library/Application Support/SwiftCode/SDKAudit.jsonl`
/// (Linux: `~/.config/swiftcode/sdk-audit.jsonl`). Directory 0700, file 0600,
/// re-enforced on every write. A single `FileHandle` is kept seeked to
/// the end for appends.
public actor SDKAuditLog {
    public static let shared = SDKAuditLog()

    private var handle: FileHandle?
    private var logURL: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("SwiftCode/SDKAudit.jsonl", isDirectory: false)
        #else
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        return base.appendingPathComponent("swiftcode/sdk-audit.jsonl", isDirectory: false)
        #endif
    }

    private init() {}

    /// Records an event. Never throws: failures are reported through the
    /// OS log and the event is dropped, never propagated to the caller.
    /// `detail` must contain identifiers only — never secrets.
    public func record(
        _ type: SDKAuditEventType,
        extensionID: String? = nil,
        capabilityRaw: String? = nil,
        detail: String? = nil,
        correlationId: String? = nil
    ) {
        let event = SDKAuditEvent(
            type: type,
            extensionID: extensionID,
            capabilityRaw: capabilityRaw,
            detail: detail,
            correlationId: correlationId
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(event)
            data.append(0x0A)
            try ensureHandle()
            guard let handle else { return }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            SDKLog.error("SDKAuditLog: failed to record \(type.rawValue): \(error.localizedDescription)",
                         subsystem: "com.swiftcode.sdk", category: "sdk-audit")
        }
    }

    /// The most recent `limit` events, oldest first. Undecodable lines
    /// are skipped and reported through the OS log as a tamper signal.
    public func recentEvents(limit: Int) -> [SDKAuditEvent] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var events: [SDKAuditEvent] = []
        var skipped = 0
        for line in data.split(separator: 0x0A) {
            guard let event = try? decoder.decode(SDKAuditEvent.self, from: Data(line)) else {
                skipped += 1
                continue
            }
            events.append(event)
        }
        if skipped > 0 {
            SDKLog.error("SDKAuditLog: skipped \(skipped) undecodable audit lines (possible tampering)",
                         subsystem: "com.swiftcode.sdk", category: "sdk-audit")
        }
        return Array(events.suffix(max(0, limit)))
    }

    public func flushAndClose() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
    }

    private func ensureHandle() throws {
        if handle != nil { return }
        let url = logURL
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        handle = try FileHandle(forWritingTo: url)
        try handle?.seekToEnd()
    }
}
