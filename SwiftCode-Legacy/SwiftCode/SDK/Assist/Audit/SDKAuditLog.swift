import Foundation
import os

public enum SDKAuditEventType: String, Sendable, Codable, CaseIterable {
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

public struct SDKAuditEvent: Codable, Sendable {
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

private let auditInfraLog = Logger(subsystem: "com.swiftcode.sdk", category: "sdk-audit")

public actor SDKAuditLog {
    public static let shared = SDKAuditLog()

    public nonisolated let logFileLocation: URL

    private let logDirectory: URL
    private let logFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var fileHandle: FileHandle?

    private static var defaultLogDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        return (base ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true))
            .appendingPathComponent("SwiftCode", isDirectory: true)
    }

    public init(logDirectory: URL? = nil) {
        let directory = logDirectory ?? Self.defaultLogDirectory
        self.logDirectory = directory
        let fileURL = directory.appendingPathComponent("SDKAudit.jsonl", isDirectory: false)
        self.logFileURL = fileURL
        self.logFileLocation = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func record(
        type: SDKAuditEventType,
        extensionID: String? = nil,
        capability: SDKCapabilityID? = nil,
        detail: String? = nil,
        correlationId: String? = nil
    ) {
        let event = SDKAuditEvent(
            type: type,
            extensionID: extensionID,
            capabilityRaw: capability?.rawValue,
            detail: detail,
            correlationId: correlationId
        )
        do {
            let data = try encoder.encode(event)
            guard let line = String(data: data, encoding: .utf8) else {
                auditInfraLog.error(
                    "SDKAuditLog: failed to stringify \(type.rawValue) event JSON; dropping event")
                return
            }
            try writeLine(line)
        } catch {
            auditInfraLog.error(
                "SDKAuditLog: failed to record \(type.rawValue) event for extension \(extensionID ?? "-", privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public func flushAndClose() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    public func recentEvents(limit: Int) -> [SDKAuditEvent] {
        guard limit > 0 else { return [] }
        guard let text = try? String(contentsOf: logFileURL, encoding: .utf8) else { return [] }

        var events: [SDKAuditEvent] = []
        var skipped = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(SDKAuditEvent.self, from: data)
            else {
                skipped += 1
                continue
            }
            events.append(event)
        }
        if skipped > 0 {
            auditInfraLog.error(
                "SDKAuditLog: skipped \(skipped, privacy: .public) undecodable line(s) in SDKAudit.jsonl — possible corruption or tampering")
        }
        if events.count > limit {
            return Array(events.suffix(limit))
        }
        return events
    }

    private func writeLine(_ line: String) throws {
        try ensureLogFile()
        guard let handle = fileHandle else {
            throw CocoaError(.fileWriteUnknown)
        }
        try handle.write(contentsOf: Data((line + "\n").utf8))
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
            fm.createFile(
                atPath: logFileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        if fileHandle == nil {
            let handle = try FileHandle(forWritingTo: logFileURL)
            try? handle.seekToEnd()
            fileHandle = handle
        }
    }
}
