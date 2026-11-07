import Foundation

public struct GitDiffHunk: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: UUID
    public let header: String
    public let lines: [String]

    public init(id: UUID = UUID(), header: String, lines: [String]) {
        self.id = id
        self.header = header
        self.lines = lines
    }
}
