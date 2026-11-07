import Foundation

public protocol CloudAuthProviderProtocol: Sendable {
    func getActiveUser() async -> CloudUser?
    func isAuthenticated() async -> Bool
    func getSwiftCodeID() async -> String?
}

public final class CloudAuthProvider: CloudAuthProviderProtocol, @unchecked Sendable {
    @MainActor public static let shared = CloudAuthProvider(manager: CloudAuthManager.shared)

    private let manager: CloudAuthManager

    public init(manager: CloudAuthManager) {
        self.manager = manager
    }

    public func getActiveUser() async -> CloudUser? {
        await MainActor.run {
            guard manager.isAuthenticated,
                  let user = manager.currentUser,
                  let swiftCodeID = manager.swiftCodeID else {
                return nil
            }
            return CloudUser(swiftcodeID: swiftCodeID, email: user.email, name: user.name, createdAt: user.createdAt)
        }
    }

    public func isAuthenticated() async -> Bool {
        await manager.isAuthenticated
    }

    public func getSwiftCodeID() async -> String? {
        await manager.swiftCodeID
    }
}

public final class AppwriteAuthenticationProvider: AuthenticationProvider, @unchecked Sendable {
    private let manager: CloudAuthManager

    public init(manager: CloudAuthManager) {
        self.manager = manager
    }

    private func session() async -> CloudSession? {
        await MainActor.run {
            guard manager.isAuthenticated, let user = manager.currentUser else { return nil }
            return CloudSession(
                userID: user.id,
                email: user.email,
                accessToken: manager.client.sessionSecret ?? "",
                refreshToken: "",
                expiresAt: manager.currentSession?.expire ?? Date().addingTimeInterval(3600))
        }
    }

    public func getActiveSession() async throws -> CloudSession? {
        await session()
    }

    public func login(email: String, password: SecureString) async throws -> CloudSession {
        try await manager.login(email: email, password: password)
        guard let session = await session() else {
            throw CloudError.unauthenticated
        }
        return session
    }

    public func createAccount(email: String, password: SecureString) async throws -> CloudSession {
        try await manager.createAccount(email: email, password: password)
        guard let session = await session() else {
            throw CloudError.unauthenticated
        }
        return session
    }

    public func logout() async throws {
        await manager.logout()
    }

    public func migrateGuestAccount(toEmail email: String, password: SecureString) async throws -> CloudSession {
        throw CloudError.syncFailed("Guest account migration is not supported: Legacy never had guest accounts.")
    }

    public func requestPasswordReset(forEmail email: String) async throws {
        try await manager.forgotPassword(email: email)
    }

    public func sessionStateChanges() -> AsyncStream<CloudSession?> {
        AsyncStream { continuation in
            Task {
                continuation.yield(await session())
                continuation.finish()
            }
        }
    }
}

public struct AppwriteStorageProvider: StorageProvider {
    private let client: AppwriteAccountClient

    public init(client: AppwriteAccountClient) {
        self.client = client
    }

    public func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        do {
            let file = try await client.createFile(
                bucketId: bucket, fileId: path, data: data,
                filename: path, contentType: contentType)
            return file.id
        } catch {
            throw CloudError.storageError(error.localizedDescription)
        }
    }

    public func download(bucket: String, path: String) async throws -> Data {
        do {
            return try await client.getFileDownload(bucketId: bucket, fileId: path)
        } catch {
            throw CloudError.storageError(error.localizedDescription)
        }
    }

    public func delete(bucket: String, path: String) async throws {
        do {
            try await client.deleteFile(bucketId: bucket, fileId: path)
        } catch {
            throw CloudError.storageError(error.localizedDescription)
        }
    }

    public func listObjects(bucket: String, prefix: String?) async throws -> [String] {
        do {
            let files = try await client.listFiles(bucketId: bucket)
            let ids = files.map { $0.id }
            guard let prefix, !prefix.isEmpty else { return ids }
            return ids.filter { $0.hasPrefix(prefix) }
        } catch {
            throw CloudError.storageError(error.localizedDescription)
        }
    }
}

public struct AppwriteCloudProvider: CloudProvider {
    public var authentication: AuthenticationProvider
    public var sync: SyncProvider
    public var storage: StorageProvider
    public var database: CloudDatabase

    public init(
        authentication: AuthenticationProvider,
        storage: StorageProvider,
        sync: SyncProvider = UnavailableSyncProvider(),
        database: CloudDatabase = UnavailableCloudDatabase()
    ) {
        self.authentication = authentication
        self.sync = sync
        self.storage = storage
        self.database = database
    }

    public init(manager: CloudAuthManager) {
        self.authentication = AppwriteAuthenticationProvider(manager: manager)
        self.storage = AppwriteStorageProvider(client: manager.client)
        self.sync = UnavailableSyncProvider()
        self.database = UnavailableCloudDatabase()
    }
}
