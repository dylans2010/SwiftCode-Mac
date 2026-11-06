import Foundation
import Crypto

// MARK: - SDKAPIKeyStore
//
// Ported from Legacy `SwiftCode/SDK/Host/APIKeys/SDKAPIKeyStore.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Owns developer API key lifecycle: the host device key, key metadata,
// verification with rate limiting, revocation, and key-bound
// entitlements. Secrets are never persisted — only metadata. The device
// key is created once and never silently regenerated: a corrupt device
// key fails closed with `.serviceUnavailable`.
//
// Storage seam: `SDKSecretStoring` (macOS Keychain via `SDKKeychain`,
// file store on Linux). SwiftCodeAssistant's `SecretStore` was considered
// and rejected — it has no enumeration, which `list()` requires.

public actor SDKAPIKeyStore {
    public static let shared = SDKAPIKeyStore(store: SDKSecretStoreFactory.defaultStore())

    /// Account holding the 32-byte host device key.
    public static let deviceKeyAccount = "sdk.device-key"
    /// Prefix for per-key metadata accounts: `sdk.apikey.<uuid>`.
    public static let metadataAccountPrefix = "sdk.apikey."

    // Rate limiting (Legacy §8.2): 10 failed verifications per 60-second
    // window per bucket, then a 5-minute lockout. Buckets are keyed by
    // the UNVERIFIED presented key ID, or `"unparseable"` when the
    // secret cannot even be parsed — the bucket key is never used for
    // authorization, only to bound guessing.
    static let maxFailuresPerWindow = 10
    static let failureWindowSeconds: TimeInterval = 60
    static let lockoutSeconds: TimeInterval = 300
    static let maxBuckets = 1_024

    private let store: any SDKSecretStoring
    private var failureBuckets: [String: FailureBucket] = [:]

    private struct FailureBucket {
        var failures: [Date] = []
        var lockedUntil: Date?
    }

    public init(store: any SDKSecretStoring) {
        self.store = store
    }

    // MARK: - Device key

    /// Returns the host device key, creating and persisting it on first
    /// use. A present-but-corrupt device key throws `.serviceUnavailable`
    /// — it is never silently regenerated, or every issued key would
    /// stop verifying without explanation.
    public func getOrCreateDeviceKey() throws -> Data {
        if let existing = try store.read(account: Self.deviceKeyAccount) {
            guard existing.count == 32 else {
                throw SDKError(
                    code: .serviceUnavailable,
                    message: "The developer key store is corrupt.",
                    suggestion: "The host device key is unreadable. Contact support — do not delete key material by hand.",
                    diagnostics: ["deviceKeyBytes": String(existing.count)]
                )
            }
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try store.write(data, account: Self.deviceKeyAccount)
        return data
    }

    // MARK: - Create / list / revoke

    /// Creates a key. The secret is returned exactly once alongside the
    /// metadata — the caller must show it to the developer and then drop
    /// it. Metadata is persisted BEFORE the secret is generated so a
    /// returned secret always verifies.
    public func createKey(
        label: String,
        scopes: Set<SDKAPIKeyScope>,
        isLive: Bool,
        expiresAt: Date? = nil
    ) throws -> (key: SDKAPIKey, secret: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...128).contains(trimmedLabel.count) else {
            throw SDKError(code: .invalidArgument, message: "The key label must be 1–128 characters.")
        }
        guard !scopes.isEmpty else {
            throw SDKError(code: .invalidArgument, message: "A key needs at least one scope.")
        }
        if let expiresAt, expiresAt <= Date() {
            throw SDKError(code: .invalidArgument, message: "The expiry date must be in the future.")
        }
        let key = SDKAPIKey(
            keyPrefix: isLive ? SDKAPIKeyCodec.livePrefix : SDKAPIKeyCodec.testPrefix,
            label: trimmedLabel,
            scopes: scopes,
            expiresAt: expiresAt
        )
        try persist(key)
        let deviceKey = try getOrCreateDeviceKey()
        let secret = SDKAPIKeyCodec.generateSecret(for: key, deviceKey: deviceKey)
        await SDKAuditLog.shared.record(.apiKeyCreated, detail: "key \(key.id.uuidString)")
        return (key, secret)
    }

    /// All keys, newest first. Undecodable metadata records are skipped,
    /// never fatal — one corrupt record must not hide every other key.
    public func list() -> [SDKAPIKey] {
        let accounts = (try? store.accountNames(withPrefix: Self.metadataAccountPrefix)) ?? []
        var keys: [SDKAPIKey] = []
        for account in accounts {
            guard let data = try? store.read(account: account),
                  let key = try? Self.decodeKey(data) else { continue }
            keys.append(key)
        }
        return keys.sorted { $0.createdAt > $1.createdAt }
    }

    /// Revokes a key. Idempotent: revoking an already-revoked or unknown
    /// key is a no-op success. Closes the key's Assist sessions so a
    /// revoked key cannot keep an open session alive.
    public func revoke(id: UUID) async {
        guard var key = try? readKey(id: id), !key.isRevoked else { return }
        key.revokedAt = Date()
        try? persist(key)
        await SDKAuditLog.shared.record(.apiKeyRevoked, detail: "key \(id.uuidString)")
        _ = await SDKAssistService.shared.closeSessions(forKeyID: id)
    }

    // MARK: - Verify

    /// Verifies a presented secret and returns the key metadata.
    /// Re-reads metadata on every call so revocation takes effect
    /// immediately. Revoked → `.apiKeyRevoked`; expired, unknown, or
    /// malformed → `.apiKeyInvalid`; rate-limited → `.apiKeyRateLimited`.
    /// Updates `lastUsedAt` on success. The secret is never logged.
    public func verify(secret: String) async throws -> SDKAPIKey {
        let bucketKey = SDKAPIKeyCodec.extractPresentedKeyID(from: secret) ?? "unparseable"
        if isLockedOut(bucketKey) {
            throw SDKError(
                code: .apiKeyRateLimited,
                message: "Too many failed key verifications. Try again later.",
                suggestion: "Wait a few minutes before trying again."
            )
        }
        // Each failed attempt records exactly one rate-limit failure.
        var failureRecorded = false
        func noteFailure(_ detail: String) async {
            guard !failureRecorded else { return }
            failureRecorded = true
            recordFailure(bucketKey)
            await SDKAuditLog.shared.record(.apiKeyAuthFailure, detail: detail)
        }
        do {
            let deviceKey = try getOrCreateDeviceKey()
            let (keyID, prefix) = try SDKAPIKeyCodec.parseAndVerify(secret: secret, deviceKey: deviceKey)
            guard var key = try? readKey(id: keyID) else {
                await noteFailure("unknown key")
                throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
            }
            guard key.keyPrefix == prefix else {
                await noteFailure("key \(keyID.uuidString)")
                throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
            }
            if key.isRevoked {
                await noteFailure("revoked key \(keyID.uuidString)")
                throw SDKError(code: .apiKeyRevoked, message: "The developer API key was revoked.")
            }
            if key.isExpired {
                await noteFailure("expired key \(keyID.uuidString)")
                throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
            }
            key.lastUsedAt = Date()
            try? persist(key)
            return key
        } catch let error as SDKError {
            // Parse failures land here (the metadata branches recorded
            // above); record them exactly once as well.
            if error.code == .apiKeyInvalid {
                await noteFailure("malformed key")
            }
            throw error
        }
    }

    // MARK: - Scopes & entitlements

    /// Requires `scope` on a verified key record. Throws
    /// `.apiKeyScopeInsufficient` (audited) otherwise.
    public func requireScope(_ scope: SDKAPIKeyScope, on key: SDKAPIKey) throws {
        guard key.scopes.contains(scope) else {
            Task {
                await SDKAuditLog.shared.record(.apiKeyScopeFailure, detail: "key \(key.id.uuidString) scope \(scope.rawValue)")
            }
            throw SDKError(
                code: .apiKeyScopeInsufficient,
                message: "The developer API key lacks the required scope.",
                suggestion: "Create a key with the \(scope.rawValue) scope."
            )
        }
    }

    /// Requires `entitlement` on a verified key record. A revoked key
    /// never satisfies an entitlement check.
    public func requireEntitlement(_ entitlement: SDKEntitlement, on key: SDKAPIKey) throws {
        guard !key.isRevoked, key.entitlements.contains(entitlement) else {
            throw SDKError(
                code: .apiKeyScopeInsufficient,
                message: "The developer API key lacks the required entitlement."
            )
        }
    }

    /// Grants an entitlement to a key. A revoked key can never be granted
    /// (`.apiKeyRevoked`, Legacy behaviour). Idempotent: granting an
    /// entitlement the key already has is a no-op success.
    public func grantEntitlement(_ entitlement: SDKEntitlement, toKeyID id: UUID) async throws {
        guard var key = try? readKey(id: id) else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        guard !key.isRevoked else {
            throw SDKError(
                code: .apiKeyRevoked,
                message: "This developer API key was revoked.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
        }
        guard !key.entitlements.contains(entitlement) else { return }
        key.entitlements.insert(entitlement)
        try persist(key)
        await SDKAuditLog.shared.record(.entitlementGranted, detail: "key \(id.uuidString) entitlement \(entitlement.rawValue)")
    }

    /// Revokes an entitlement from a key. Returns the number of in-flight
    /// Assist sessions closed by the revocation hook (Legacy behaviour:
    /// a revoked entitlement must not keep an open session alive).
    /// Idempotent: revoking an entitlement the key does not have is a
    /// no-op success that still closes nothing.
    public func revokeEntitlement(_ entitlement: SDKEntitlement, fromKeyID id: UUID) async throws -> Int {
        guard var key = try? readKey(id: id) else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        guard key.entitlements.contains(entitlement) else { return 0 }
        key.entitlements.remove(entitlement)
        try persist(key)
        let closedSessions = await SDKAssistService.shared.closeSessions(forKeyID: id)
        await SDKAuditLog.shared.record(
            .entitlementRevoked,
            detail: "key \(id.uuidString) entitlement \(entitlement.rawValue) closedSessions \(closedSessions)"
        )
        return closedSessions
    }

    // MARK: - Rate limiting

    private func isLockedOut(_ bucket: String) -> Bool {
        guard let entry = failureBuckets[bucket], let lockedUntil = entry.lockedUntil else { return false }
        if Date() < lockedUntil { return true }
        failureBuckets[bucket]?.lockedUntil = nil
        return false
    }

    private func recordFailure(_ bucket: String) {
        let now = Date()
        var entry = failureBuckets[bucket] ?? FailureBucket()
        entry.failures = entry.failures.filter { now.timeIntervalSince($0) < Self.failureWindowSeconds }
        entry.failures.append(now)
        if entry.failures.count >= Self.maxFailuresPerWindow {
            entry.lockedUntil = now.addingTimeInterval(Self.lockoutSeconds)
            entry.failures = []
        }
        failureBuckets[bucket] = entry
        if failureBuckets.count > Self.maxBuckets {
            // Evict the stalest bucket so the table stays bounded.
            let stalest = failureBuckets.min { lhs, rhs in
                (lhs.value.failures.min() ?? .distantPast) < (rhs.value.failures.min() ?? .distantPast)
            }
            if let key = stalest?.key { failureBuckets.removeValue(forKey: key) }
        }
    }

    // MARK: - Persistence

    private func metadataAccount(for id: UUID) -> String {
        Self.metadataAccountPrefix + id.uuidString
    }

    private func persist(_ key: SDKAPIKey) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(key)
        try store.write(data, account: metadataAccount(for: key.id))
    }

    private func readKey(id: UUID) throws -> SDKAPIKey? {
        guard let data = try store.read(account: metadataAccount(for: id)) else { return nil }
        return try Self.decodeKey(data)
    }

    private static func decodeKey(_ data: Data) throws -> SDKAPIKey {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SDKAPIKey.self, from: data)
    }
}
