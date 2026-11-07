import Foundation
import Testing
import YcodeAssistant
@testable import SwiftCodeCloud

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

struct CloudModelsTests {

    @Test("SHA-256 of the empty string matches the FIPS vector")
    func sha256Empty() {
        #expect(hex(SHA256Digest.hash(Data())) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("SHA-256 of abc matches the FIPS vector")
    func sha256Abc() {
        #expect(hex(SHA256Digest.hash(Data("abc".utf8))) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("SHA-256 of a 56-byte message (second-block boundary) matches the FIPS vector")
    func sha256Long() {
        let message = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
        #expect(hex(SHA256Digest.hash(Data(message.utf8))) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    @Test("deterministicUUID is stable per input and distinct per input")
    func deterministicUUID() async {
        let manager = await CloudAuthManager(store: MemorySecretStore())
        let first = await manager.deterministicUUID(from: "sc_id=ABCDEF")
        let second = await manager.deterministicUUID(from: "sc_id=ABCDEF")
        let other = await manager.deterministicUUID(from: "sc_id=123456")
        #expect(first == second)
        #expect(first != other)
    }

    @Test("dbUserID strips both sc_id= and sc_id_ prefixes to the same UUID")
    func dbUserIDStripsPrefix() async {
        let manager = await CloudAuthManager(store: MemorySecretStore())
        let plain = await manager.dbUserID(from: "ABCDEF0123456789")
        let equals = await manager.dbUserID(from: "sc_id=ABCDEF0123456789")
        let underscore = await manager.dbUserID(from: "sc_id_ABCDEF0123456789")
        #expect(plain == equals)
        #expect(plain == underscore)
    }

    @Test("ConflictResolver: higher version wins on either side")
    func conflictHigherVersionWins() {
        let local = CloudRecord(swiftcodeID: "sc_id=1", recordType: "projects", recordKey: "a", payload: [:], version: 3)
        let remote = CloudRecord(swiftcodeID: "sc_id=1", recordType: "projects", recordKey: "a", payload: [:], version: 2)
        #expect(ConflictResolver.shared.resolve(local: local, remote: remote) == local)
        #expect(ConflictResolver.shared.resolve(local: remote, remote: local) == local)
    }

    @Test("ConflictResolver: on equal versions the newer timestamp wins, ties go local")
    func conflictNewerTimestampWins() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let localOld = CloudRecord(swiftcodeID: "sc_id=1", recordType: "projects", recordKey: "a", payload: [:], version: 1, updatedAt: older)
        let remoteNew = CloudRecord(swiftcodeID: "sc_id=1", recordType: "projects", recordKey: "a", payload: [:], version: 1, updatedAt: newer)
        #expect(ConflictResolver.shared.resolve(local: localOld, remote: remoteNew) == remoteNew)
        #expect(ConflictResolver.shared.resolve(local: remoteNew, remote: localOld) == remoteNew)
        let tie = CloudRecord(swiftcodeID: "sc_id=1", recordType: "projects", recordKey: "a", payload: [:], version: 1, updatedAt: newer)
        #expect(ConflictResolver.shared.resolve(local: tie, remote: remoteNew) == tie)
    }

    @Test("CloudRecord encodes with Legacy's snake_case wire keys")
    func cloudRecordWireKeys() throws {
        let record = CloudRecord(swiftcodeID: "sc_id=1", recordType: "projects", recordKey: "a", payload: ["k": "v"])
        let data = try JSONEncoder().encode(record)
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("\"swiftcode_id\""))
        #expect(text.contains("\"record_type\""))
        #expect(text.contains("\"record_key\""))
        let decoded = try JSONDecoder().decode(CloudRecord.self, from: data)
        #expect(decoded == record)
    }

    @Test("SyncQueue is FIFO and counts pending uploads")
    func syncQueue() async {
        let queue = SyncQueue.shared
        await queue.clear()
        await queue.enqueue(SyncOperation(type: .upload, recordID: "a"))
        await queue.enqueue(SyncOperation(type: .download, recordID: "b"))
        await queue.enqueue(SyncOperation(type: .upload, recordID: "c"))
        #expect(await queue.getPendingUploadCount() == 2)
        #expect(await queue.dequeue()?.recordID == "a")
        #expect(await queue.getPendingUploadCount() == 1)
        #expect(await queue.getAll().count == 2)
        await queue.clear()
        #expect(await queue.dequeue() == nil)
    }

    @Test("CloudError messages match Legacy's text")
    func cloudErrorMessages() {
        #expect(CloudError.unauthenticated.localizedDescription == "User is not authenticated. Please sign in to access cloud services.")
        #expect(CloudError.missingSwiftCodeID.localizedDescription == "No valid permanent SwiftCode ID found. Access is restricted.")
        #expect(CloudError.networkError("down").localizedDescription == "Cloud network failure: down")
        #expect(CloudError.syncFailed("x").localizedDescription == "Cloud synchronization failed: x")
        #expect(CloudError.offline.localizedDescription.contains("offline"))
    }

    @Test("CloudSession knows when it is expired")
    func cloudSessionExpiry() {
        let live = CloudSession(userID: "u", email: "e", accessToken: "t", refreshToken: "", expiresAt: Date().addingTimeInterval(600))
        #expect(live.isExpired == false)
        let dead = CloudSession(userID: "u", email: "e", accessToken: "t", refreshToken: "", expiresAt: Date().addingTimeInterval(-600))
        #expect(dead.isExpired == true)
    }

    @Test("CloudStorageInfo usage percentage guards a zero limit")
    func cloudStorageInfo() {
        #expect(CloudStorageInfo(usedBytes: 1, limitBytes: 4).usagePercentage == 25.0)
        #expect(CloudStorageInfo(usedBytes: 1, limitBytes: 0).usagePercentage == 0.0)
        #expect(CloudStorageInfo().limitBytes == 5 * 1024 * 1024 * 1024)
    }

    @Test("Appwrite dates parse with and without fractional seconds")
    func appwriteDates() {
        #expect(AppwriteDecoder.date(from: "2026-01-15T10:30:00.000+00:00") != nil)
        #expect(AppwriteDecoder.date(from: "2026-01-15T10:30:00Z") != nil)
        #expect(AppwriteDecoder.date(from: "not a date") == nil)
    }

    @Test("The unavailable sync provider and database fail honestly")
    func unavailableProviders() async {
        let sync = UnavailableSyncProvider()
        await #expect(throws: CloudError.syncFailed("No cloud sync backend is configured: the sync payloads have no Appwrite database or collection to push to or pull from.")) {
            try await sync.pushDeltas([])
        }
        await #expect(throws: CloudError.syncFailed("No cloud sync backend is configured: the sync payloads have no Appwrite database or collection to push to or pull from.")) {
            try await sync.pullDeltas(since: Date(), tableName: "projects")
        }
        let database = UnavailableCloudDatabase()
        await #expect(throws: CloudError.databaseError("No cloud database is configured: there is no Appwrite database or collection behind the cloud tables.")) {
            try await database.query("projects", filter: nil)
        }
    }

    @Test("The storage provider refuses uploads honestly")
    func storageUploadUnavailable() async {
        let client = AppwriteAccountClient(session: stubSession())
        let storage = AppwriteStorageProvider(client: client)
        await #expect(throws: CloudError.self) {
            try await storage.upload(bucket: "backups", path: "x.zip", data: Data(), contentType: "application/zip")
        }
    }
}
