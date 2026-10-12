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
//
// All timestamps are real (`Date()`). Keychain failures surface as
// `.serviceUnavailable`; unknown/malformed/forged secrets surface as
// `.apiKeyInvalid` (one code for all three, so failure modes are not
// distinguishable); revoked keys surface as `.apiKeyRevoked`.

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
        isLive: Bool
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

        let key = SDKAPIKey(
            keyPrefix: isLive ? SDKAPIKeyCodec.livePrefix : SDKAPIKeyCodec.testPrefix,
            label: trimmedLabel,
            scopes: scopes,
            createdAt: Date()
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
    /// Every call: parses and HMAC-verifies the secret, loads fresh metadata
    /// from the Keychain, rejects revoked keys (`.apiKeyRevoked`), and
    /// updates `lastUsedAt`. Unknown IDs, malformed secrets, and signature
    /// mismatches all surface as `.apiKeyInvalid` — deliberately
    /// indistinguishable.
    ///
    /// Keychain failures fail closed (`.serviceUnavailable`): when the host
    /// cannot establish key validity, the action is denied.
    public func verify(secret: String) throws -> SDKAPIKey {
        let deviceKey = try getOrCreateDeviceKey()
        let (id, prefix) = try SDKAPIKeyCodec.parseAndVerify(secret, deviceKey: deviceKey)
        var key = try loadMetadata(id: id)
        // Defense in depth: the signature already binds the prefix, but the
        // stored metadata must agree with what was presented.
        guard key.keyPrefix == prefix else {
            throw apiKeyInvalidError()
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
        return key
    }

    // MARK: - Revocation

    /// Revokes the key with `id`, effective immediately: `verify(secret:)`
    /// checks `revokedAt` on every call, so no session can outlive this.
    /// Revoking an already-revoked key succeeds (idempotent).
    /// Revoking an unknown key ID throws `.apiKeyInvalid`.
    public func revoke(id: UUID) throws {
        var key = try loadMetadata(id: id)
        guard key.revokedAt == nil else { return }
        key.revokedAt = Date()
        try persist(key)
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
            if let json = try? SDKKeychain.get(forKey: account),
               let value = json,
               let key = try? decodeMetadata(value)
            {
                keys.append(key)
            }
        }
        return keys.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Scope enforcement

    /// Requires `scope` on an already-verified `key`. Throws
    /// `.apiKeyScopeInsufficient` naming the missing scope, or
    /// `.apiKeyRevoked` if the key was revoked after verification
    /// (belt-and-braces: `verify` is the primary revocation check).
    public func requireScope(_ scope: SDKAPIKeyScope, for key: SDKAPIKey) throws {
        if key.revokedAt != nil {
            throw SDKError(
                code: .apiKeyRevoked,
                message: "This developer API key was revoked.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
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
}
