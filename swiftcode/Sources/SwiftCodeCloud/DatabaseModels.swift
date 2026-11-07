import Foundation

public enum DatabaseProvider: String, Codable, CaseIterable, Sendable {
    case sqlite = "SQLite"
    case postgresql = "PostgreSQL"
    case mysql = "MySQL"
    case mariadb = "MariaDB"
    case supabase = "Supabase PostgreSQL"
}

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

public struct DatabaseConnection: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var provider: DatabaseProvider

    public var sqliteFilePath: String?

    public var host: String?
    public var port: Int?
    public var databaseName: String?
    public var username: String?

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

public struct DatabaseColumn: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String
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
    public var junctionTable: String?
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

public struct DatabaseIndex: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var columns: [String]
    public var isUnique: Bool
    public var type: String
    public var expression: String?

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

public struct DatabaseTrigger: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var event: String
    public var tableName: String
    public var actionStatement: String

    public init(name: String, event: String, tableName: String, actionStatement: String) {
        self.name = name
        self.event = event
        self.tableName = tableName
        self.actionStatement = actionStatement
    }
}

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
