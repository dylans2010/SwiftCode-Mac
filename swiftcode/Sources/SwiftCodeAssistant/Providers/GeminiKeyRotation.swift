import Foundation

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

public struct AlternativeKeyStoreData: Codable, Sendable, Equatable {
    public var keys: [AlternativeKeyMetadata]
    public var activeKeyId: UUID?

    public init(keys: [AlternativeKeyMetadata] = [], activeKeyId: UUID? = nil) {
        self.keys = keys
        self.activeKeyId = activeKeyId
    }
}

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

    public static func maskKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            return "••••••••"
        }
        let prefix = trimmed.hasPrefix("AIza") ? "AIza" : String(trimmed.prefix(4))
        let suffix = String(trimmed.suffix(4))
        return "\(prefix)••••••••••••\(suffix)"
    }

    public static func hashKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return SHA256.hash(Data(trimmed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func isValidGeminiKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20, trimmed.count <= 120 else { return false }
        guard !trimmed.contains(" ") && !trimmed.contains("\t") && !trimmed.contains("\n") else { return false }
        return true
    }

    private func keyAccount(for id: UUID) -> String {
        "\(SecretAccount.geminiAltKeyPrefix)\(id.uuidString)"
    }

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

    public func markRateLimited(id: UUID, retryAfterSeconds: TimeInterval? = nil) {
        guard let idx = data.keys.firstIndex(where: { $0.id == id }) else { return }
        let cooldown = max(2.0, retryAfterSeconds ?? 60.0)
        data.keys[idx].state = .rateLimited
        data.keys[idx].rateLimitedUntil = Date().addingTimeInterval(cooldown)
        data.keys[idx].failureCount += 1
        save()
    }

    public func markHealthy(id: UUID) {
        guard let idx = data.keys.firstIndex(where: { $0.id == id }) else { return }
        if data.keys[idx].state == .rateLimited || data.keys[idx].state == .failed {
            data.keys[idx].state = .ready
        }
        data.keys[idx].rateLimitedUntil = nil
        data.keys[idx].successCount += 1
        save()
    }

    public func markFailed(id: UUID, isPermanentAuthError: Bool = false) {
        guard let idx = data.keys.firstIndex(where: { $0.id == id }) else { return }
        data.keys[idx].state = isPermanentAuthError ? .invalid : .failed
        data.keys[idx].failureCount += 1
        save()
    }

    @discardableResult
    public func rotateNow() -> AlternativeKeyMetadata? {
        guard let next = selectNextAvailableKey(excludingId: data.activeKeyId) else {
            return nil
        }
        return next.metadata
    }

    public func resetHealth() {
        for i in data.keys.indices {
            if data.keys[i].state != .disabled && data.keys[i].state != .invalid {
                data.keys[i].state = .ready
                data.keys[i].rateLimitedUntil = nil
            }
        }
        save()
    }

    private func save() {
        try? store.writeJSON(data, for: metadataAccount)
    }
}
