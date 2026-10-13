import CryptoKit
import Foundation
import Security

// MARK: - SDKAPIKeyStore
//
// The host-side authority for developer API keys (spec §8.2.1, ADR §11).
// An actor: all state transitions (create / verify / revoke / list) are
// serialized, which keeps `lastUsedAt` / `revokedAt` updates race-free under
// Swift 6 strict concurrency.
//
// SECURITY MODEL
// - The key SECRET is never stored anywhere — not in the Keychain, not on
//   disk, not in memory beyond the call that handles it. Verification is by
//   HMAC-SHA256 against a 32-byte device key (`SecRandomCopyBytes`,
//   Keychain-backed at `sdk.device-key`), so there is no secret hash in
//   storage for an attacker to steal.
// - Only key METADATA (`SDKAPIKey`: id, prefix, label, scopes, timestamps)
//   is persisted, as JSON in `SDKKeychain` under `sdk.apikey.<uuid>`.
//   Metadata contains no secret material.
// - `verify(secret:)` re-reads metadata and re-checks `revokedAt` on EVERY
//   call. Revocation therefore takes effect immediately at the authorization
//   boundary (spec §8.2.1); no session caches a "still valid" verdict.
// - The secret is returned from `createKey` exactly once. Callers (Studio)
//   must display it once and must never persist it in plaintext.
// - The secret `String` is toxic: it is never logged, never interpolated
//   into an `SDKError`, and never written to disk by this type.
// - Brute-force protection: `verify(secret:)` is in-memory rate limited
//   (see "Brute-force protection" below) — guessing resistance lives here,
//   at the only entry point that accepts a raw secret.
// - Optional expiry: `SDKAPIKey.expiresAt` (nil = never expires) is
//   honored by `verify` on every call, alongside the `revokedAt` check.
//
// All timestamps are real (`Date()`). Keychain failures surface as
// `.serviceUnavailable`; unknown/malformed/forged/expired secrets surface
// as `.apiKeyInvalid` (one code for all four, so failure modes are not
// distinguishable); revoked keys surface as `.apiKeyRevoked`; a rate-limit
// lockout surfaces as `.apiKeyRateLimited`.

public actor SDKAPIKeyStore {

    /// Process-wide shared store. The actor serializes all access.
    public static let shared = SDKAPIKeyStore()

    private init() {}

    // MARK: - Keychain layout

    /// Keychain account holding the base64-encoded 32-byte device key.
    private static let deviceKeyAccount = "sdk.device-key"
    /// Keychain account prefix for per-key metadata JSON.
    private static let metadataAccountPrefix = "sdk.apikey."
    private static let deviceKeyByteCount = 32
    private static let maxLabelLength = 128

    // MARK: - Device key

    /// Returns the device signing key, creating and persisting it on first
    /// use. The raw bytes live only in the Keychain and in the returned
    /// `SymmetricKey`; this actor keeps no in-memory copy between calls.
    ///
    /// A present-but-corrupt device key is a hard `.serviceUnavailable`
    /// failure: silently regenerating it would invalidate every issued key,
    /// which must be an explicit, user-visible rotation — not an accident.
    public func getOrCreateDeviceKey() throws -> SymmetricKey {
        if let stored = try SDKKeychain.get(forKey: Self.deviceKeyAccount) {
            guard let raw = Data(base64Encoded: stored), raw.count == Self.deviceKeyByteCount else {
                throw SDKError(
                    code: .serviceUnavailable,
                    message: "The SDK device key is corrupt and cannot be used.",
                    suggestion: "Delete the \"\(Self.deviceKeyAccount)\" item from the Keychain to rotate it (this invalidates all existing developer API keys).",
                    diagnostics: ["reason": "device-key-corrupt"]
                )
            }
            return SymmetricKey(data: raw)
        }

        var bytes = [UInt8](repeating: 0, count: Self.deviceKeyByteCount)
        defer { bytes = [UInt8](repeating: 0, count: Self.deviceKeyByteCount) }
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not generate the SDK device key.",
                suggestion: "The macOS Keychain could not be reached. Check that the Keychain is unlocked and try again.",
                diagnostics: ["operation": "device-key-generate", "osstatus": String(status)]
            )
        }
        let key = SymmetricKey(data: bytes)
        try SDKKeychain.set(Data(bytes).base64EncodedString(), forKey: Self.deviceKeyAccount)
        return key
    }

    // MARK: - Creation

    /// Creates a new developer API key and its signed secret.
    ///
    /// The returned `secret` is shown to the developer EXACTLY ONCE.
    /// Callers must display it once (Studio → Settings → Developer API Keys)
    /// and must never persist it in plaintext, log it, or embed it in error
    /// output. Only the metadata is stored; the secret is re-derivable for
    /// verification via the device key, never by lookup.
    ///
    /// - Parameters:
    ///   - label: Human-readable label (1–128 characters).
    ///   - scopes: At least one scope entitlement.
    ///   - isLive: `true` → `sc_dev_live_…`, `false` → `sc_dev_test_…`.
    /// - Returns: The stored metadata and the one-time secret.
    public func createKey(
        label: String,
        scopes: Set<SDKAPIKeyScope>,
        isLive: Bool,
        expiresAt: Date? = nil
    ) throws -> (key: SDKAPIKey, secret: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, trimmedLabel.count <= Self.maxLabelLength else {
            throw SDKError(
                code: .invalidArgument,
                message: "The API key label must be between 1 and \(Self.maxLabelLength) characters."
            )
        }
        guard !scopes.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The API key must be granted at least one scope."
            )
        }
        if let expiresAt, expiresAt <= Date() {
            throw SDKError(
                code: .invalidArgument,
                message: "The API key expiry must be in the future."
            )
        }

        let key = SDKAPIKey(
            keyPrefix: isLive ? SDKAPIKeyCodec.livePrefix : SDKAPIKeyCodec.testPrefix,
            label: trimmedLabel,
            scopes: scopes,
            createdAt: Date(),
            expiresAt: expiresAt
        )
        let deviceKey = try getOrCreateDeviceKey()
        let secret = try SDKAPIKeyCodec.generateSecret(for: key, deviceKey: deviceKey)
        // Persist metadata BEFORE the secret leaves this function: a secret
        // whose metadata was never stored can never verify.
        try persist(key)
        return (key, secret)
    }

    // MARK: - Verification (authorization boundary)

    /// Verifies a presented secret and returns its metadata.
    ///
    /// Every call: enforces the brute-force rate limit, parses and
    /// HMAC-verifies the secret, loads fresh metadata from the Keychain,
    /// rejects revoked keys (`.apiKeyRevoked`) and expired keys
    /// (`.apiKeyInvalid`), and updates `lastUsedAt`. Unknown IDs,
    /// malformed secrets, and signature mismatches all surface as
    /// `.apiKeyInvalid` — deliberately indistinguishable.
    ///
    /// The returned metadata includes the key's CURRENT entitlements
    /// (`SDKAPIKey.entitlements`): metadata is re-read on every call, so
    /// entitlement grants and revocations take effect at the authorization
    /// boundary immediately.
    ///
    /// Keychain failures fail closed (`.serviceUnavailable`): when the host
    /// cannot establish key validity, the action is denied.
    public func verify(secret: String) throws -> SDKAPIKey {
        // Bucket label from the UNVERIFIED structural parse (never a trust
        // decision — just a stable per-presented-key counter).
        let bucketKey = SDKAPIKeyCodec.extractPresentedKeyID(from: secret)?.uuidString
            ?? Self.unparseableBucketKey
        try checkRateLimit(bucketKey: bucketKey)

        do {
            let deviceKey = try getOrCreateDeviceKey()
            let (id, prefix) = try SDKAPIKeyCodec.parseAndVerify(secret, deviceKey: deviceKey)
            var key = try loadMetadata(id: id)
            // Defense in depth: the signature already binds the prefix, but the
            // stored metadata must agree with what was presented.
            guard key.keyPrefix == prefix else {
                throw apiKeyInvalidError()
            }
            if key.isExpired {
                throw apiKeyExpiredError()
            }
            if key.revokedAt != nil {
                throw SDKError(
                    code: .apiKeyRevoked,
                    message: "This developer API key was revoked.",
                    suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
                )
            }
            key.lastUsedAt = Date()
            try persist(key)
            recordVerifySuccess(bucketKey: bucketKey)
            return key
        } catch let sdkError as SDKError {
            // Only guessing attempts feed the limiter: infrastructure
            // failures (`.serviceUnavailable`) and known-bad keys
            // (`.apiKeyRevoked`) are not brute-force signals.
            if sdkError.code == .apiKeyInvalid {
                recordVerifyFailure(bucketKey: bucketKey)
            }
            throw sdkError
        }
    }

    // MARK: - Brute-force protection
    //
    // In-memory rate limiting on `verify(secret:)` — the only entry point
    // that accepts a raw secret, hence the only guessing surface.
    //
    // - Per presented key ID: at most `maxFailuresPerWindow` FAILED
    //   verifications per `attemptWindow` seconds, then a `lockoutDuration`
    //   lockout. The bucket key is the unverified structural ID
    //   (`SDKAPIKeyCodec.extractPresentedKeyID`); secrets too malformed to
    //   yield an ID share the `unparseableBucketKey` bucket.
    // - A successful verification clears the bucket; the lockout is fixed
    //   length (attempts made during a lockout do not extend it).
    // - Lockout throws `.apiKeyRateLimited` — deliberately distinct from
    //   `.apiKeyInvalid` so a legitimate developer knows to wait instead of
    //   rotating a good key. The lockout reveals nothing about key
    //   validity: the bucket key is derived from the presenter-supplied
    //   secret, so no new oracle is created.
    // - Actor-isolated state: no locks, race-free under Swift 6. Nothing
    //   persists — a host restart clears all buckets (fail-open on restart
    //   is safe: the HMAC check itself is unchanged).

    /// Failed verifications allowed per key ID per `attemptWindow`.
    private static let maxFailuresPerWindow = 10
    /// Sliding window for counting failures.
    private static let attemptWindow: TimeInterval = 60
    /// How long a bucket stays locked after exhausting its window.
    private static let lockoutDuration: TimeInterval = 5 * 60
    /// Bucket label for secrets too malformed to yield a key ID.
    private static let unparseableBucketKey = "unparseable"
    /// Bound on tracked buckets; beyond this, idle buckets are pruned.
    private static let maxTrackedBuckets = 1024

    private struct AttemptBucket {
        var windowStart: Date
        var failures: Int
        var lockedUntil: Date?
    }

    private var attemptBuckets: [String: AttemptBucket] = [:]

    /// Throws `.apiKeyRateLimited` when `bucketKey` is currently locked out.
    /// Rolls the window forward when it has elapsed.
    private func checkRateLimit(bucketKey: String) throws {
        pruneBucketsIfNeeded()
        let now = Date()
        guard var bucket = attemptBuckets[bucketKey] else { return }
        if let lockedUntil = bucket.lockedUntil {
            if now < lockedUntil {
                throw rateLimitedError(lockedUntil: lockedUntil)
            }
            // Lockout expired: start a fresh window.
            bucket = AttemptBucket(windowStart: now, failures: 0, lockedUntil: nil)
            attemptBuckets[bucketKey] = bucket
            return
        }
        if now.timeIntervalSince(bucket.windowStart) >= Self.attemptWindow {
            bucket.windowStart = now
            bucket.failures = 0
            attemptBuckets[bucketKey] = bucket
        }
    }

    private func recordVerifyFailure(bucketKey: String) {
        let now = Date()
        var bucket = attemptBuckets[bucketKey]
            ?? AttemptBucket(windowStart: now, failures: 0, lockedUntil: nil)
        if now.timeIntervalSince(bucket.windowStart) >= Self.attemptWindow {
            bucket.windowStart = now
            bucket.failures = 0
            bucket.lockedUntil = nil
        }
        bucket.failures += 1
        if bucket.failures >= Self.maxFailuresPerWindow {
            bucket.lockedUntil = now.addingTimeInterval(Self.lockoutDuration)
        }
        attemptBuckets[bucketKey] = bucket
    }

    private func recordVerifySuccess(bucketKey: String) {
        attemptBuckets.removeValue(forKey: bucketKey)
    }

    /// Keeps the bucket map bounded: once past `maxTrackedBuckets`, idle
    /// buckets (window elapsed, not locked) are dropped. Locked and
    /// in-window buckets are always kept.
    private func pruneBucketsIfNeeded() {
        guard attemptBuckets.count > Self.maxTrackedBuckets else { return }
        let now = Date()
        // Note: Dictionary.filter returns an array of tuples, so rebuild
        // the dictionary explicitly (keys are already unique).
        attemptBuckets = Dictionary(
            uniqueKeysWithValues: attemptBuckets.filter { _, bucket in
                if let lockedUntil = bucket.lockedUntil, lockedUntil > now { return true }
                return now.timeIntervalSince(bucket.windowStart) < Self.attemptWindow
            }
        )
    }

    private func rateLimitedError(lockedUntil: Date) -> SDKError {
        let remaining = max(1, Int(lockedUntil.timeIntervalSince(Date()) / 60))
        return SDKError(
            code: .apiKeyRateLimited,
            message: "Too many failed verification attempts for this developer API key. Verification is temporarily locked (about \(remaining) minute\(remaining == 1 ? "" : "s") remaining).",
            suggestion: "Wait for the lockout to expire and try again. If you did not make these attempts, revoke the key in Studio → Settings → Developer API Keys and generate a new one."
        )
    }

    // MARK: - Revocation

    /// Revokes the key with `id`, effective immediately: `verify(secret:)`
    /// checks `revokedAt` on every call, so no session can outlive this.
    /// In-flight Assist sessions owned by the key are closed as well
    /// (Docs/Intro-to-SDK.md §14). Revoking an already-revoked key
    /// succeeds (idempotent). Revoking an unknown key ID throws
    /// `.apiKeyInvalid`.
    public func revoke(id: UUID) async throws {
        var key = try loadMetadata(id: id)
        guard key.revokedAt == nil else { return }
        key.revokedAt = Date()
        try persist(key)
        // A revoked key fails `verify(secret:)` on the next call, so
        // subsequent calls are denied at the boundary; close the sessions
        // the key had open too (host-owned cleanup, never extension-facing).
        _ = await SDKAssistService.shared.closeSessions(forKeyID: id)
    }

    // MARK: - Listing

    /// Returns metadata for all known keys, newest first. Metadata only —
    /// secrets are never stored and therefore never listed. Undecodable
    /// entries are skipped; a Keychain enumeration failure yields an empty
    /// list rather than a partial one.
    public func list() -> [SDKAPIKey] {
        guard let accounts = try? SDKKeychain.accountNames(withPrefix: Self.metadataAccountPrefix) else {
            return []
        }
        var keys: [SDKAPIKey] = []
        for account in accounts {
            if let value = try? SDKKeychain.get(forKey: account),
               let key = try? decodeMetadata(value)
            {
                keys.append(key)
            }
        }
        return keys.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Entitlement grant/revoke (Assist authorization, Docs/Intro-to-SDK.md §12)
    //
    // Entitlements are stored ON the API key record (`SDKAPIKey.entitlements`),
    // never in the manifest, never self-asserted. The ONLY writer of these
    // methods is `SDKAssistApplicationStore.approve(_:)` — the Assist access
    // application approval step IS the entitlement grant path. Every
    // grant/revoke is recorded in the audit log with the key ID and the
    // entitlement ID — never secret material.
    //
    // Because entitlements live on the persisted metadata record,
    // `verify(secret:)` returns the key WITH its current entitlements: it
    // re-reads metadata on every call, so an entitlement revocation takes
    // effect at the authorization boundary exactly like key revocation.

    /// Grants `entitlement` to the key with `id`. Idempotent: granting an
    /// entitlement the key already carries succeeds without duplicating it.
    /// Throws `.apiKeyInvalid` for an unknown key ID; `.apiKeyRevoked` for
    /// a revoked key (entitlements are never granted to revoked keys).
    public func grantEntitlement(_ entitlement: SDKEntitlement, to id: UUID) async throws {
        var key = try loadMetadata(id: id)
        if key.revokedAt != nil {
            throw SDKError(
                code: .apiKeyRevoked,
                message: "This developer API key was revoked.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
        }
        guard !key.entitlements.contains(entitlement) else { return }
        key.entitlements.insert(entitlement)
        try persist(key)
        await SDKAuditLog.shared.record(
            type: .entitlementGranted,
            detail: "keyId=\(id.uuidString); entitlement=\(entitlement.rawValue)"
        )
    }

    /// Revokes `entitlement` from the key with `id`, effective immediately:
    /// `verify(secret:)` re-reads metadata on every call, so the next
    /// authorization-boundary check sees the revocation. In-flight Assist
    /// sessions owned by this key are closed as well
    /// (Docs/Intro-to-SDK.md §14): the metadata removal above is already
    /// effective at the boundary, and closing the open sessions is pure
    /// host-side bookkeeping (no backend work is in flight at the
    /// unwired backend boundary), so it is always safe. Idempotent:
    /// revoking an entitlement the key does not carry succeeds silently.
    /// Throws `.apiKeyInvalid` for an unknown key ID.
    public func revokeEntitlement(_ entitlement: SDKEntitlement, from id: UUID) async throws {
        var key = try loadMetadata(id: id)
        guard key.entitlements.contains(entitlement) else { return }
        key.entitlements.remove(entitlement)
        try persist(key)
        let closedSessions = await SDKAssistService.shared.closeSessions(forKeyID: id)
        await SDKAuditLog.shared.record(
            type: .entitlementRevoked,
            detail: "keyId=\(id.uuidString); entitlement=\(entitlement.rawValue); closedSessions=\(closedSessions)"
        )
    }

    // MARK: - Scope enforcement

    /// Requires `scope` on an already-verified `key`. Throws
    /// `.apiKeyScopeInsufficient` naming the missing scope,
    /// `.apiKeyRevoked` if the key was revoked after verification, or
    /// `.apiKeyInvalid` if the key expired after verification
    /// (belt-and-braces: `verify` is the primary revocation/expiry check).
    public func requireScope(_ scope: SDKAPIKeyScope, for key: SDKAPIKey) throws {
        if key.revokedAt != nil {
            throw SDKError(
                code: .apiKeyRevoked,
                message: "This developer API key was revoked.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
        }
        if key.isExpired {
            throw apiKeyExpiredError()
        }
        guard key.scopes.contains(scope) else {
            throw SDKError(
                code: .apiKeyScopeInsufficient,
                message: "This developer API key does not include the \"\(scope.rawValue)\" scope.",
                suggestion: "Create a key with the \"\(scope.rawValue)\" scope in Studio → Settings → Developer API Keys.",
                diagnostics: ["keyId": key.id.uuidString, "missingScope": scope.rawValue]
            )
        }
    }

    // MARK: - Entitlement enforcement

    /// Requires `entitlement` on an already-verified `key` (mirror of
    /// `requireScope`). Throws `.apiKeyScopeInsufficient` naming the
    /// missing entitlement, `.apiKeyRevoked` if the key was revoked after
    /// verification, or `.apiKeyInvalid` if the key expired after
    /// verification (belt-and-braces: `verify` is the primary check).
    public func requireEntitlement(_ entitlement: SDKEntitlement, for key: SDKAPIKey) throws {
        if key.revokedAt != nil {
            throw SDKError(
                code: .apiKeyRevoked,
                message: "This developer API key was revoked.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
        }
        if key.isExpired {
            throw apiKeyExpiredError()
        }
        guard key.entitlements.contains(entitlement) else {
            throw SDKError(
                code: .apiKeyScopeInsufficient,
                message: "This developer API key does not carry the \"\(entitlement.rawValue)\" entitlement.",
                suggestion: "Apply for Assist access in Studio → Settings → Developer API Keys → Assist Access; the entitlement is granted when the application is approved.",
                diagnostics: ["keyId": key.id.uuidString, "missingEntitlement": entitlement.rawValue]
            )
        }
    }

    // MARK: - Metadata persistence

    private static func metadataAccount(for id: UUID) -> String {
        metadataAccountPrefix + id.uuidString.lowercased()
    }

    private func persist(_ key: SDKAPIKey) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(key)
        } catch {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not store the developer API key.",
                diagnostics: ["reason": "metadata-encode-failed"]
            )
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not store the developer API key.",
                diagnostics: ["reason": "metadata-utf8-failed"]
            )
        }
        try SDKKeychain.set(json, forKey: Self.metadataAccount(for: key.id))
    }

    private func decodeMetadata(_ json: String) throws -> SDKAPIKey {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = json.data(using: .utf8) else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The stored developer API key metadata is corrupt.",
                diagnostics: ["reason": "metadata-utf8-failed"]
            )
        }
        do {
            return try decoder.decode(SDKAPIKey.self, from: data)
        } catch {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The stored developer API key metadata is corrupt.",
                diagnostics: ["reason": "metadata-decode-failed"]
            )
        }
    }

    /// Loads metadata for `id`. Unknown IDs and Keychain read failures both
    /// surface as `.apiKeyInvalid` here: at the authorization boundary, "the
    /// host cannot establish this key" and "this key does not exist" must not
    /// be distinguishable to the presenter of the secret.
    private func loadMetadata(id: UUID) throws -> SDKAPIKey {
        let account = Self.metadataAccount(for: id)
        let stored: String?
        do {
            stored = try SDKKeychain.get(forKey: account)
        } catch {
            throw apiKeyInvalidError()
        }
        guard let json = stored else {
            throw apiKeyInvalidError()
        }
        do {
            return try decodeMetadata(json)
        } catch {
            // Corrupt metadata for a presented secret: fail closed as invalid
            // rather than leaking a service-level distinction.
            throw apiKeyInvalidError()
        }
    }

    private func apiKeyInvalidError() -> SDKError {
        SDKError(
            code: .apiKeyInvalid,
            message: "The developer API key is invalid or could not be verified.",
            suggestion: "Check the key for typos, or generate a new key in Studio → Settings → Developer API Keys."
        )
    }

    /// An expired key is an invalid key: same `.apiKeyInvalid` code (no new
    /// oracle), with a message that tells the key holder the actual cause.
    private func apiKeyExpiredError() -> SDKError {
        SDKError(
            code: .apiKeyInvalid,
            message: "This developer API key has expired.",
            suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
        )
    }
}
