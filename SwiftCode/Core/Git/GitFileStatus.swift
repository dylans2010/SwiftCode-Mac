import Foundation

public struct GitFileStatus: Identifiable, Sendable, Codable {
    public var id: String { path }
    public let path: URL
    public let status: Status
    public let isStaged: Bool

    public enum Status: String, Sendable, Codable {
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case untracked = "??"
        case conflicted = "UU"
    }

    public init(path: URL, status: Status, isStaged: Bool) {
        self.path = path
        self.status = status
        self.isStaged = isStaged
    }
}
