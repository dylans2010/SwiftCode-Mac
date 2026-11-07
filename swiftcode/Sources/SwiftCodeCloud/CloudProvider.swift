import Foundation

public protocol CloudProvider: Sendable {
    var authentication: AuthenticationProvider { get }
    var sync: SyncProvider { get }
    var storage: StorageProvider { get }
    var database: CloudDatabase { get }
}

public protocol AuthenticationProvider: Sendable {
    func getActiveSession() async throws -> CloudSession?
    func login(email: String, password: SecureString) async throws -> CloudSession
    func createAccount(email: String, password: SecureString) async throws -> CloudSession
    func logout() async throws
    func migrateGuestAccount(toEmail email: String, password: SecureString) async throws -> CloudSession
    func requestPasswordReset(forEmail email: String) async throws
    func sessionStateChanges() -> AsyncStream<CloudSession?>
}

public protocol CloudDatabase: Sendable {
    func query(_ table: String, filter: String?) async throws -> [[String: String]]
    func insert(_ table: String, values: [String: String]) async throws
    func update(_ table: String, values: [String: String], filter: String) async throws
    func delete(_ table: String, filter: String) async throws
}

public protocol SyncProvider: Sendable {
    func pullDeltas(since: Date, tableName: String) async throws -> [SyncPayload]
    func pushDeltas(_ deltas: [SyncPayload]) async throws
    func subscribeToChanges(tableName: String, onInsert: @escaping @Sendable (SyncPayload) -> Void, onUpdate: @escaping @Sendable (SyncPayload) -> Void) async throws
    func unsubscribeFromChanges(tableName: String) async throws
}

public protocol StorageProvider: Sendable {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String
    func download(bucket: String, path: String) async throws -> Data
    func delete(bucket: String, path: String) async throws
    func listObjects(bucket: String, prefix: String?) async throws -> [String]
}

public struct SecureString: Codable, Sendable, Equatable, ExpressibleByStringLiteral {
    private let rawValue: String

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(_ value: String) {
        self.rawValue = value
    }

    public func value() -> String {
        return rawValue
    }
}

public struct UnavailableSyncProvider: SyncProvider {
    public init() {}

    private func unavailable() -> CloudError {
        .syncFailed("No cloud sync backend is configured: the sync payloads have no Appwrite database or collection to push to or pull from.")
    }

    public func pullDeltas(since: Date, tableName: String) async throws -> [SyncPayload] {
        throw unavailable()
    }

    public func pushDeltas(_ deltas: [SyncPayload]) async throws {
        throw unavailable()
    }

    public func subscribeToChanges(tableName: String, onInsert: @escaping @Sendable (SyncPayload) -> Void, onUpdate: @escaping @Sendable (SyncPayload) -> Void) async throws {
        throw unavailable()
    }

    public func unsubscribeFromChanges(tableName: String) async throws {
        throw unavailable()
    }
}

public struct UnavailableCloudDatabase: CloudDatabase {
    public init() {}

    private func unavailable() -> CloudError {
        .databaseError("No cloud database is configured: there is no Appwrite database or collection behind the cloud tables.")
    }

    public func query(_ table: String, filter: String?) async throws -> [[String: String]] {
        throw unavailable()
    }

    public func insert(_ table: String, values: [String: String]) async throws {
        throw unavailable()
    }

    public func update(_ table: String, values: [String: String], filter: String) async throws {
        throw unavailable()
    }

    public func delete(_ table: String, filter: String) async throws {
        throw unavailable()
    }
}
