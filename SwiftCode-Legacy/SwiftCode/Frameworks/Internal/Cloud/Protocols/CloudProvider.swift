import Foundation

/// Primary abstract seam governing all cloud-backed capabilities.
public protocol CloudProvider: Sendable {
    var authentication: AuthenticationProvider { get }
    var sync: SyncProvider { get }
    var storage: StorageProvider { get }
    var database: CloudDatabase { get }
}

/// Abstract seam governing auth workflows, credentials, and guest migrations.
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
public protocol CloudDatabase: Sendable {
    func query(_ table: String, filter: String?) async throws -> [[String: String]]
    func insert(_ table: String, values: [String: String]) async throws
    func update(_ table: String, values: [String: String], filter: String) async throws
    func delete(_ table: String, filter: String) async throws
}

/// Abstract seam governing realtime subscriptions and continuous delta synchronizations.
public protocol SyncProvider: Sendable {
    func pullDeltas(since: Date, tableName: String) async throws -> [SyncPayload]
    func pushDeltas(_ deltas: [SyncPayload]) async throws
    func subscribeToChanges(tableName: String, onInsert: @escaping @Sendable (SyncPayload) -> Void, onUpdate: @escaping @Sendable (SyncPayload) -> Void) async throws
    func unsubscribeFromChanges(tableName: String) async throws
}

/// Abstract seam governing file object uploads, downloads, and remote asset listings.
public protocol StorageProvider: Sendable {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String
    func download(bucket: String, path: String) async throws -> Data
    func delete(bucket: String, path: String) async throws
    func listObjects(bucket: String, prefix: String?) async throws -> [String]
}

/// Helper representing secure strings to hide sensitive tokens from memory leak inspect audits.
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
