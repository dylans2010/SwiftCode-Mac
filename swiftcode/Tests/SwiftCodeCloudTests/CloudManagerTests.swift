import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeCloud

@MainActor
struct CloudManagerTests {

    private func makeManager(
        handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data),
        store: MemorySecretStore = MemorySecretStore()
    ) -> (CloudAuthManager, CloudManager, MemorySecretStore) {
        StubURLProtocol.requests = []
        StubURLProtocol.handler = handler
        let client = AppwriteAccountClient(session: stubSession())
        let auth = CloudAuthManager(client: client, store: store)
        return (auth, CloudManager(authManager: auth), store)
    }

    @Test("sync without authentication records the unauthenticated error and stamps nothing")
    func syncWithoutAuth() async {
        UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey)
        let (_, cloud, _) = makeManager(handler: authHappyPath)
        await cloud.sync()
        #expect(cloud.currentError == CloudError.unauthenticated.localizedDescription)
        #expect(cloud.syncState == .idle)
        #expect(cloud.lastSyncTime == nil)
    }

    @Test("initialize without authentication leaves the manager uninitialized")
    func initializeWithoutAuth() async {
        let (_, cloud, _) = makeManager(handler: authHappyPath)
        await cloud.initialize()
        #expect(cloud.isInitialized == false)
    }

    @Test("login signs in, restores the session, and persists the session secret")
    func loginFlow() async throws {
        let (auth, _, store) = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        #expect(auth.isAuthenticated == true)
        #expect(auth.currentUser?.email == "dylan@example.com")
        #expect(auth.swiftCodeID == "sc_id=ABCDEF0123456789ABCDEF0123456789")
        #expect(auth.currentSession?.id == "sess_1")
        #expect(store.readString(SecretAccount.appwriteSessionSecret) == "stub-secret-123")
        #expect(store.readString(SecretAccount.appwriteUserID) == "user_1")
        let accountRequest = StubURLProtocol.requests.first(where: { $0.url?.path == "/v1/account" })
        #expect(accountRequest?.value(forHTTPHeaderField: "Cookie") == "a_session_6a670d0b0022e5f964b4=stub-secret-123")
    }

    @Test("login with wrong credentials throws and records the user-facing error")
    func loginWrongCredentials() async {
        let (auth, _, _) = makeManager { _ in
            appwriteError(401, code: 401, type: "user_unauthorized", message: "Invalid `email` param: Invalid credentials")
        }
        do {
            try await auth.login(email: "dylan@example.com", password: SecureString("wrong"))
            Issue.record("Expected login to throw")
        } catch {
            #expect(auth.isAuthenticated == false)
            #expect(auth.authError == "Invalid email address or password. Please verify and try again.")
        }
    }

    @Test("restoreSession mints and stores a swiftcode_id when the prefs lack one")
    func restoreMintsSwiftCodeID() async {
        let (auth, _, _) = makeManager { request in
            if request.url?.path == "/v1/account" { return ok(userWithoutSwiftCodeIDJSON) }
            return ok("{}")
        }
        auth.client.sessionSecret = "stub-secret-123"
        await auth.restoreSession()
        #expect(auth.isAuthenticated == true)
        let minted = auth.swiftCodeID ?? ""
        #expect(minted.hasPrefix("sc_id="))
        #expect(minted.count == 38)
        let prefsRequest = StubURLProtocol.requests.first(where: { $0.url?.path == "/v1/account/prefs" })
        #expect(prefsRequest?.httpMethod == "PATCH")
        let prefs = jsonBody(of: prefsRequest!)["prefs"] as? [String: String]
        #expect(prefs?["swiftcode_id"] == minted)
    }

    @Test("restoreSession with no stored secret fails cleanly and clears state")
    func restoreWithoutSecret() async {
        let (auth, _, store) = makeManager(handler: authHappyPath)
        await auth.restoreSession()
        #expect(auth.isAuthenticated == false)
        #expect(auth.currentUser == nil)
        #expect(auth.swiftCodeID == nil)
        #expect(store.readString(SecretAccount.appwriteSessionSecret) == nil)
    }

    @Test("logout ends the session server-side and clears local state and the stored secret")
    func logoutFlow() async throws {
        let (auth, _, store) = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        #expect(auth.isAuthenticated == true)
        await auth.logout()
        #expect(auth.isAuthenticated == false)
        #expect(auth.currentUser == nil)
        #expect(auth.swiftCodeID == nil)
        #expect(store.readString(SecretAccount.appwriteSessionSecret) == nil)
        #expect(StubURLProtocol.requests.contains(where: {
            $0.httpMethod == "DELETE" && $0.url?.path == "/v1/account/sessions/current"
        }))
    }

    @Test("createAccount creates the account and then signs in")
    func createAccountFlow() async throws {
        let (auth, _, _) = makeManager(handler: authHappyPath)
        try await auth.createAccount(email: "new@example.com", password: SecureString("s3cretpass"))
        #expect(auth.isAuthenticated == true)
        let create = StubURLProtocol.requests.first(where: { $0.url?.path == "/v1/account" && $0.httpMethod == "POST" })
        #expect(create != nil)
        #expect(jsonBody(of: create!)["userId"] as? String == "unique()")
    }

    @Test("startSync and stopSync flip the persisted flag and the sync state")
    func startStopSync() async throws {
        UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey) }
        let (auth, cloud, _) = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        await cloud.startSync()
        #expect(cloud.isSyncEnabled == true)
        #expect(UserDefaults.standard.bool(forKey: CloudManager.syncEnabledKey) == true)
        #expect(cloud.syncState == .idle)
        #expect(cloud.lastSyncTime != nil)
        cloud.stopSync()
        #expect(cloud.isSyncEnabled == false)
        #expect(cloud.syncState == .paused)
        #expect(UserDefaults.standard.bool(forKey: CloudManager.syncEnabledKey) == false)
    }

    @Test("handleLogout stops sync, clears the cache, and resets state")
    func handleLogout() async throws {
        UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey) }
        let (auth, cloud, _) = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        await cloud.startSync()
        let record = CloudRecord(swiftcodeID: "sc_id=1", recordType: "projects", recordKey: "a", payload: [:])
        await LocalCloudCache.shared.saveRecord(record)
        #expect(await LocalCloudCache.shared.getAllRecords().count == 1)
        await cloud.handleLogout()
        #expect(cloud.isInitialized == false)
        #expect(cloud.isSyncEnabled == false)
        #expect(cloud.syncState == .idle)
        #expect(cloud.lastSyncTime == nil)
        #expect(await LocalCloudCache.shared.getAllRecords().isEmpty)
    }

    @Test("CloudAuthProvider exposes the signed-in user after login")
    func authProviderAdapter() async throws {
        let (auth, _, _) = makeManager(handler: authHappyPath)
        let provider = CloudAuthProvider(manager: auth)
        #expect(await provider.getActiveUser() == nil)
        #expect(await provider.isAuthenticated() == false)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let user = await provider.getActiveUser()
        #expect(user?.swiftcodeID == "sc_id=ABCDEF0123456789ABCDEF0123456789")
        #expect(user?.email == "dylan@example.com")
        #expect(user?.name == "Dylan")
        #expect(await provider.isAuthenticated() == true)
        #expect(await provider.getSwiftCodeID() == "sc_id=ABCDEF0123456789ABCDEF0123456789")
    }

    @Test("The session secret round-trips through the secret store without touching the keychain")
    func secretStoreRoundTrip() throws {
        let store = MemorySecretStore()
        try store.write(Data("stub-secret-123".utf8), for: SecretAccount.appwriteSessionSecret)
        #expect(store.readString(SecretAccount.appwriteSessionSecret) == "stub-secret-123")
        try store.delete(SecretAccount.appwriteSessionSecret)
        #expect(store.readString(SecretAccount.appwriteSessionSecret) == nil)
    }

    @Test("The sync engine with no provider skips the cycle and leaves statistics untouched")
    func syncEngineNoProvider() async {
        UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey) }
        let (auth, _, _) = makeManager(handler: authHappyPath)
        let engine = CloudSyncEngine(testAuthManager: auth)
        await engine.setSyncEnabled(true)
        await engine.triggerSync()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let stats = await engine.getStatistics()
        #expect(stats.totalUploadCount == 0)
        #expect(stats.totalDownloadCount == 0)
        #expect(stats.lastSyncTimestamp == nil)
    }

    @Test("The sync engine with an unavailable provider counts the failed cycle")
    func syncEngineUnavailableProvider() async throws {
        UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey) }
        let (auth, _, _) = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let engine = CloudSyncEngine(testAuthManager: auth)
        await engine.setProvider(AppwriteCloudProvider(manager: auth))
        await engine.setSyncEnabled(true)
        await engine.triggerSync()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let stats = await engine.getStatistics()
        #expect(stats.conflictCount == 1)
    }
}
