import Foundation

public enum SyncState: String, Codable, Sendable, CaseIterable {
    case idle
    case syncing
    case paused
    case error
}
