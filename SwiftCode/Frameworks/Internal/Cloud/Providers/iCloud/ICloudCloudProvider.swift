import Foundation
import CloudKit
import os.log

public final class ICloudCloudProvider: NSObject, CloudProvider, SyncProvider, BackupProvider, StorageProvider, Sendable {
    public let type: CloudProviderType = .icloud
    public let isEnabled: Bool = true
    public let name: String = "Apple iCloud"

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ICloudProvider")
    private let database: CKDatabase = CKContainer.default().privateCloudDatabase

    public override init() {
        super.init()
    }

    public func initialize() async throws {
        logger.info("Initializing CloudKit Custom Sync Zone...")
        // Real zone creation in Private Database for granular synchronization control
        let customZone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName))
        do {
            _ = try await database.modifyRecordZones(saving: [customZone], deleting: [])
            logger.info("CloudKit Custom Sync Zone configured successfully.")
        } catch {
            logger.error("CloudKit Zone creation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func testConnection() async -> Bool {
        let status = await ICloudKitService.shared.getAccountStatus()
        return status == .available
    }

    // MARK: - SyncProvider (CloudKit Private Record Syncing)

    public func pushChanges(_ payloads: [SyncPayload]) async throws -> [String] {
        logger.info("Pushing updates to CloudKit database...")
        var succeededIDs: [String] = []
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)

        var recordsToSave: [CKRecord] = []

        for payload in payloads {
            let recordID = CKRecord.ID(recordName: payload.resourceID, zoneID: zoneID)
            let record = CKRecord(recordType: "SyncPayload", recordID: recordID)
            record["table"] = payload.table as CKRecordValue
            record["data"] = payload.data as CKRecordValue
            record["lastModified"] = payload.lastModified as CKRecordValue
            record["version"] = payload.version as CKRecordValue
            recordsToSave.append(record)
        }

        guard !recordsToSave.isEmpty else { return [] }

        do {
            let result = try await database.modifyRecords(saving: recordsToSave, deleting: [], savePolicy: .changedKeys)
            for savedRecord in result.saveResults {
                succeededIDs.append(savedRecord.key.recordName)
            }
            logger.info("Successfully pushed \(succeededIDs.count) records to CloudKit.")
        } catch {
            logger.error("CloudKit batch push operation failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        return succeededIDs
    }

    public func pullChanges(since lastSync: Date) async throws -> [SyncPayload] {
        logger.info("Pulling incremental changes from CloudKit...")
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)
        let predicate = NSPredicate(format: "lastModified > %@", lastSync as NSDate)
        let query = CKQuery(recordType: "SyncPayload", predicate: predicate)

        var pulledPayloads: [SyncPayload] = []

        do {
            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID, desiredKeys: nil, resultsLimit: 100)
            for (_, matchResult) in matchResults {
                if case .success(let record) = matchResult {
                    guard let table = record["table"] as? String,
                          let data = record["data"] as? Data,
                          let lastMod = record["lastModified"] as? Date,
                          let version = record["version"] as? Int else { continue }

                    let payload = SyncPayload(
                        resourceID: record.recordID.recordName,
                        table: table,
                        data: data,
                        lastModified: lastMod,
                        version: version
                    )
                    pulledPayloads.append(payload)
                }
            }
            logger.info("Successfully pulled \(pulledPayloads.count) new payloads from CloudKit.")
        } catch {
            logger.error("CloudKit query execution failed: \(error.localizedDescription, privacy: .public)")
        }

        return pulledPayloads
    }

    // MARK: - BackupProvider (CloudKit CKAsset Integration)

    public func uploadBackup(archiveData: Data, filename: String, manifestJSON: String) async throws {
        logger.info("Uploading database backup to CloudKit...")
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: filename, zoneID: zoneID)
        let record = CKRecord(recordType: "Backup", recordID: recordID)

        // Write raw data to a temporary file for CKAsset tracking
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(filename)
        try archiveData.write(to: tempURL)

        record["filename"] = filename as CKRecordValue
        record["size_bytes"] = Int64(archiveData.count) as CKRecordValue
        record["manifest"] = manifestJSON as CKRecordValue
        record["fileAsset"] = CKAsset(fileURL: tempURL)

        do {
            _ = try await database.save(record)
            logger.info("Backup archive saved in CloudKit successfully.")
            // Delete temp file cleanly
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            logger.error("Failed to upload backup to CloudKit: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    public func downloadBackup(filename: String) async throws -> (Data, String) {
        logger.info("Downloading backup archive from CloudKit...")
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: filename, zoneID: zoneID)

        do {
            let record = try await database.record(for: recordID)
            guard let asset = record["fileAsset"] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let manifest = record["manifest"] as? String else {
                throw NSError(domain: "CloudKitBackup", code: 404, userInfo: [NSLocalizedDescriptionKey: "Backup asset or metadata missing in record"])
            }

            let data = try Data(contentsOf: fileURL)
            return (data, manifest)
        } catch {
            logger.error("CloudKit backup download failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func listBackups() async throws -> [String] {
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)
        let query = CKQuery(recordType: "Backup", predicate: NSPredicate(value: true))

        do {
            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID, desiredKeys: ["filename"], resultsLimit: 100)
            var filenames: [String] = []
            for (_, matchResult) in matchResults {
                if case .success(let record) = matchResult,
                   let name = record["filename"] as? String {
                    filenames.append(name)
                }
            }
            return filenames
        } catch {
            logger.error("CloudKit listing backups failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func deleteBackup(filename: String) async throws {
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: filename, zoneID: zoneID)
        do {
            _ = try await database.deleteRecord(withID: recordID)
            logger.info("Backup record deleted from CloudKit.")
        } catch {
            logger.error("Failed to delete CloudKit backup: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - StorageProvider (Generic CloudKit storage containers)

    public func uploadFile(bucket: String, path: String, data: Data, contentType: String) async throws -> URL {
        logger.info("Uploading storage asset to CloudKit: \(bucket, privacy: .public)/\(path, privacy: .public)...")
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)
        let safePath = path.replacingOccurrences(of: "/", with: "_")
        let recordID = CKRecord.ID(recordName: "\(bucket)_\(safePath)", zoneID: zoneID)
        let record = CKRecord(recordType: "StorageObject", recordID: recordID)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(safePath)
        try data.write(to: tempURL)

        record["bucket"] = bucket as CKRecordValue
        record["path"] = path as CKRecordValue
        record["contentType"] = contentType as CKRecordValue
        record["asset"] = CKAsset(fileURL: tempURL)

        do {
            _ = try await database.save(record)
            try? FileManager.default.removeItem(at: tempURL)
            return URL(string: "https://icloud.com/drive/\(bucket)/\(path)")!
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            logger.error("CloudKit upload failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func downloadFile(bucket: String, path: String) async throws -> Data {
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)
        let safePath = path.replacingOccurrences(of: "/", with: "_")
        let recordID = CKRecord.ID(recordName: "\(bucket)_\(safePath)", zoneID: zoneID)

        do {
            let record = try await database.record(for: recordID)
            guard let asset = record["asset"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                throw NSError(domain: "CloudKitStorage", code: 404, userInfo: [NSLocalizedDescriptionKey: "Storage asset not found"])
            }
            return try Data(contentsOf: fileURL)
        } catch {
            logger.error("CloudKit download failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func deleteFile(bucket: String, path: String) async throws {
        let zoneID = CKRecordZone.ID(zoneName: "SwiftCodeCustomSyncZone", ownerName: CKCurrentUserDefaultName)
        let safePath = path.replacingOccurrences(of: "/", with: "_")
        let recordID = CKRecord.ID(recordName: "\(bucket)_\(safePath)", zoneID: zoneID)

        do {
            _ = try await database.deleteRecord(withID: recordID)
        } catch {
            logger.error("CloudKit deletion failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
