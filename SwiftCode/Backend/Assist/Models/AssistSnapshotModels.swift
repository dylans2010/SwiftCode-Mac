import Foundation

public struct AssistSnapshotMetadata: Codable {
    public let id: String
    public let timestamp: Date
    public let message: String
    public let rootPath: String
}

public struct AssistFileDiff: Codable {
    public let path: String
    public let status: DiffStatus
    public let changes: String // Simplified diff string

    public enum DiffStatus: String, Codable {
        case added
        case modified
        case deleted
    }
}
