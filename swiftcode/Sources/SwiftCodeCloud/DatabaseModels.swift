import Foundation

/// The database engines the Database utility knows about, ported
/// verbatim from Legacy's `Views/Utilities/Database/Models/Database.swift`.
/// Only the Supabase case is exercised by `SupabaseService`; the rest
/// are carried over so a stored `DatabaseConnection` keeps its shape.
public enum DatabaseProvider: String, Codable, CaseIterable, Sendable {
    case sqlite = "SQLite"
    case postgresql = "PostgreSQL"
    case mysql = "MySQL"
    case mariadb = "MariaDB"
    case supabase = "Supabase PostgreSQL"
}

/// Metadata about a database on a connection, ported verbatim
/// from Legacy's `Views/Utilities/Database/Models/Database.swift`.
/// Recorded for the Database utility; `SupabaseService` does not
/// populate it (PostgREST's OpenAPI schema carries no version /
/// size / table count).
public struct DatabaseInfo: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var provider: DatabaseProvider
    public var connectionID: UUID
    public var version: String?
    public var sizeInMB: Double?
    public var tableCount: Int

    public init(
        id: UUID = UUID(), name: String, provider: DatabaseProvider,
        connectionID: UUID, version: String? = nil,
        sizeInMB: Double? = nil, tableCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.connectionID = connectionID
        self.version = version
        self.sizeInMB = sizeInMB
        self.tableCount = tableCount
    }
}

/// A saved database connection, ported verbatim from Legacy's
/// `Views/Utilities/Database/Models/DatabaseConnection.swift`.
/// For Supabase connections the project URL and anon key are the
/// fields `SupabaseService` reads; the service key and JWT secret
/// are stored here when the user supplies them, and are never
/// logged. No credential is ever given a default value here.
public struct DatabaseConnection: Identifiable, Codable, Hashable, Sendable {
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

    public init(
        id: UUID = UUID(), name: String, provider: DatabaseProvider,
        sqliteFilePath: String? = nil, host: String? = nil, port: Int? = nil,
        databaseName: String? = nil, username: String? = nil,
        supabaseURL: String? = nil, supabaseAnonKey: String? = nil,
        supabaseServiceKey: String? = nil, supabaseJWTSecret: String? = nil
    ) {
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

/// One column of a table, ported verbatim from Legacy's
/// `Views/Utilities/Database/Models/DatabaseColumn.swift`.
public struct DatabaseColumn: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String // e.g. TEXT, INTEGER, VARCHAR(255), uuid, etc.
    public var isPrimaryKey: Bool
    public var isForeignKey: Bool
    public var isNullable: Bool
    public var isUnique: Bool
    public var isAutoIncrement: Bool
    public var isGenerated: Bool
    public var generationExpression: String?
    public var defaultValue: String?
    public var checkConstraint: String?
    public var comment: String?

    public init(
        name: String, type: String, isPrimaryKey: Bool = false,
        isForeignKey: Bool = false, isNullable: Bool = true,
        isUnique: Bool = false, isAutoIncrement: Bool = false,
        isGenerated: Bool = false, generationExpression: String? = nil,
        defaultValue: String? = nil, checkConstraint: String? = nil,
        comment: String? = nil
    ) {
        self.name = name
        self.type = type
        self.isPrimaryKey = isPrimaryKey
        self.isForeignKey = isForeignKey
        self.isNullable = isNullable
        self.isUnique = isUnique
        self.isAutoIncrement = isAutoIncrement
        self.isGenerated = isGenerated
        self.generationExpression = generationExpression
        self.defaultValue = defaultValue
        self.checkConstraint = checkConstraint
        self.comment = comment
    }
}

/// A relationship between two tables, ported verbatim from Legacy's
/// `Views/Utilities/Database/Models/DatabaseRelationship.swift`.
/// `SupabaseService.fetchTables` does not populate relationships
/// (PostgREST's OpenAPI schema does not describe them); the type is
/// carried over so `DatabaseTable` keeps its shape.
public enum RelationshipType: String, Codable, CaseIterable, Sendable {
    case oneToOne = "One-to-One"
    case oneToMany = "One-to-Many"
    case manyToMany = "Many-to-Many"
}

public enum ReferentialAction: String, Codable, CaseIterable, Sendable {
    case cascade = "CASCADE"
    case restrict = "RESTRICT"
    case setNull = "SET NULL"
    case setDefault = "SET DEFAULT"
    case noAction = "NO ACTION"
}

public struct DatabaseRelationship: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var type: RelationshipType
    public var sourceTable: String
    public var sourceColumn: String
    public var targetTable: String
    public var targetColumn: String
    public var junctionTable: String? // for Many-to-Many relationships
    public var onDelete: ReferentialAction
    public var onUpdate: ReferentialAction

    public init(
        id: UUID = UUID(), type: RelationshipType, sourceTable: String,
        sourceColumn: String, targetTable: String, targetColumn: String,
        junctionTable: String? = nil, onDelete: ReferentialAction = .cascade,
        onUpdate: ReferentialAction = .cascade
    ) {
        self.id = id
        self.type = type
        self.sourceTable = sourceTable
        self.sourceColumn = sourceColumn
        self.targetTable = targetTable
        self.targetColumn = targetColumn
        self.junctionTable = junctionTable
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
}

/// An index on a table, ported verbatim from Legacy's
/// `Views/Utilities/Database/Models/DatabaseIndex.swift`.
public struct DatabaseIndex: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var columns: [String]
    public var isUnique: Bool
    public var type: String // e.g. B-TREE, HASH, GIN, GiST, etc.
    public var expression: String? // for functional or partial indexes

    public init(
        name: String, columns: [String], isUnique: Bool = false,
        type: String = "B-TREE", expression: String? = nil
    ) {
        self.name = name
        self.columns = columns
        self.isUnique = isUnique
        self.type = type
        self.expression = expression
    }
}

/// A trigger on a table, ported verbatim from Legacy's
/// `Views/Utilities/Database/Models/DatabaseTrigger.swift`.
public struct DatabaseTrigger: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var event: String // BEFORE INSERT, AFTER UPDATE, etc.
    public var tableName: String
    public var actionStatement: String

    public init(name: String, event: String, tableName: String, actionStatement: String) {
        self.name = name
        self.event = event
        self.tableName = tableName
        self.actionStatement = actionStatement
    }
}

/// One table, ported verbatim from Legacy's
/// `Views/Utilities/Database/Models/DatabaseTable.swift`.
public struct DatabaseTable: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var columns: [DatabaseColumn]
    public var relationships: [DatabaseRelationship]
    public var indexes: [DatabaseIndex]
    public var triggers: [DatabaseTrigger]
    public var isView: Bool
    public var isMaterializedView: Bool
    public var comment: String?
    public var recordCount: Int

    public init(
        name: String, columns: [DatabaseColumn] = [],
        relationships: [DatabaseRelationship] = [],
        indexes: [DatabaseIndex] = [], triggers: [DatabaseTrigger] = [],
        isView: Bool = false, isMaterializedView: Bool = false,
        comment: String? = nil, recordCount: Int = 0
    ) {
        self.name = name
        self.columns = columns
        self.relationships = relationships
        self.indexes = indexes
        self.triggers = triggers
        self.isView = isView
        self.isMaterializedView = isMaterializedView
        self.comment = comment
        self.recordCount = recordCount
    }
}

/// Database errors, ported verbatim from Legacy's
/// `Views/Utilities/Database/Helpers/DatabaseErrorHandler.swift`.
public enum DatabaseError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case queryExecutionFailed(String, sql: String)
    case schemaModificationFailed(String)
    case tableNotFound(String)
    case validationFailed(String)
    case importFailed(String)
    case exportFailed(String)
    case syncFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection Failed: \(message)"
        case .queryExecutionFailed(let message, let sql):
            return "SQL Execution Error: \(message) [SQL: \(sql)]"
        case .schemaModificationFailed(let message):
            return "Schema Modification Failed: \(message)"
        case .tableNotFound(let name):
            return "Table not found: \(name)"
        case .validationFailed(let message):
            return "Validation Error: \(message)"
        case .importFailed(let message):
            return "Import Failed: \(message)"
        case .exportFailed(let message):
            return "Export Failed: \(message)"
        case .syncFailed(let message):
            return "Sync Failed: \(message)"
        }
    }
}
