import Foundation

/// The in-memory local cloud cache, backed by `CloudPersistence`.
/// Ported verbatim from Legacy's `LocalCloudCache.swift` (46 lines):
/// records are keyed by `"\(recordType):\(recordKey)"`, every
/// mutation rewrites the whole cache file, and `clear()` empties
/// both memory and disk.
///
/// This cache holds `CloudRecord` payloads only. It is the store
/// `CloudManager.handleLogout` clears, and the store
/// `CloudSyncEngine` never actually fills — Legacy never wired a
/// remote source into it, so neither does this port.
public actor LocalCloudCache {
    public static let shared = LocalCloudCache()

    private var cachedRecords: [String: CloudRecord] = [:]
    private let persistence = CloudPersistence.shared

    private init() {
        let records = persistence.loadFromDisk()
        for record in records {
            let compoundKey = "\(record.recordType):\(record.recordKey)"
            cachedRecords[compoundKey] = record
        }
    }

    public func getRecord(recordType: String, key: String) -> CloudRecord? {
        let compoundKey = "\(recordType):\(key)"
        return cachedRecords[compoundKey]
    }

    public func saveRecord(_ record: CloudRecord) {
        let compoundKey = "\(record.recordType):\(record.recordKey)"
        cachedRecords[compoundKey] = record
        persistence.saveToDisk(records: Array(cachedRecords.values))
    }

    public func removeRecord(recordType: String, key: String) {
        let compoundKey = "\(recordType):\(key)"
        cachedRecords.removeValue(forKey: compoundKey)
        persistence.saveToDisk(records: Array(cachedRecords.values))
    }

    public func getAllRecords() -> [CloudRecord] {
        return Array(cachedRecords.values)
    }

    public func clear() {
        cachedRecords.removeAll()
        persistence.clearCacheOnDisk()
    }
}
