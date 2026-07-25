import Foundation

public enum SyncConflictStrategy: String, Codable, Sendable {
    case keepLocal
    case keepCloud
    case merge
}

public protocol ConflictResolver: Sendable {
    func resolveConflict(table: String, localData: Data, cloudData: Data, strategy: SyncConflictStrategy) throws -> Data
}
