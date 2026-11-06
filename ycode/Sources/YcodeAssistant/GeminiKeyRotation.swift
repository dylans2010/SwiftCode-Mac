import Foundation

// MARK: - Gemini alternative-key rotation (Wave 16, Slice D)
//
// Ported from Legacy (Dylan's own code; direct port authorised under
// MIT, spec-first where it costs nothing):
//   * `SwiftCode/Backend/Assist/AlternativeKeyManager.swift` —
//     `AlternativeKeyState`, `AlternativeKeyMetadata`,
//     `KeyImportResult`, import / removal / selection /
//     rate-limit / failure-counting / rotation rules.
//
// Legacy kept raw keys in the Keychain (`com.swiftcode.gemini.
// altkey.<uuid>`) and metadata in UserDefaults. Ycode keeps raw
// keys in the `SecretStore` (`gemini.alt-key.<uuid>`, Keychain on
// macOS, a 0600 file on Linux) and the metadata envelope in the
// same store (`gemini.alt-keys.metadata`). The metadata holds only
// masked values and SHA-256 hashes — never a raw key — and it is
// the manager's index, because `SecretStore` has no enumeration:
// if the metadata is deleted, any stored raw keys become
// unreachable orphans (they stay in the store until the user
// removes them by re-importing, which dedups by hash).
//
// Adaptations:
//   * No `@Observable` / `@MainActor` singleton: this is an actor
//     the host owns (`GeminiKeyRotationManager(store:)`). There is
//     no `shared` — the host creates one per secret store, which
//     is what makes the manager testable with `MemorySecretStore`.
//   * No `os.Logger`: the manager is silent. Callers log the
//     masked value when they rotate, as the router does.
//   * No `reorderKeys(from:to:)` with `IndexSet` (AppKit type):
//     `reorderKeys(_:)` takes the ordered ids instead.
//   * SHA-256 uses YcodeAssistant's own pure-Swift `SHA256`
//     (`Crypto.swift`), so the manager builds on Linux without
//     CryptoKit. The hash is the same SHA-256 Legacy computed
//     with CryptoKit.

// MARK: - Types

/// The state of one alternative key (Legacy
/// `AlternativeKeyState`, verbatim).
public enum AlternativeKeyState: String, Codable, Sendable {
    case ready = "Ready"
    case active = "Active"
    case rateLimited = "Rate Limited"
    case invalid = "Invalid"
    case failed = "Failed"
    case disabled = "Disabled"
}

/// Metadata for one alternative key (Legacy
/// `AlternativeKeyMetadata`, verbatim). `maskedValue` and
/// `keyHash` are safe to show and store; the raw key is never
/// in this struct.
public struct AlternativeKeyMetadata: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let maskedValue: String
    public let keyHash: String
    public var state: AlternativeKeyState
    public var lastUsed: Date?
    public var rateLimitedUntil: Date?
    public var failureCount: Int
    public var successCount: Int
    public var orderIndex: Int
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        maskedValue: String,
        keyHash: String,
        state: AlternativeKeyState = .ready,
        lastUsed: Date? = nil,
        rateLimitedUntil: Date? = nil,
        failureCount: Int = 0,
        successCount: Int = 0,
        orderIndex: Int = 0,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.maskedValue = maskedValue
        self.keyHash = keyHash
        self.state = state
        self.lastUsed = lastUsed
        self.rateLimitedUntil = rateLimitedUntil
        self.failureCount = failureCount
        self.successCount = successCount
        self.orderIndex = orderIndex
        self.addedAt = addedAt
    }

    /// True while the key is inside its rate-limit cooldown
    /// (Legacy `isCurrentlyRateLimited`, verbatim: a
    /// `.rateLimited` state whose `until` has passed no longer
    /// counts, even though the state still reads rate-limited
    /// until the next successful use clears it).
    public var isCurrentlyRateLimited: Bool {
        if state == .rateLimited {
            if let until = rateLimitedUntil, Date() < until {
                return true
            }
        }
        return false
    }

    public var isAvailableForUse: Bool {
        if state == .invalid || state == .disabled { return false }
        if isCurrentlyRateLimited { return false }
        return true
    }
}

/// The outcome of importing a block of pasted keys (Legacy
/// `KeyImportResult`, verbatim).
public struct KeyImportResult: Sendable, Equatable {
    public let totalDetected: Int
    public let newKeysAdded: Int
    public let duplicatesRemoved: Int
    public let invalidKeysRejected: Int

    public init(totalDetected: Int, newKeysAdded: Int, duplicatesRemoved: Int, invalidKeysRejected: Int) {
        self.totalDetected = totalDetected
        self.newKeysAdded = newKeysAdded
        self.duplicatesRemoved = duplicatesRemoved
        self.invalidKeysRejected = invalidKeysRejected
    }
}

/// The persisted envelope: the key list plus the active key id
/// (Legacy persisted the same two values under two UserDefaults
/// keys; Ycode stores one envelope in the secret store).
public struct AlternativeKeyStoreData: Codable, Sendable, Equatable {
    public var keys: [AlternativeKeyMetadata]
    public var activeKeyId: UUID?

    public init(keys: [AlternativeKeyMetadata] = [], activeKeyId: UUID? = nil) {
        self.keys = keys
        self.activeKeyId = activeKeyId
    }
}

// MARK: - Manager

/// Secure storage and automatic rotation for alternative Gemini
/// API keys (Legacy `AlternativeKeyManager`).
public actor GeminiKeyRotationManager {
    private let store: SecretStore
    private let metadataAccount: String
    private var data: AlternativeKeyStoreData

    public init(store: SecretStore, metadataAccount: String = SecretAccount.geminiAltKeysMetadata) {
        self.store = store
        self.metadataAccount = metadataAccount
        self.data = (try? store.readJSON(AlternativeKeyStoreData.self, metadataAccount)) ?? AlternativeKeyStoreData()
    }

    public var keys: [AlternativeKeyMetadata] { data.keys }
    public var activeKeyId: UUID? { data.activeKeyId }

    // MARK: - Key hashing & masking

    /// The display form of a key: the `AIza` prefix (or first
    /// four characters) + bullets + the last four characters.
    /// Short keys show only bullets (Legacy `maskKey`, verbatim).
    public static func maskKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            return "••••••••"
        }
        let prefix = trimmed.hasPrefix("AIza") ? "AIza" : String(trimmed.prefix(4))
        let suffix = String(trimmed.suffix(4))
        return "\(prefix)••••••••••••\(suffix)"
    }

    /// The SHA-256 hex of a key (Legacy `hashKey`, verbatim —
    /// same digest, computed with Ycode's pure-Swift SHA-256).
    public static func hashKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return SHA256.hash(Data(trimmed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A plausible Gemini key: 20–120 characters, no whitespace
    /// (Legacy `isValidGeminiKey`, verbatim).
    public static func isValidGeminiKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20, trimmed.count <= 120 else { return false }
        guard !trimmed.contains(" ") && !trimmed.contains("\t") && !trimmed.contains("\n") else { return false }
        return true
    }

    private func keyAccount(for id: UUID) -> String {
        "\(SecretAccount.geminiAltKeyPrefix)\(id.uuidString)"
    }

    // MARK: - Import & management

    /// Imports keys pasted as text (comma / newline / `;`
    /// separated, surrounding quotes stripped). Duplicates are
    /// detected by hash, against both this batch and the stored
    /// keys; a key whose raw value cannot be stored counts as
    /// invalid (Legacy `importRawKeys`, verbatim).
    @discardableResult
    public func importKeys(_ text: String) -> KeyImportResult {
        let separators = CharacterSet(charactersIn: ",\n\r;")
        let rawCandidates = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`")) }
            .filter { !$0.isEmpty }

        var total = 0
        var newCount = 0
        var dupCount = 0
        var invalidCount = 0
        var seenInBatch = Set<String>()

        for raw in rawCandidates {
            total += 1
            guard Self.isValidGeminiKey(raw) else {
                invalidCount += 1
                continue
            }
            let hash = Self.hashKey(raw)
            if seenInBatch.contains(hash) || data.keys.contains(where: { $0.keyHash == hash }) {
                dupCount += 1
                continue
            }
            seenInBatch.insert(hash)
            let id = UUID()
            let masked = Self.maskKey(raw)
            do {
                try store.write(Data(raw.utf8), for: keyAccount(for: id))
            } catch {
                invalidCount += 1
                continue
            }
            let meta = AlternativeKeyMetadata(
                id: id,
                maskedValue: masked,
                keyHash: hash,
                state: .ready,
                orderIndex: data.keys.count
            )
            data.keys.append(meta)
            newCount += 1
        }

        save()
        if data.activeKeyId == nil, let first = data.keys.first(where: { $0.isAvailableForUse }) {
            data.activeKeyId = first.id
            save()
        }
        return KeyImportResult(
            totalDetected: total,
            newKeysAdded: newCount,
            duplicatesRemoved: dupCount,
            invalidKeysRejected: invalidCount
        )
    }

    public func removeKey(id: UUID) {
        try? store.delete(keyAccount(for: id))
        data.keys.removeAll { $0.id == id }
        if data.activeKeyId == id {
            data.activeKeyId = data.keys.first(where: { $0.isAvailableForUse })?.id
        }
        reindexOrder()
        save()
    }

    public func removeAllKeys() {
        for key in data.keys {
            try? store.delete(keyAccount(for: key.id))
        }
        data.keys.removeAll()
        data.activeKeyId = nil
        save()
    }

    /// Reorders the keys to the given id order (ids not listed
    /// keep their relative order at the end). Legacy used
    /// `IndexSet`; this host has no AppKit type to take.
    public func reorderKeys(_ orderedIDs: [UUID]) {
        var reordered: [AlternativeKeyMetadata] = []
        for id in orderedIDs {
            if let key = data.keys.first(where: { $0.id == id }) {
                reordered.append(key)
            }
        }
        for key in data.keys where !orderedIDs.contains(key.id) {
            reordered.append(key)
        }
        data.keys = reordered
        reindexOrder()
        save()
    }

    private func reindexOrder() {
        for i in data.keys.indices {
            data.keys[i].orderIndex = i
        }
    }

    // MARK: - Key retrieval & rotation

    /// The active key when it is usable, otherwise the next
    /// available key. Marks the returned key `.active` and stamps
    /// `lastUsed` (Legacy `getActiveOrNextKey`, verbatim).
    public func getActiveOrNextKey() -> (key: String, metadata: AlternativeKeyMetadata)? {
        if let activeId = data.activeKeyId, let idx = data.keys.firstIndex(where: { $0.id == activeId }) {
            let meta = data.keys[idx]
            if meta.isAvailableForUse {
                if let raw = store.readString(keyAccount(for: meta.id)) {
                    data.keys[idx].lastUsed = Date()
                    data.keys[idx].state = .active
                    save()
                    return (raw, data.keys[idx])
                }
            }
        }
        return selectNextAvailableKey()
    }

    /// The next usable key: fewest failures first, then the
    /// shortest circular distance from the active key's position
    /// (Legacy `selectNextAvailableKey`, verbatim). The previous
    /// active key returns to `.ready`. Returns nil when no key
    /// is usable.
    public func selectNextAvailableKey(excludingId: UUID? = nil) -> (key: String, metadata: AlternativeKeyMetadata)? {
        let available = data.keys.filter { $0.isAvailableForUse && $0.id != excludingId }
        guard !available.isEmpty else { return nil }

        let currentIndex = data.keys.firstIndex(where: { $0.id == data.activeKeyId }) ?? -1
        let sortedCandidates = available.sorted { a, b in
            if a.failureCount != b.failureCount {
                return a.failureCount < b.failureCount
            }
            let distA = (a.orderIndex - currentIndex + data.keys.count) % data.keys.count
            let distB = (b.orderIndex - currentIndex + data.keys.count) % data.keys.count
            return distA < distB
        }

        guard let chosen = sortedCandidates.first,
              let rawKey = store.readString(keyAccount(for: chosen.id)) else {
            return nil
        }

        if let idx = data.keys.firstIndex(where: { $0.id == chosen.id }) {
            if let prevId = data.activeKeyId, let prevIdx = data.keys.firstIndex(where: { $0.id == prevId }) {
                if data.keys[prevIdx].state == .active {
                    data.keys[prevIdx].state = .ready
                }
            }
            data.activeKeyId = chosen.id
            data.keys[idx].state = .active
            data.keys[idx].lastUsed = Date()
            save()
            return (rawKey, data.keys[idx])
        }
        return nil
    }

    /// Marks a key rate-limited for `retryAfterSeconds`
    /// (default 60s, minimum 2s) and counts a failure (Legacy
    /// `markRateLimited`, verbatim).
    public func markRateLimited(id: UUID, retryAfterSeconds: TimeInterval? = nil) {
        guard let idx = data.keys.firstIndex(where: { $0.id == id }) else { return }
        let cooldown = max(2.0, retryAfterSeconds ?? 60.0)
        data.keys[idx].state = .rateLimited
        data.keys[idx].rateLimitedUntil = Date().addingTimeInterval(cooldown)
        data.keys[idx].failureCount += 1
        save()
    }

    /// Marks a key healthy after a successful use: clears a
    /// rate-limit / failure state and counts a success (Legacy
    /// `markHealthy`, verbatim).
    public func markHealthy(id: UUID) {
        guard let idx = data.keys.firstIndex(where: { $0.id == id }) else { return }
        if data.keys[idx].state == .rateLimited || data.keys[idx].state == .failed {
            data.keys[idx].state = .ready
        }
        data.keys[idx].rateLimitedUntil = nil
        data.keys[idx].successCount += 1
        save()
    }

    /// Marks a key failed; a permanent auth error marks it
    /// `.invalid` instead (Legacy `markFailed`, verbatim).
    public func markFailed(id: UUID, isPermanentAuthError: Bool = false) {
        guard let idx = data.keys.firstIndex(where: { $0.id == id }) else { return }
        data.keys[idx].state = isPermanentAuthError ? .invalid : .failed
        data.keys[idx].failureCount += 1
        save()
    }

    /// Rotates to the next available key right now, or nil when
    /// no other key is usable (Legacy `rotateNow`, verbatim).
    @discardableResult
    public func rotateNow() -> AlternativeKeyMetadata? {
        guard let next = selectNextAvailableKey(excludingId: data.activeKeyId) else {
            return nil
        }
        return next.metadata
    }

    /// Clears rate-limit / failure states (`.disabled` and
    /// `.invalid` are left alone) (Legacy `resetHealth`,
    /// verbatim).
    public func resetHealth() {
        for i in data.keys.indices {
            if data.keys[i].state != .disabled && data.keys[i].state != .invalid {
                data.keys[i].state = .ready
                data.keys[i].rateLimitedUntil = nil
            }
        }
        save()
    }

    // MARK: - Persistence (metadata only)

    private func save() {
        try? store.writeJSON(data, for: metadataAccount)
    }
}
