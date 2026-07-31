import Foundation

public struct DatabaseConnection: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var provider: DatabaseProvider

    // SQLite connection configuration
    public var sqliteFilePath: String?

    // Network-based connection configuration (Postgres, MySQL, MariaDB, Supabase)
    public var host: String?
    public var port: Int?
    public var databaseName: String?
    public var username: String?

    // Supabase specific options
    public var supabaseURL: String?
    public var supabaseAnonKey: String?
    public var supabaseServiceKey: String?
    public var supabaseJWTSecret: String?

    public init(id: UUID = UUID(), name: String, provider: DatabaseProvider, sqliteFilePath: String? = nil, host: String? = nil, port: Int? = nil, databaseName: String? = nil, username: String? = nil, supabaseURL: String? = nil, supabaseAnonKey: String? = nil, supabaseServiceKey: String? = nil, supabaseJWTSecret: String? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.sqliteFilePath = sqliteFilePath
        self.host = host
        self.port = port
        self.databaseName = databaseName
        self.username = username
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.supabaseServiceKey = supabaseServiceKey
        self.supabaseJWTSecret = supabaseJWTSecret
    }
}
