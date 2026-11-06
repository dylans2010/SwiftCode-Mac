//
//  AlternativeKeyManager.swift
//  SwiftCode
//
//  Secure credential manager and automatic rotation engine for alternative Gemini API keys.
//

import Foundation
import CryptoKit
import Observation
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "AlternativeKeys")

public enum AlternativeKeyState: String, Codable, Sendable {
    case ready = "Ready"
    case active = "Active"
    case rateLimited = "Rate Limited"
    case invalid = "Invalid"
    case failed = "Failed"
    case disabled = "Disabled"
}

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

public struct KeyImportResult: Sendable {
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

@Observable
@MainActor
public final class AlternativeKeyManager: Sendable {
    public static let shared = AlternativeKeyManager()

    public var keys: [AlternativeKeyMetadata] = []
    public var activeKeyId: UUID? = nil

    private let metadataKey = "com.swiftcode.gemini.altkeys.metadata"
    private let activeKeyIdKey = "com.swiftcode.gemini.altkeys.active_id"
    private let keychainPrefix = "com.swiftcode.gemini.altkey."

    private init() {
        loadMetadata()
    }

    // MARK: - Key Hashing & Masking

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
        let hash = SHA256.hash(data: Data(trimmed.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    public static func isValidGeminiKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20, trimmed.count <= 120 else { return false }
        guard !trimmed.contains(" ") && !trimmed.contains("\t") && !trimmed.contains("\n") else { return false }
        return true
    }

    private func keychainAccount(for id: UUID) -> String {
        "\(keychainPrefix)\(id.uuidString)"
    }

    // MARK: - Import & Management

    @discardableResult
    public func importRawKeys(_ text: String) -> KeyImportResult {
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
            if seenInBatch.contains(hash) || keys.contains(where: { $0.keyHash == hash }) {
                dupCount += 1
                continue
            }
            seenInBatch.insert(hash)

            let id = UUID()
            let masked = Self.maskKey(raw)
            let stored = KeychainService.shared.set(raw, forKey: keychainAccount(for: id))
            guard stored else {
                invalidCount += 1
                continue
            }

            let meta = AlternativeKeyMetadata(
                id: id,
                maskedValue: masked,
                keyHash: hash,
                state: .ready,
                orderIndex: keys.count
            )
            keys.append(meta)
            newCount += 1
        }

        saveMetadata()
        if activeKeyId == nil, let first = keys.first(where: { $0.isAvailableForUse }) {
            activeKeyId = first.id
        }

        logger.info("[AlternativeKeyManager] Imported raw keys: total=\(total), new=\(newCount), dup=\(dupCount), invalid=\(invalidCount)")
        return KeyImportResult(
            totalDetected: total,
            newKeysAdded: newCount,
            duplicatesRemoved: dupCount,
            invalidKeysRejected: invalidCount
        )
    }

    public func removeKey(id: UUID) {
        KeychainService.shared.delete(forKey: keychainAccount(for: id))
        keys.removeAll { $0.id == id }
        if activeKeyId == id {
            activeKeyId = keys.first(where: { $0.isAvailableForUse })?.id
        }
        reindexOrder()
        saveMetadata()
    }

    public func removeAllKeys() {
        for key in keys {
            KeychainService.shared.delete(forKey: keychainAccount(for: key.id))
        }
        keys.removeAll()
        activeKeyId = nil
        saveMetadata()
    }

    public func reorderKeys(from source: IndexSet, to destination: Int) {
        keys.move(fromOffsets: source, toOffset: destination)
        reindexOrder()
        saveMetadata()
    }

    private func reindexOrder() {
        for i in keys.indices {
            keys[i].orderIndex = i
        }
    }

    // MARK: - Key Retrieval & Rotation

    public func getActiveOrNextKey() -> (key: String, metadata: AlternativeKeyMetadata)? {
        if let activeId = activeKeyId, let idx = keys.firstIndex(where: { $0.id == activeId }) {
            let meta = keys[idx]
            if meta.isAvailableForUse {
                if let raw = KeychainService.shared.get(forKey: keychainAccount(for: meta.id)) {
                    keys[idx].lastUsed = Date()
                    keys[idx].state = .active
                    saveMetadata()
                    return (raw, keys[idx])
                }
            }
        }
        return selectNextAvailableKey()
    }

    public func selectNextAvailableKey(excludingId: UUID? = nil) -> (key: String, metadata: AlternativeKeyMetadata)? {
        let available = keys.filter { $0.isAvailableForUse && $0.id != excludingId }
        guard !available.isEmpty else {
            logger.warning("[AlternativeKeyManager] No usable alternative keys available.")
            return nil
        }

        let currentIndex = keys.firstIndex(where: { $0.id == activeKeyId }) ?? -1
        let sortedCandidates = available.sorted { a, b in
            if a.failureCount != b.failureCount {
                return a.failureCount < b.failureCount
            }
            let distA = (a.orderIndex - currentIndex + keys.count) % keys.count
            let distB = (b.orderIndex - currentIndex + keys.count) % keys.count
            return distA < distB
        }

        guard let chosen = sortedCandidates.first,
              let rawKey = KeychainService.shared.get(forKey: keychainAccount(for: chosen.id)) else {
            return nil
        }

        if let idx = keys.firstIndex(where: { $0.id == chosen.id }) {
            if let prevId = activeKeyId, let prevIdx = keys.firstIndex(where: { $0.id == prevId }) {
                if keys[prevIdx].state == .active {
                    keys[prevIdx].state = .ready
                }
            }
            activeKeyId = chosen.id
            keys[idx].state = .active
            keys[idx].lastUsed = Date()
            saveMetadata()
            logger.info("[AlternativeKeyManager] Selected next active key: \(chosen.maskedValue, privacy: .public)")
            return (rawKey, keys[idx])
        }

        return nil
    }

    public func markRateLimited(id: UUID, retryAfterSeconds: TimeInterval? = nil) {
        guard let idx = keys.firstIndex(where: { $0.id == id }) else { return }
        let cooldown = max(2.0, retryAfterSeconds ?? 60.0)
        keys[idx].state = .rateLimited
        keys[idx].rateLimitedUntil = Date().addingTimeInterval(cooldown)
        keys[idx].failureCount += 1
        saveMetadata()
        logger.warning("[AlternativeKeyManager] Key marked rate limited until \(self.keys[idx].rateLimitedUntil?.description ?? "unknown"): \(self.keys[idx].maskedValue, privacy: .public)")
    }

    public func markHealthy(id: UUID) {
        guard let idx = keys.firstIndex(where: { $0.id == id }) else { return }
        if keys[idx].state == .rateLimited || keys[idx].state == .failed {
            keys[idx].state = .ready
        }
        keys[idx].rateLimitedUntil = nil
        keys[idx].successCount += 1
        saveMetadata()
    }

    public func markFailed(id: UUID, isPermanentAuthError: Bool = false) {
        guard let idx = keys.firstIndex(where: { $0.id == id }) else { return }
        keys[idx].state = isPermanentAuthError ? .invalid : .failed
        keys[idx].failureCount += 1
        saveMetadata()
        logger.error("[AlternativeKeyManager] Key marked failed (invalid=\(isPermanentAuthError)): \(self.keys[idx].maskedValue, privacy: .public)")
    }

    @discardableResult
    public func rotateNow() -> AlternativeKeyMetadata? {
        guard let next = selectNextAvailableKey(excludingId: activeKeyId) else {
            return nil
        }
        return next.metadata
    }

    public func resetHealth() {
        for i in keys.indices {
            if keys[i].state != .disabled && keys[i].state != .invalid {
                keys[i].state = .ready
                keys[i].rateLimitedUntil = nil
            }
        }
        saveMetadata()
    }

    // MARK: - Persistence (Metadata Only)

    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
        if let aid = activeKeyId {
            UserDefaults.standard.set(aid.uuidString, forKey: activeKeyIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKeyIdKey)
        }
    }

    private func loadMetadata() {
        if let idStr = UserDefaults.standard.string(forKey: activeKeyIdKey) {
            self.activeKeyId = UUID(uuidString: idStr)
        }
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let decoded = try? JSONDecoder().decode([AlternativeKeyMetadata].self, from: data) else {
            return
        }
        self.keys = decoded
    }
}
