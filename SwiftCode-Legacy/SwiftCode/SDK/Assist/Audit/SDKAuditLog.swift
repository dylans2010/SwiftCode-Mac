import Foundation
import os

// MARK: - SDKAuditEventType
//
// Stable, host-side security audit event taxonomy (Docs/Intro-to-SDK.md
// §16.3). These event types are FIXED: do not rename or remove cases.
// Additive cases require a minor SDK version bump.
//
// Every significant permission, authentication, and trust action the SDK
// host takes MUST be recorded with one of these types via `SDKAuditLog`:
//   - Permission requested, granted, denied, or revoked.
//   - Assist access requests and denials (Assist is deny-by-default;
//     `assistDenied` fires on every denied attempt, including attempts made
//     at the host broker boundary, not just at manifest validation).
//   - API key created, revoked, authentication failure, and scope failure.
//     A key *rotation* is recorded as a pair of events — `apiKeyCreated`
//     for the replacement and `apiKeyRevoked` for the retired key — sharing
//     one correlation ID.
//   - Package installed, updated, disabled, or uninstalled.
//   - Runtime terminated due to policy, crash, or memory violation.
//   - Security value lifecycle for the per-app Keychain namespace: value
//     added, used, deleted, all values wiped on extension uninstall, and
//     security permission denied. The `detail` for these events carries the
//     app Security ID, the value ID, and (for use) the operation kind —
//     NEVER the secret bytes, and never a request body or any string that
//     could contain them. Every one of these events records the acting
//     extension identity (`extensionID`) and a correlation ID.

public enum SDKAuditEventType: String, Sendable, Codable, CaseIterable {
    // Permissions
    case permissionRequested
    case permissionGranted
    case permissionDenied
    case permissionRevoked

    // Assist gate (deny-by-default)
    case assistDenied
    /// A cloud-model call was denied because the caller key lacks the
    /// `com.SwiftCode.developer-AI-Allows-Cloud` entitlement
    /// (Docs/Intro-to-SDK.md §12). `detail`: the capability + key ID —
    /// never secrets.
    case cloudModelDenied

    // Developer API keys
    case apiKeyCreated
    case apiKeyRevoked
    case apiKeyScopeFailure
    case apiKeyAuthFailure

    // Assist authorization entitlements (Docs/Intro-to-SDK.md §12).
    // Granted only through the Assist access application flow
    // (`SDKAssistApplicationStore.approve` → `SDKAPIKeyStore.grantEntitlement`),
    // never from the manifest or client code.
    /// An entitlement was granted to a developer API key. `detail`: the key
    /// ID and the entitlement ID — never secrets.
    case entitlementGranted
    /// An entitlement was revoked from a developer API key. `detail`: the
    /// key ID and the entitlement ID — never secrets.
    case entitlementRevoked

    // Extension lifecycle
    case extensionInstalled
    case extensionUpdated
    case extensionDisabled
    case extensionUninstalled

    // Runtime
    case runtimeTerminated

    // Security values (per-app Keychain namespace). Recorded by the host
    // security broker — never by the extension itself. Callers MUST pass the
    // acting extension's identity as `extensionID` and a correlation ID;
    // the event's own `timestamp` is the timestamp of record. `detail` on
    // these events carries identifiers only — the rules below are the
    // secrets contract for this section, and the strictest part of this
    // file's redaction policy.
    /// A secret value was stored under the app's Security ID. `detail`:
    /// app Security ID + value ID. NEVER the secret bytes.
    case securityValueAdded
    /// A stored value was used by a host-mediated operation. `detail`: app
    /// Security ID + value ID + operation kind. NEVER the secret bytes, and
    /// NEVER the request body or any other string that could contain them.
    case securityValueUsed
    /// A single stored value was deleted. `detail`: app Security ID +
    /// value ID. NEVER the secret bytes.
    case securityValueDeleted
    /// All stored values for an app were wiped because the owning extension
    /// was uninstalled. `detail`: app Security ID (+ wiped-value count when
    /// known). NEVER any secret material.
    case securityValuesWipedOnUninstall
    /// An extension was denied access to a security value or namespace.
    /// `detail`: app Security ID + value ID (when one was targeted) +
    /// reason. NEVER the secret bytes.
    case securityPermissionDenied
}

// MARK: - SDKAuditEvent
//
// One immutable security audit record. Serialized as ONE JSON object per
// line (sorted keys, ISO-8601 dates) in the host audit log.
//
// HOST ONLY: this type is held only by host code. Extension runtimes never
// receive a reference to it, and the extension-facing TypeScript SDK exposes
// no binding for it. There is no read or delete API reachable from an
// extension — the append-only log on disk is protected by file permissions
// (0600) and by the fact that extensions have no capability that reaches it.
//
// SECRETS CONTRACT (callers' contract): `detail` MUST NEVER contain secrets
// or credential material — no API keys, tokens, passwords, client secrets,
// or PEM blocks. Pass *identifiers* instead: key IDs, key fingerprints
// (e.g. a SHA-256 hex of the key), the public `sc_dev_live_…` prefix with
// its tail redacted, stable error codes, and human-readable reasons. The
// audit log is a forensic record; writing a secret into it would defeat the
// protection the 0600 file mode is meant to provide.

public struct SDKAuditEvent: Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let type: SDKAuditEventType
    public let extensionID: String?
    /// Raw capability value (e.g. `SDKCapabilityID.projectRead.rawValue`).
    /// Stored as a plain string rather than `SDKCapabilityID` so audit
    /// records from older SDK versions still decode after the capability
    /// set evolves.
    public let capabilityRaw: String?
    /// Free-form, privacy-conscious detail. NEVER secrets (see above).
    public let detail: String?
    /// Optional caller-supplied correlation ID (e.g. the `ERR-XXXXXX` ID
    /// from an `SDKError`, or a shared ID linking a key rotation pair).
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

/// os_log channel for *audit-log infrastructure* failures (subsystem
/// `com.swiftcode.sdk`, category `sdk-audit`). Emitted only when the audit
/// log itself cannot be written — the failure is then visible in the unified
/// log so a silent audit hole is never confused with "nothing happened".
private let auditInfraLog = Logger(subsystem: "com.swiftcode.sdk", category: "sdk-audit")

// MARK: - SDKAuditLog
//
// Durable, append-only, tamper-resistant host security audit log
// (spec §16.3). Every `record(_:)` call appends ONE JSON object per line
// (sorted keys, ISO-8601 dates) to
// `~/Library/Application Support/SwiftCode/SDKAudit.jsonl`.
//
// Tamper resistance comes from three layers:
//   1. Ownership: only host code holds this type. No read/delete API is
//      exposed to extensions (the TS SDK has no binding for it), and this
//      API surface offers append and tail-read only — there is no rewrite,
//      truncate, or delete entry point at all.
//   2. File protection: the containing directory is created mode 0700 and
//      the log file mode 0600 (re-enforced on every open), so only this
//      user can read or modify it. The log lives outside any directory an
//      extension capability can reach.
//   3. Durability: appends go through a single `FileHandle` seeked to end;
//      events are never buffered-and-dropped silently.
//
// Best-effort, never throws: a logging failure must not crash the host flow
// that reported the security event. On I/O failure the failure itself is
// emitted via os_log (subsystem `com.swiftcode.sdk`, category `sdk-audit`)
// and recording continues. The log is deliberately NOT rotated or
// truncated by this type — deleting audit records is exactly what the
// tamper-resistance requirement forbids; retention policy is a
// host-administration decision outside this API.

public actor SDKAuditLog {
    public static let shared = SDKAuditLog()

    /// Exposed `nonisolated` so host tooling (e.g. Studio) can locate the
    /// log file without awaiting the actor. Immutable after init.
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

    /// - Parameter logDirectory: Override for tests. Defaults to
    ///   `~/Library/Application Support/SwiftCode`.
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

    // MARK: - Recording

    /// Records ONE security audit event by appending one JSON object to
    /// `SDKAudit.jsonl`.
    ///
    /// Never throws outward and never traps: on any I/O failure the failure
    /// is emitted via os_log (subsystem `com.swiftcode.sdk`, category
    /// `sdk-audit`) and the caller continues unaffected — an audit-log
    /// failure must not crash the host flow that reported the event.
    ///
    /// - Parameters:
    ///   - type: The audit event type (permission/API-key/Assist/lifecycle/
    ///     security).
    ///   - extensionID: The extension the event concerns, if any.
    ///   - capability: The capability the event concerns, if any (stored as
    ///     its raw string value so old records keep decoding).
    ///   - detail: Privacy-conscious free-form detail. MUST NOT contain
    ///     secrets/credentials — callers' contract (see `SDKAuditEvent`).
    ///   - correlationId: Optional ID linking related events (e.g. an
    ///     `SDKError` correlation ID or a key-rotation pair).
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

    /// Closes the open file handle, if any. The handle is reopened lazily
    /// on the next `record(_:)` call.
    public func flushAndClose() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - Reading (host only)

    /// Returns up to `limit` of the most recent audit events, oldest first,
    /// by scanning the tail of `SDKAudit.jsonl`. Intended for the future
    /// Studio audit viewer. Lines that fail to decode are skipped (a
    /// corrupted line must not hide the rest of the record); a non-zero
    /// skip count is emitted via os_log as a tamper-integrity signal.
    ///
    /// Host only — like `record`, this is unreachable from extensions.
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

    // MARK: - Private file handling

    /// Appends one line to the log, creating the directory (mode 0700) and
    /// the file (mode 0600) on demand, and re-enforcing the 0600 file mode
    /// on every open so an externally relaxed mode is tightened again.
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
