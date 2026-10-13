import Foundation

// MARK: - SDKGrantStore (persisted capability grant store)
//
// Host-owned, actor-guarded persisted store for permission grants
// (spec Docs/Intro-to-SDK.md §8.2, §8.7; ADR SDK-Architecture.md §5).
//
// Persistence: ~/Library/Application Support/SwiftCode/SDKGrants.json
// (mode 0600), a JSON array of grant records written atomically
// (temp file + rename) with sorted keys. The store loads lazily on
// first access and keeps an in-memory cache inside this actor; every
// mutation re-persists the full cache.
//
// Grant lifecycle enforced here:
//   - A grant is ACTIVE only if it has no revokedAt tombstone and its
//     expiresAt is nil or in the future (checked against Date()).
//   - revoke() stamps revokedAt and KEEPS the record (revocation
//     tombstone) — it never deletes, so revocation is auditable.
//   - pruneExpired() removes only records whose expiresAt is more than
//     30 days in the past; revoked tombstones are kept regardless of
//     age (audit-relevant).
//   - A corrupt on-disk file is moved aside to
//     SDKGrants.json.corrupt-<timestamp> and the store starts empty —
//     never crashes on corrupt state.
//
// NOT via KeychainService (ADR §5: its UserDefaults base64 fallback is a
// secret-leak vector). Grant records carry no secrets — only identities,
// digests, scopes, and timestamps.
//
// Thread-safety: this is an actor; the in-memory cache is actor-isolated.
// Errors use SDKError/SDKErrorCode (Contracts/Errors/SDKError.swift),
// never fatalError and never force-unwraps on untrusted input.

// MARK: - SDKGrantScope

/// The scope a grant applies to. v1 scopes grants to a single approved
/// project: the standardized absolute path of the project root. A grant
/// never leaks across projects.
public struct SDKGrantScope: Codable, Sendable {
    /// Standardized absolute path of the approved project root.
    public let projectRootPath: String

    public init(projectRootPath: String) {
        self.projectRootPath = (projectRootPath as NSString).standardizingPath
    }
}

// MARK: - SDKGrantRecord

/// One persisted permission grant: an extension (identified by extension
/// ID + installed package identity) holds one capability within one
/// project scope. Field set per spec §8.2.
public struct SDKGrantRecord: Codable, Sendable {
    public let id: UUID
    public let extensionID: String
    /// SHA-256 hex digest of the installed package, at grant time.
    public let packageDigest: String
    public let packageVersion: String
    public let capability: SDKCapabilityID
    public let scope: SDKGrantScope
    public let grantedAt: Date
    /// Granting principal or approval source, e.g. "user-approval".
    public let grantedBy: String
    /// Optional expiry. Nil = does not expire.
    public let expiresAt: Date?
    /// Revocation tombstone. Set (never cleared) by revoke/revokeAll;
    /// a revoked record stays persisted as audit evidence.
    public let revokedAt: Date?
    /// Policy version at grant time. Current policy is version 1.
    public let policyVersion: Int

    public init(
        id: UUID = UUID(),
        extensionID: String,
        packageDigest: String,
        packageVersion: String,
        capability: SDKCapabilityID,
        scope: SDKGrantScope,
        grantedAt: Date = Date(),
        grantedBy: String,
        expiresAt: Date? = nil,
        revokedAt: Date? = nil,
        policyVersion: Int = 1
    ) {
        self.id = id
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.packageVersion = packageVersion
        self.capability = capability
        self.scope = scope
        self.grantedAt = grantedAt
        self.grantedBy = grantedBy
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.policyVersion = policyVersion
    }

    /// Whether this record authorizes use right now: not revoked and not
    /// expired (expiry evaluated against `Date()`).
    public func isActive(now: Date = Date()) -> Bool {
        if revokedAt != nil { return false }
        if let expiresAt, expiresAt <= now { return false }
        return true
    }

    /// A copy of this record with a revocation tombstone stamped.
    public func revoked() -> SDKGrantRecord {
        guard revokedAt == nil else { return self }
        return SDKGrantRecord(
            id: id,
            extensionID: extensionID,
            packageDigest: packageDigest,
            packageVersion: packageVersion,
            capability: capability,
            scope: scope,
            grantedAt: grantedAt,
            grantedBy: grantedBy,
            expiresAt: expiresAt,
            revokedAt: Date(),
            policyVersion: policyVersion
        )
    }
}

// MARK: - SDKGrantStore

public actor SDKGrantStore {
    /// Host-wide shared instance. All grant reads/writes go through this
    /// actor so revocation takes effect at the broker's next check.
    public static let shared = SDKGrantStore()

    /// Records expired for longer than this are eligible for pruning.
    private static let pruneAfter: TimeInterval = 30 * 24 * 60 * 60

    /// Parent dirs are created on first persist. Kept on actor state so
    /// it can be injected in tests (tests construct their own instance).
    private let storeURL: URL

    /// In-memory cache, keyed by record id. Loaded lazily from disk on
    /// first access; every mutation re-persists.
    private var cache: [UUID: SDKGrantRecord] = [:]
    private var loaded = false

    private init(storeURL: URL = SDKGrantStore.defaultStoreURL()) {
        self.storeURL = storeURL
    }

    // MARK: - Store location

    private static func defaultStoreURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SwiftCode/SDKGrants.json")
    }

    // MARK: - Load

    /// Loads the cache from disk exactly once. Throws SDKError
    /// (.serviceUnavailable) on I/O failure; a corrupt file is moved
    /// aside and the store starts empty.
    private func ensureLoaded() throws {
        guard !loaded else { return }
        loaded = true

        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return }

        let data: Data
        do {
            data = try Data(contentsOf: storeURL)
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "read", "underlying": "\(error)"])
        }

        do {
            let records = try Self.decodeRecords(data)
            cache = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        } catch {
            // Corrupt state must never crash the host: move the bad file
            // aside and start empty.
            let asideURL = storeURL.appendingPathExtension("corrupt-\(Self.corruptTimestamp())")
            do {
                try fm.moveItem(at: storeURL, to: asideURL)
            } catch {
                // If even the move fails, still start empty rather than
                // throwing: an unreadable store must not crash the host.
            }
            cache = [:]
        }
    }

    private static func decodeRecords(_ data: Data) throws -> [SDKGrantRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SDKGrantRecord].self, from: data)
    }

    private static func corruptTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - Persist

    /// Atomically persists the full cache: encode to a temp file next to
    /// the store, chmod 0600, then rename into place. Throws SDKError
    /// (.serviceUnavailable) on any I/O failure.
    private func persist() throws {
        let fm = FileManager.default
        let dirURL = storeURL.deletingLastPathComponent()

        do {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "mkdir", "underlying": "\(error)"])
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        let payload: Data
        do {
            payload = try encoder.encode(Array(cache.values).sorted { $0.id.uuidString < $1.id.uuidString })
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "encode", "underlying": "\(error)"])
        }

        // Write to a sibling temp file first so a crash mid-write can
        // never leave a half-written store file.
        let tmpURL = dirURL.appendingPathComponent(
            "SDKGrants.json.tmp-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try payload.write(to: tmpURL, options: [.atomic])
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "write-tmp", "underlying": "\(error)"])
        }

        // Mode 0600 BEFORE the file becomes the live store (ADR §5).
        do {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw Self.storeUnavailableError(
                diagnostics: ["op": "chmod", "underlying": "\(error)"])
        }

        // Rename over the live store (atomic within a directory).
        do {
            if fm.fileExists(atPath: storeURL.path) {
                try fm.removeItem(at: storeURL)
            }
            try fm.moveItem(at: tmpURL, to: storeURL)
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw Self.storeUnavailableError(
                diagnostics: ["op": "rename", "underlying": "\(error)"])
        }

        // Re-assert 0600 on the final path (rename preserves it, but be
        // explicit — the store is security-relevant).
        do {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "chmod-final", "underlying": "\(error)"])
        }
    }

    private static func storeUnavailableError(diagnostics: [String: String]) -> SDKError {
        SDKError(
            code: .serviceUnavailable,
            message: "Permission store unavailable. Grants could not be read or saved.",
            suggestion: "Restart SwiftCode and try again. If the problem persists, check that ~/Library/Application Support/SwiftCode is writable.",
            diagnostics: diagnostics
        )
    }

    // MARK: - Queries

    /// Returns the grant authorizing `extensionID` to use `capability`
    /// within `projectRootPath`, or nil when missing, revoked, or
    /// expired (expiry evaluated against the current date). A failed
    /// load is treated as "no grants" (deny-by-default) rather than a
    /// crash.
    public func activeGrant(
        extensionID: String,
        capability: SDKCapabilityID,
        projectRootPath: String
    ) -> SDKGrantRecord? {
        let now = Date()
        let standardizedRoot = (projectRootPath as NSString).standardizingPath
        let records: [SDKGrantRecord]
        do {
            try ensureLoaded()
            records = Array(cache.values)
        } catch {
            return nil
        }
        return records.first {
            $0.extensionID == extensionID
                && $0.capability == capability
                && $0.scope.projectRootPath == standardizedRoot
                && $0.isActive(now: now)
        }
    }

    /// All grant records (active, revoked, and expired) for an
    /// extension, oldest first. Tombstones are included — this is the
    /// audit view. A failed load returns an empty array.
    public func grants(for extensionID: String) -> [SDKGrantRecord] {
        let records: [SDKGrantRecord]
        do {
            try ensureLoaded()
            records = cache.values.filter { $0.extensionID == extensionID }
        } catch {
            return []
        }
        return records.sorted { $0.grantedAt < $1.grantedAt }
    }

    // MARK: - Mutations

    /// Inserts or replaces grant records by `id`, then persists.
    ///
    /// - Parameter authorizedByAPIKey: the verified developer API key the
    ///   issuing session presented, if any (spec §8.2.1). When non-nil,
    ///   issuing a grant for a privileged capability
    ///   (`SDKCapabilityRegistry.isPrivileged`) additionally requires the
    ///   key to carry the `capabilities:request` scope: otherwise the whole
    ///   batch is rejected with `.apiKeyScopeInsufficient` and NOTHING is
    ///   persisted (fail closed — partial issuance would leave the store in
    ///   a half-authorized state). A nil key means the grants come from the
    ///   user-approval path, which this gate does not constrain.
    public func recordGrants(
        _ records: [SDKGrantRecord],
        authorizedByAPIKey apiKey: SDKAPIKey? = nil
    ) async throws {
        try ensureLoaded()
        if let apiKey {
            try await enforceKeyScopeForIssuance(records: records, apiKey: apiKey)
        }
        for record in records {
            cache[record.id] = record
        }
        try persist()
    }

    /// Grant-issuance side of the `capabilities:request` scope gate: a
    /// session whose key lacks the scope cannot be granted privileged
    /// capabilities. Emits an `apiKeyScopeFailure` audit event on denial
    /// (key ID only — never secret material).
    private func enforceKeyScopeForIssuance(records: [SDKGrantRecord], apiKey: SDKAPIKey) async throws {
        if apiKey.revokedAt != nil {
            throw SDKError(
                code: .apiKeyRevoked,
                message: "This developer API key was revoked.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
        }
        if apiKey.isExpired {
            throw SDKError(
                code: .apiKeyInvalid,
                message: "This developer API key has expired.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
        }
        let privileged = records.filter { SDKCapabilityRegistry.isPrivileged($0.capability) }
        guard !privileged.isEmpty else { return }
        guard apiKey.scopes.contains(.capabilitiesRequest) else {
            let correlationId = SDKError.newCorrelationId()
            let capabilities = privileged
                .map { $0.capability.rawValue }
                .sorted()
                .joined(separator: ", ")
            await SDKAuditLog.shared.record(
                type: .apiKeyScopeFailure,
                extensionID: privileged[0].extensionID,
                detail: "grant issuance denied: session API key \(apiKey.id.uuidString) "
                    + "lacks \"capabilities:request\" for privileged capabilities (\(capabilities))",
                correlationId: correlationId
            )
            throw SDKError(
                code: .apiKeyScopeInsufficient,
                message: "This developer API key does not include the \"capabilities:request\" scope, "
                    + "which is required to grant privileged capabilities (\(capabilities)).",
                suggestion: "Create a key with the \"capabilities:request\" scope in Studio → Settings → Developer API Keys.",
                diagnostics: ["keyId": apiKey.id.uuidString, "missingScope": "capabilities:request"],
                correlationId: correlationId
            )
        }
    }

    /// Stamps `revokedAt` on every record for `extensionID` +
    /// `capability` (revocation tombstone — records are kept, never
    /// deleted), then persists. Idempotent: revoking an already-revoked
    /// or unknown grant is a no-op success.
    public func revoke(extensionID: String, capability: SDKCapabilityID) throws {
        try ensureLoaded()
        for (id, record) in cache where record.extensionID == extensionID && record.capability == capability {
            cache[id] = record.revoked()
        }
        try persist()
    }

    /// Stamps `revokedAt` on every record for `extensionID`, then
    /// persists. Idempotent.
    public func revokeAll(for extensionID: String) throws {
        try ensureLoaded()
        for (id, record) in cache where record.extensionID == extensionID {
            cache[id] = record.revoked()
        }
        try persist()
    }

    /// Removes records that have been expired for more than 30 days.
    /// Revoked records (audit tombstones) are kept regardless of age.
    public func pruneExpired() throws {
        try ensureLoaded()
        let cutoff = Date().addingTimeInterval(-Self.pruneAfter)
        cache = cache.filter { _, record in
            if record.revokedAt != nil { return true }       // keep audit tombstones
            guard let expiresAt = record.expiresAt else { return true } // non-expiring grants stay
            return expiresAt > cutoff                        // keep recently-expired; drop long-expired
        }
        try persist()
    }
}
