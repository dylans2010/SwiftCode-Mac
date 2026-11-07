import CryptoKit
import Foundation
import Security

public actor SDKAPIKeyStore {

    public static let shared = SDKAPIKeyStore()

    private init() {}

    private static let deviceKeyAccount = "sdk.device-key"
    private static let metadataAccountPrefix = "sdk.apikey."
    private static let deviceKeyByteCount = 32
    private static let maxLabelLength = 128

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
        try persist(key)
        return (key, secret)
    }

    public func verify(secret: String) throws -> SDKAPIKey {
        let bucketKey = SDKAPIKeyCodec.extractPresentedKeyID(from: secret)?.uuidString
            ?? Self.unparseableBucketKey
        try checkRateLimit(bucketKey: bucketKey)

        do {
            let deviceKey = try getOrCreateDeviceKey()
            let (id, prefix) = try SDKAPIKeyCodec.parseAndVerify(secret, deviceKey: deviceKey)
            var key = try loadMetadata(id: id)
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
            if sdkError.code == .apiKeyInvalid {
                recordVerifyFailure(bucketKey: bucketKey)
            }
            throw sdkError
        }
    }

    private static let maxFailuresPerWindow = 10
    private static let attemptWindow: TimeInterval = 60
    private static let lockoutDuration: TimeInterval = 5 * 60
    private static let unparseableBucketKey = "unparseable"
    private static let maxTrackedBuckets = 1024

    private struct AttemptBucket {
        var windowStart: Date
        var failures: Int
        var lockedUntil: Date?
    }

    private var attemptBuckets: [String: AttemptBucket] = [:]

    private func checkRateLimit(bucketKey: String) throws {
        pruneBucketsIfNeeded()
        let now = Date()
        guard var bucket = attemptBuckets[bucketKey] else { return }
        if let lockedUntil = bucket.lockedUntil {
            if now < lockedUntil {
                throw rateLimitedError(lockedUntil: lockedUntil)
            }
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

    private func pruneBucketsIfNeeded() {
        guard attemptBuckets.count > Self.maxTrackedBuckets else { return }
        let now = Date()
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

    public func revoke(id: UUID) async throws {
        var key = try loadMetadata(id: id)
        guard key.revokedAt == nil else { return }
        key.revokedAt = Date()
        try persist(key)
        _ = await SDKAssistService.shared.closeSessions(forKeyID: id)
    }

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

    private func apiKeyExpiredError() -> SDKError {
        SDKError(
            code: .apiKeyInvalid,
            message: "This developer API key has expired.",
            suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
        )
    }
}
