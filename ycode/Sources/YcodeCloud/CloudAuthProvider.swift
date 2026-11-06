import Foundation

/// The read-only view of the signed-in cloud account, ported from
/// Legacy's `CloudAuthProvider.swift`. Legacy read the shared
/// `AuthManager` directly; this adapter reads a `CloudAuthManager`,
/// so tests can substitute one backed by a stub transport.
public protocol CloudAuthProviderProtocol: Sendable {
    func getActiveUser() async -> CloudUser?
    func isAuthenticated() async -> Bool
    func getSwiftCodeID() async -> String?
}

public final class CloudAuthProvider: CloudAuthProviderProtocol, @unchecked Sendable {
    /// The shared adapter reads the shared auth manager. MainActor
    /// because the manager is MainActor-isolated; pass a manager
    /// explicitly when calling from outside the main actor.
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

/// The `AuthenticationProvider` seam backed by the Appwrite account.
/// Appwrite email sessions are cookie-based and have no refresh
/// token: `CloudSession.accessToken` carries the session secret and
/// `refreshToken` is empty (see `CloudSession`); `expiresAt` is the
/// session's `expire` date.
///
/// Legacy had no guest accounts and no live session stream, so
/// `migrateGuestAccount` throws honestly and `sessionStateChanges`
/// yields the current session once and finishes — callers that need
/// live updates poll `getActiveSession` after auth actions.
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

/// The `StorageProvider` seam backed by Appwrite Storage. This is
/// what `BackupEngine` needs: `upload` / `listObjects` / `download` /
/// `delete` on the `backups` bucket, over the client's Storage REST
/// calls. The `path` is the Appwrite file id within the bucket; the
/// returned string from `upload` is the created file's id.
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

/// The first concrete `CloudProvider`: real auth (Appwrite account)
/// and real storage (Appwrite Storage), honestly-unavailable sync
/// and database (no Appwrite database or collection backs the sync
/// payloads — see `UnavailableSyncProvider` /
/// `UnavailableCloudDatabase`).
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

    /// Builds the provider from one `CloudAuthManager`: its client
    /// backs both the auth seam and the storage seam.
    public init(manager: CloudAuthManager) {
        self.authentication = AppwriteAuthenticationProvider(manager: manager)
        self.storage = AppwriteStorageProvider(client: manager.client)
        self.sync = UnavailableSyncProvider()
        self.database = UnavailableCloudDatabase()
    }
}
