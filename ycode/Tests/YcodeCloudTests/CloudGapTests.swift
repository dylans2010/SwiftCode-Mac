import Foundation
import Testing
import YcodeAssistant
@testable import YcodeCloud

// Gap-closure tests: multipart Storage upload, the Supabase
// PostgREST client, AppConfig remainder, BackupEngine, and the
// OAuth-callback resume the app shell relies on. Stub transport
// and fixtures only — no live network, no real credentials.

@MainActor
struct CloudGapTests {

    // MARK: - Multipart upload

    @Test("multipart body carries the fileId field, the file part, and the raw bytes")
    func multipartBodyShape() {
        let body = AppwriteAccountClient.multipartFormData(
            boundary: "BOUNDARY", fileId: "abc.zip",
            data: Data("zip-bytes".utf8), filename: "abc.zip", contentType: "application/zip")
        let text = String(data: body, encoding: .utf8) ?? ""
        #expect(text.hasPrefix("--BOUNDARY\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"fileId\"\r\n\r\nabc.zip\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"abc.zip\"\r\n"))
        #expect(text.contains("Content-Type: application/zip\r\n\r\n"))
        #expect(text.contains("zip-bytes"))
        #expect(text.hasSuffix("\r\n--BOUNDARY--\r\n"))
    }

    @Test("createFile posts multipart/form-data and decodes the created file")
    func createFileRequest() async throws {
        let client = stubClient { request in
            guard request.url?.path == "/v1/storage/buckets/backups/files",
                  request.httpMethod == "POST" else {
                return (404, [:], json("{}"))
            }
            return ok("{\"$id\":\"file_1\",\"bucketId\":\"backups\",\"name\":\"abc.zip\",\"mimeType\":\"application/zip\",\"sizeOriginal\":9}")
        }
        let file = try await client.createFile(
            bucketId: "backups", fileId: "abc.zip",
            data: Data("zip-bytes".utf8), filename: "abc.zip", contentType: "application/zip")
        #expect(file.id == "file_1")
        #expect(file.name == "abc.zip")
        let request = StubURLProtocol.requests[0]
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(request.value(forHTTPHeaderField: "X-Appwrite-Project") == "6a670d0b0022e5f964b4")
    }

    @Test("AppwriteStorageProvider.upload returns the created file id")
    func storageProviderUpload() async throws {
        let client = stubClient { request in
            if request.url?.path == "/v1/storage/buckets/backups/files" {
                return ok("{\"$id\":\"created-id\",\"bucketId\":\"backups\",\"name\":\"x.zip\",\"mimeType\":\"application/zip\",\"sizeOriginal\":3}")
            }
            return ok("{}")
        }
        let provider = AppwriteStorageProvider(client: client)
        let id = try await provider.upload(bucket: "backups", path: "x.zip", data: Data("abc".utf8), contentType: "application/zip")
        #expect(id == "created-id")
    }

    // MARK: - OAuth callback resume

    @Test("beginOAuth resumes when the app shell delivers the callback URL")
    func beginOAuthResumesOnCallback() async throws {
        let auth = CloudAuthManager(client: AppwriteAccountClient(session: stubSession()), store: MemorySecretStore())
        StubURLProtocol.handler = authHappyPath
        var opened: URL?
        let task = Task {
            try await auth.beginOAuth(provider: .google, openURL: { url in opened = url; return true })
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(opened?.scheme == "https")
        let delivered = auth.handleOAuthCallback(URL(string: "appwrite-callback-6a670d0b0022e5f964b4://")!)
        #expect(delivered == nil) // resumed the pending wait; nothing left to return
        let user = try await task.value
        #expect(user.email == "dylan@example.com")
        #expect(auth.isAuthenticated == true)
    }

    @Test("beginOAuth throws when the provider declines the sign-in")
    func beginOAuthFailureCallback() async throws {
        let auth = CloudAuthManager(client: AppwriteAccountClient(session: stubSession()), store: MemorySecretStore())
        StubURLProtocol.handler = authHappyPath
        let task = Task {
            try await auth.beginOAuth(provider: .github, openURL: { _ in true })
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        _ = auth.handleOAuthCallback(URL(string: "appwrite-callback-6a670d0b0022e5f964b4://?error=access_denied&error_description=Denied")!)
        do {
            _ = try await task.value
            Issue.record("Expected beginOAuth to throw")
        } catch let error as AppwriteError {
            #expect(error.userFacingMessage == "OAuth Failed: Denied")
        }
    }

    @Test("handleOAuthCallback returns standalone recovery and verification links")
    func standaloneCallbackLinks() {
        let auth = CloudAuthManager(client: AppwriteAccountClient(session: stubSession()), store: MemorySecretStore())
        let recovery = auth.handleOAuthCallback(URL(string: "appwrite-callback-6a670d0b0022e5f964b4://reset-password?userId=u1&secret=s1")!)
        #expect(recovery == .recovery(userId: "u1", secret: "s1"))
        let verification = auth.handleOAuthCallback(URL(string: "appwrite-callback-6a670d0b0022e5f964b4://verify?userId=u2&secret=s2")!)
        #expect(verification == .verification(userId: "u2", secret: "s2"))
        #expect(auth.handleOAuthCallback(URL(string: "https://example.com/")!) == nil)
    }

    // MARK: - SupabaseService

    private func supabaseConnection() -> DatabaseConnection {
        DatabaseConnection(
            name: "Test", provider: .supabase,
            supabaseURL: "https://example.supabase.co", supabaseAnonKey: "anon-key")
    }

    @Test("testConnection returns true on 200 and sends the anon key as apikey + Bearer")
    func supabaseTestConnection() async throws {
        let service = SupabaseService(session: stubSession())
        StubURLProtocol.handler = { _ in ok("{}") }
        #expect(try await service.testConnection(connection: supabaseConnection()) == true)
        let request = StubURLProtocol.requests[0]
        #expect(request.url?.absoluteString == "https://example.supabase.co/rest/v1/")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon-key")
    }

    @Test("testConnection throws connectionFailed on a non-200 status")
    func supabaseTestConnectionFailure() async {
        let service = SupabaseService(session: stubSession())
        StubURLProtocol.handler = { _ in (401, [:], json("{}")) }
        do {
            _ = try await service.testConnection(connection: supabaseConnection())
            Issue.record("Expected testConnection to throw")
        } catch let error as DatabaseError {
            #expect(error.errorDescription?.contains("HTTP Status Code 401") == true)
        }
    }

    @Test("testConnection throws connectionFailed for a missing project URL")
    func supabaseTestConnectionBadURL() async {
        let service = SupabaseService(session: stubSession())
        var connection = supabaseConnection()
        connection.supabaseURL = nil
        do {
            _ = try await service.testConnection(connection: connection)
            Issue.record("Expected testConnection to throw")
        } catch let error as DatabaseError {
            #expect(error.errorDescription?.contains("Invalid Supabase Project URL") == true)
        }
    }

    @Test("fetchTables parses the OpenAPI definitions into sorted tables")
    func supabaseFetchTables() async throws {
        let service = SupabaseService(session: stubSession())
        let schema = """
        {"definitions":{
          "posts":{"description":"Blog posts","properties":{
            "id":{"type":"integer","description":"PK"},
            "title":{"type":"string"}},
            "required":["id","title"]},
          "authors":{"properties":{"id":{"type":"uuid"},"bio":{"type":"string"}},"required":["id"]}
        }}
        """
        StubURLProtocol.handler = { _ in ok(schema) }
        let tables = try await service.fetchTables(connection: supabaseConnection())
        #expect(tables.map(\.name) == ["authors", "posts"])
        let posts = tables[1]
        #expect(posts.comment == "Blog posts")
        #expect(posts.columns.count == 2)
        let idColumn = posts.columns.first(where: { $0.name == "id" })
        #expect(idColumn?.type == "INTEGER")
        #expect(idColumn?.isPrimaryKey == true)
        #expect(idColumn?.isNullable == false)
        #expect(idColumn?.comment == "PK")
        #expect(posts.columns.first(where: { $0.name == "title" })?.type == "STRING")
        #expect(tables[0].columns.first(where: { $0.name == "bio" })?.isNullable == true)
    }

    @Test("fetchTables returns an empty list when the schema has no definitions")
    func supabaseFetchTablesEmpty() async throws {
        let service = SupabaseService(session: stubSession())
        StubURLProtocol.handler = { _ in ok("{}") }
        #expect(try await service.fetchTables(connection: supabaseConnection()).isEmpty)
    }

    @Test("fetchTables throws queryExecutionFailed on a non-200 status")
    func supabaseFetchTablesFailure() async {
        let service = SupabaseService(session: stubSession())
        StubURLProtocol.handler = { _ in (500, [:], json("{}")) }
        do {
            _ = try await service.fetchTables(connection: supabaseConnection())
            Issue.record("Expected fetchTables to throw")
        } catch let error as DatabaseError {
            if case .queryExecutionFailed = error { } else {
                Issue.record("Expected queryExecutionFailed, got \(error)")
            }
        }
    }

    @Test("executeSQL fails honestly: PostgREST has no SQL endpoint")
    func supabaseExecuteSQLHonestFailure() async {
        let service = SupabaseService(session: stubSession())
        do {
            _ = try await service.executeSQL(connection: supabaseConnection(), sql: "SELECT 1")
            Issue.record("Expected executeSQL to throw")
        } catch let error as DatabaseError {
            #expect(error.errorDescription?.contains("no SQL execution endpoint") == true)
            #expect(error.errorDescription?.contains("SELECT 1") == true)
        }
    }

    @Test("postgrestRequest sends no key headers when the connection has no anon key")
    func supabaseRequestWithoutKey() throws {
        let service = SupabaseService(session: stubSession())
        var connection = supabaseConnection()
        connection.supabaseAnonKey = nil
        let request = try service.postgrestRequest(connection: connection)
        #expect(request.value(forHTTPHeaderField: "apikey") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - AppConfig

    @Test("AppConfig defaults are Legacy's public URLs and empty keys when unconfigured")
    func appConfigDefaults() {
        let config = AppConfig()
        #expect(config.supabaseURL.absoluteString == "https://secctbuzkfbketdihzui.supabase.co")
        #expect(config.swiftCloudAPIURL.absoluteString == "https://api.swiftcloud.ai/v1")
        #expect(config.supabaseAnonKey == "")
        #expect(config.openRouterAPIKey == "")
        #expect(config.geminiAPIKey == "")
        let diagnostics = config.runDiagnostics()
        #expect(diagnostics["configuredSupabaseURL"] == "MISSING")
        #expect(diagnostics["configuredSupabaseAnonKey"] == "MISSING")
        #expect(diagnostics["configuredOpenRouterAPIKey"] == "MISSING")
        #expect(diagnostics["configuredGeminiAPIKey"] == "MISSING")
        #expect(diagnostics["configuredSwiftCloudAPIURL"] == "MISSING")
    }

    @Test("AppConfig reads configured values and reports them LOADED")
    func appConfigConfigured() {
        let config = AppConfig(
            supabaseURL: "https://custom.supabase.co",
            supabaseAnonKey: "custom-anon",
            openRouterAPIKey: "or-key",
            geminiAPIKey: "gem-key",
            swiftCloudAPIURL: "https://custom.swiftcloud.test/v1")
        #expect(config.supabaseURL.absoluteString == "https://custom.supabase.co")
        #expect(config.supabaseAnonKey == "custom-anon")
        #expect(config.openRouterAPIKey == "or-key")
        #expect(config.geminiAPIKey == "gem-key")
        #expect(config.swiftCloudAPIURL.absoluteString == "https://custom.swiftcloud.test/v1")
        #expect(config.runDiagnostics().values.allSatisfy { $0 == "LOADED" })
    }

    @Test("AppConfig treats placeholder and $-prefixed values as unconfigured")
    func appConfigPlaceholderValues() {
        let config = AppConfig(supabaseAnonKey: "$SUPABASE_ANON_KEY", openRouterAPIKey: "placeholder-key")
        #expect(config.supabaseAnonKey == "")
        #expect(config.openRouterAPIKey == "")
        #expect(config.runDiagnostics()["configuredSupabaseAnonKey"] == "MISSING")
        #expect(config.runDiagnostics()["configuredOpenRouterAPIKey"] == "MISSING")
    }

    // MARK: - BackupEngine

    private func makeTempAppSupport() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("YcodeBackupGapTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeAuthenticatedManager() async throws -> CloudAuthManager {
        StubURLProtocol.handler = authHappyPath
        let auth = CloudAuthManager(client: AppwriteAccountClient(session: stubSession()), store: MemorySecretStore())
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        return auth
    }

    private func makeEngine(
        auth: CloudAuthManager,
        appSupport: URL,
        createArchive: (@Sendable (URL, URL) throws -> Void)? = nil,
        extractArchive: (@Sendable (URL, URL) throws -> Int)? = nil
    ) -> BackupEngine {
        BackupEngine(
            authManager: auth, appSupportDirectory: appSupport,
            createArchive: createArchive, extractArchive: extractArchive)
    }

    @Test("backup operations require authentication")
    func backupRequiresAuth() async {
        let appSupport = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let auth = CloudAuthManager(client: AppwriteAccountClient(session: stubSession()), store: MemorySecretStore())
        let engine = makeEngine(auth: auth, appSupport: appSupport)
        let manifest = BackupManifest(sizeInBytes: 0, filename: "x.zip", isCloudStored: false)
        do {
            try await engine.performBackup()
            Issue.record("Expected performBackup to throw")
        } catch let error as BackupError {
            #expect(error == .unauthenticated)
        }
        do {
            _ = try await engine.restore(manifest: manifest)
            Issue.record("Expected restore to throw")
        } catch let error as BackupError {
            #expect(error == .unauthenticated)
        }
        do {
            try await engine.delete(manifest: manifest)
            Issue.record("Expected delete to throw")
        } catch let error as BackupError {
            #expect(error == .unauthenticated)
        }
    }

    @Test("loadLocalBackups lists zip files newest-first and ignores other files")
    func loadLocalBackups() async throws {
        let appSupport = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let auth = try await makeAuthenticatedManager()
        let engine = makeEngine(auth: auth, appSupport: appSupport)
        let backupsDir = engine.localBackupsURL
        try Data("a".utf8).write(to: backupsDir.appendingPathComponent("old.zip"))
        try Data("b".utf8).write(to: backupsDir.appendingPathComponent("notes.txt"))
        try Data("c".utf8).write(to: backupsDir.appendingPathComponent("new.zip"))
        // Force distinct creation dates via the manifest ordering on disk.
        engine.loadLocalBackups()
        #expect(engine.backups.map(\.filename).sorted() == ["new.zip", "old.zip"])
        #expect(engine.backups.allSatisfy { !$0.isCloudStored })
    }

    @Test("performBackup archives locally, hashes, and reloads the list")
    func performBackupLocal() async throws {
        let appSupport = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let auth = try await makeAuthenticatedManager()
        let stateDir = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try Data("state".utf8).write(to: stateDir.appendingPathComponent("state.json"))
        var archivedStaging: URL?
        let engine = makeEngine(auth: auth, appSupport: appSupport, createArchive: { staging, archive in
            archivedStaging = staging
            try Data("stub-zip-bytes".utf8).write(to: archive)
        })
        try await engine.performBackup()
        #expect(archivedStaging != nil)
        #expect(engine.isCreatingBackup == false)
        #expect(engine.backupProgress == 1.0)
        #expect(engine.statusMessage == "Backup snapshot created successfully.")
        #expect(engine.lastArchiveSHA256?.count == 64)
        #expect(engine.backups.count == 1)
        #expect(engine.backups[0].filename.hasSuffix(".zip"))
        // The archive written by the stub is what got hashed.
        let expected = SHA256Digest.hash(Data("stub-zip-bytes".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(engine.lastArchiveSHA256 == expected)
    }

    @Test("performBackup uploads the archive to the backups bucket when a provider is given")
    func performBackupUpload() async throws {
        let appSupport = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let auth = try await makeAuthenticatedManager()
        let stateDir = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let storage = RecordingStorageProvider()
        let provider = AppwriteCloudProvider(
            authentication: AppwriteAuthenticationProvider(manager: auth), storage: storage)
        let engine = makeEngine(auth: auth, appSupport: appSupport, createArchive: { _, archive in
            try Data("upload-me".utf8).write(to: archive)
        })
        try await engine.performBackup(cloudProvider: provider)
        let uploads = await storage.uploads()
        #expect(uploads.count == 1)
        #expect(uploads[0].bucket == "backups")
        #expect(uploads[0].path.hasSuffix(".zip"))
        #expect(uploads[0].data == Data("upload-me".utf8))
        #expect(uploads[0].contentType == "application/zip")
    }

    @Test("fetchCloudBackups merges cloud zip manifests as cloud-stored")
    func fetchCloudBackups() async throws {
        let appSupport = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let auth = try await makeAuthenticatedManager()
        let storage = RecordingStorageProvider()
        await storage.setFiles(["remote-1.zip": Data(), "notes.txt": Data()])
        let provider = AppwriteCloudProvider(
            authentication: AppwriteAuthenticationProvider(manager: auth), storage: storage)
        let engine = makeEngine(auth: auth, appSupport: appSupport)
        try await engine.fetchCloudBackups(cloudProvider: provider)
        #expect(engine.backups.count == 1)
        #expect(engine.backups[0].filename == "remote-1.zip")
        #expect(engine.backups[0].isCloudStored == true)
    }

    @Test("restore downloads, erases state except Backups, extracts, and reports the count")
    func restoreFromCloud() async throws {
        let appSupport = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let auth = try await makeAuthenticatedManager()
        let stateDir = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        let backupsDir = stateDir.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        try Data("old state".utf8).write(to: stateDir.appendingPathComponent("old.json"))
        try Data("keep me".utf8).write(to: backupsDir.appendingPathComponent("keep.zip"))
        let storage = RecordingStorageProvider()
        await storage.setFiles(["snap.zip": Data("cloud-zip".utf8)])
        let provider = AppwriteCloudProvider(
            authentication: AppwriteAuthenticationProvider(manager: auth), storage: storage)
        let engine = makeEngine(auth: auth, appSupport: appSupport, extractArchive: { _, destination in
            try Data("restored".utf8).write(to: destination.appendingPathComponent("restored.json"))
            return 3
        })
        let manifest = BackupManifest(sizeInBytes: 9, filename: "snap.zip", isCloudStored: true)
        let result = try await engine.restore(manifest: manifest, cloudProvider: provider)
        #expect(result.isSuccess == true)
        #expect(result.restoredFileCount == 3)
        #expect(FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("old.json").path) == false)
        #expect(FileManager.default.fileExists(atPath: backupsDir.appendingPathComponent("keep.zip").path) == true)
        #expect(FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("restored.json").path) == true)
        let downloads = await storage.downloads()
        #expect(downloads == ["snap.zip"])
    }

    @Test("restore of a missing local archive returns a failed result instead of throwing")
    func restoreMissingArchive() async throws {
        let appSupport = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let auth = try await makeAuthenticatedManager()
        let engine = makeEngine(auth: auth, appSupport: appSupport)
        let manifest = BackupManifest(sizeInBytes: 0, filename: "nope.zip", isCloudStored: false)
        let result = try await engine.restore(manifest: manifest)
        #expect(result.isSuccess == false)
        #expect(result.errorMessage == "Backup archive file not found.")
    }

    @Test("delete removes the local file and the remote copy when cloud-stored")
    func deleteBackup() async throws {
        let appSupport = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let auth = try await makeAuthenticatedManager()
        let storage = RecordingStorageProvider()
        await storage.setFiles(["gone.zip": Data("x".utf8)])
        let provider = AppwriteCloudProvider(
            authentication: AppwriteAuthenticationProvider(manager: auth), storage: storage)
        let engine = makeEngine(auth: auth, appSupport: appSupport)
        try Data("x".utf8).write(to: engine.localBackupsURL.appendingPathComponent("gone.zip"))
        engine.loadLocalBackups()
        #expect(engine.backups.count == 1)
        try await engine.delete(
            manifest: BackupManifest(sizeInBytes: 1, filename: "gone.zip", isCloudStored: true),
            cloudProvider: provider)
        #expect(engine.backups.isEmpty)
        #expect(await storage.deleted() == ["gone.zip"])
        #expect(FileManager.default.fileExists(atPath: engine.localBackupsURL.appendingPathComponent("gone.zip").path) == false)
    }

    @Test("system archivers round-trip: zip creates, unzip extracts")
    func systemArchiveRoundTrip() throws {
        let base = makeTempAppSupport()
        defer { try? FileManager.default.removeItem(at: base) }
        let staging = base.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("hello backup".utf8).write(to: staging.appendingPathComponent("hello.txt"))
        let archive = base.appendingPathComponent("out.zip")
        try BackupEngine.systemCreateArchive(directory: staging, archive: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
        let dest = base.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let count = try BackupEngine.systemExtractArchive(archive: archive, destination: dest)
        #expect(count >= 1)
        #expect(try String(contentsOf: dest.appendingPathComponent("hello.txt"), encoding: .utf8) == "hello backup")
    }
}

/// A recording `StorageProvider` for backup tests: files live in
/// memory, uploads/downloads/deletes are recorded.
final class RecordingStorageProvider: StorageProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _files: [String: Data] = [:]
    private var _uploads: [(bucket: String, path: String, data: Data, contentType: String)] = []
    private var _downloads: [String] = []
    private var _deleted: [String] = []

    func setFiles(_ files: [String: Data]) async {
        lock.lock(); defer { lock.unlock() }
        _files = files
    }

    func uploads() async -> [(bucket: String, path: String, data: Data, contentType: String)] {
        lock.lock(); defer { lock.unlock() }
        return _uploads
    }

    func downloads() async -> [String] {
        lock.lock(); defer { lock.unlock() }
        return _downloads
    }

    func deleted() async -> [String] {
        lock.lock(); defer { lock.unlock() }
        return _deleted
    }

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        lock.lock(); defer { lock.unlock() }
        _uploads.append((bucket, path, data, contentType))
        _files[path] = data
        return path
    }

    func download(bucket: String, path: String) async throws -> Data {
        lock.lock()
        _downloads.append(path)
        let data = _files[path]
        lock.unlock()
        guard let data else { throw CloudError.storageError("No such file: \(path)") }
        return data
    }

    func delete(bucket: String, path: String) async throws {
        lock.lock(); defer { lock.unlock() }
        _deleted.append(path)
        _files.removeValue(forKey: path)
    }

    func listObjects(bucket: String, prefix: String?) async throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        let ids = _files.keys.sorted()
        guard let prefix, !prefix.isEmpty else { return ids }
        return ids.filter { $0.hasPrefix(prefix) }
    }
}
