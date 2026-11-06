import Foundation

/// The primary abstract seam governing all cloud-backed
/// capabilities. Ported verbatim from Legacy's
/// `CloudProvider.swift`. Legacy defined this protocol (and the four
/// sub-protocols below) but **no type in Legacy ever conformed to
/// it** — `CloudSyncEngine` holds an optional provider that nothing
/// sets, and `BackupEngine` takes one as a parameter that no caller
/// supplies. `AppwriteCloudProvider` (in `CloudAuthProvider.swift`)
/// is the first concrete implementation: real auth and storage,
/// honestly-unavailable sync and database.
public protocol CloudProvider: Sendable {
    var authentication: AuthenticationProvider { get }
    var sync: SyncProvider { get }
    var storage: StorageProvider { get }
    var database: CloudDatabase { get }
}

/// Abstract seam governing auth workflows, credentials, and guest
/// migrations. Ported verbatim from Legacy's `CloudProvider.swift`.
public protocol AuthenticationProvider: Sendable {
    func getActiveSession() async throws -> CloudSession?
    func login(email: String, password: SecureString) async throws -> CloudSession
    func createAccount(email: String, password: SecureString) async throws -> CloudSession
    func logout() async throws
    func migrateGuestAccount(toEmail email: String, password: SecureString) async throws -> CloudSession
    func requestPasswordReset(forEmail email: String) async throws
    func sessionStateChanges() -> AsyncStream<CloudSession?>
}

/// Abstract seam managing the raw database interactions for schemas.
/// Ported verbatim from Legacy's `CloudProvider.swift`.
public protocol CloudDatabase: Sendable {
    func query(_ table: String, filter: String?) async throws -> [[String: String]]
    func insert(_ table: String, values: [String: String]) async throws
    func update(_ table: String, values: [String: String], filter: String) async throws
    func delete(_ table: String, filter: String) async throws
}

/// Abstract seam governing realtime subscriptions and continuous
/// delta synchronizations. Ported verbatim from Legacy's
/// `CloudProvider.swift`.
public protocol SyncProvider: Sendable {
    func pullDeltas(since: Date, tableName: String) async throws -> [SyncPayload]
    func pushDeltas(_ deltas: [SyncPayload]) async throws
    func subscribeToChanges(tableName: String, onInsert: @escaping @Sendable (SyncPayload) -> Void, onUpdate: @escaping @Sendable (SyncPayload) -> Void) async throws
    func unsubscribeFromChanges(tableName: String) async throws
}

/// Abstract seam governing file object uploads, downloads, and
/// remote asset listings. Ported verbatim from Legacy's
/// `CloudProvider.swift`.
public protocol StorageProvider: Sendable {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String
    func download(bucket: String, path: String) async throws -> Data
    func delete(bucket: String, path: String) async throws
    func listObjects(bucket: String, prefix: String?) async throws -> [String]
}

/// Secure strings to hide sensitive tokens from memory-leak
/// inspection audits. Ported verbatim from Legacy's
/// `CloudProvider.swift`. (It wraps rather than erases: the value
/// is still in memory while held, as in Legacy.)
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

/// A `SyncProvider` that always fails honestly. Legacy's
/// `CloudSyncEngine` calls `pushDeltas` / `pullDeltas` on whatever
/// provider is configured, but no Legacy provider ever implemented
/// them — there is no Appwrite database or collection behind the
/// sync payloads. Until a later wave defines that backend, any
/// attempt to push or pull fails with a named reason instead of
/// pretending to sync.
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

/// A `CloudDatabase` that always fails honestly, for the same reason
/// as `UnavailableSyncProvider`: Legacy defined the seam but never
/// backed it with a database.
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
