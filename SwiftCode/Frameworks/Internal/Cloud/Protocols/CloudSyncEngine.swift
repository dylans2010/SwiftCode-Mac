import Foundation

public enum SyncState: String, Codable, Sendable {
    case idle
    case syncing
    case paused
    case error
}

public protocol CloudSyncEngine: AnyObject, Sendable {
    var syncState: SyncState { get }
    var lastSyncTime: Date? { get }
    var syncProgress: Double { get }

    func start() async
    func pause() async
    func resume() async
    func triggerSync() async throws
}
