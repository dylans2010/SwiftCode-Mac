// Adapted from SwiftCode-Legacy SwiftCode/Core/Git/GitDiffHunk.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct GitDiffHunk: Identifiable, Sendable, Codable {
    public let id: UUID
    public let header: String
    public let lines: [String]

    public init(header: String, lines: [String]) {
        self.id = UUID()
        self.header = header
        self.lines = lines
    }
}
