import Foundation

public struct GitCommit: Identifiable, Sendable, Codable {
    public let id: String // Hash
    public let author: String
    public let email: String
    public let date: Date
    public let message: String
    public let parentHashes: [String]

    public init(hash: String, author: String, email: String, date: Date, message: String, parentHashes: [String]) {
        self.id = hash
        self.author = author
        self.email = email
        self.date = date
        self.message = message
        self.parentHashes = parentHashes
    }
}
