// Adapted from SwiftCode-Legacy SwiftCode/Core/Git/GitStatusSnapshot.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct GitStatusSnapshot: Sendable, Codable {
    public let branchName: String
    public let ahead: Int
    public let behind: Int
    public let files: [GitFileStatus]

    public var stagedFiles: [GitFileStatus] {
        files.filter { $0.isStaged }
    }

    public var unstagedFiles: [GitFileStatus] {
        files.filter { !$0.isStaged }
    }

    public init(branchName: String, ahead: Int, behind: Int, files: [GitFileStatus]) {
        self.branchName = branchName
        self.ahead = ahead
        self.behind = behind
        self.files = files
    }
}
