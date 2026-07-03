import Foundation

public struct GitStatusSnapshot: Sendable, Codable {
    public let branchName: String
    public let ahead: Int
    public let behind: Int
    public let files: [GitFileStatus]

    public init(branchName: String, ahead: Int, behind: Int, files: [GitFileStatus]) {
        self.branchName = branchName
        self.ahead = ahead
        self.behind = behind
        self.files = files
    }
}
