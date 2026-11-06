import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "LocalCloudCache")

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
        logger.info("Loaded \(records.count) records from local cloud cache disk storage synchronously during init.")
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
