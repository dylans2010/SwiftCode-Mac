import Foundation

public enum DatabaseProvider: String, Codable, CaseIterable {
    case sqlite = "SQLite"
    case postgresql = "PostgreSQL"
    case mysql = "MySQL"
    case mariadb = "MariaDB"
    case supabase = "Supabase PostgreSQL"
}

public struct DatabaseInfo: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var provider: DatabaseProvider
    public var connectionID: UUID
    public var version: String?
    public var sizeInMB: Double?
    public var tableCount: Int

    public init(id: UUID = UUID(), name: String, provider: DatabaseProvider, connectionID: UUID, version: String? = nil, sizeInMB: Double? = nil, tableCount: Int = 0) {
        self.id = id
        self.name = name
        self.provider = provider
        self.connectionID = connectionID
        self.version = version
        self.sizeInMB = sizeInMB
        self.tableCount = tableCount
    }
}
