import Foundation

public struct DatabaseMigration: Identifiable, Codable, Hashable {
    public var id: UUID
    public var version: String // timestamp based, e.g. "20260725190906"
    public var name: String
    public var sqlUp: String
    public var sqlDown: String
    public var appliedAt: Date?

    public init(id: UUID = UUID(), version: String, name: String, sqlUp: String, sqlDown: String, appliedAt: Date? = nil) {
        self.id = id
        self.version = version
        self.name = name
        self.sqlUp = sqlUp
        self.sqlDown = sqlDown
        self.appliedAt = appliedAt
    }
}
