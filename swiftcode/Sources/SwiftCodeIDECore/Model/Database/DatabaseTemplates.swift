import Foundation
import SwiftCodeHealthStore

public struct DatabaseTemplateColumn: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var type: String
    public var isPrimaryKey: Bool
    public var isNullable: Bool
    public var isUnique: Bool
    public var isAutoIncrement: Bool
    public var isForeignKey: Bool
    public var defaultValue: String?

    public init(name: String, type: String, isPrimaryKey: Bool = false, isNullable: Bool = true,
                isUnique: Bool = false, isAutoIncrement: Bool = false, isForeignKey: Bool = false,
                defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.isPrimaryKey = isPrimaryKey
        self.isNullable = isNullable
        self.isUnique = isUnique
        self.isAutoIncrement = isAutoIncrement
        self.isForeignKey = isForeignKey
        self.defaultValue = defaultValue
    }
}

public enum DatabaseRelationshipType: String, Codable, Sendable {
    case oneToOne, oneToMany, manyToMany
}

public struct DatabaseTemplateRelationship: Codable, Sendable, Equatable, Hashable {
    public var type: DatabaseRelationshipType
    public var sourceTable: String
    public var sourceColumn: String
    public var targetTable: String
    public var targetColumn: String

    public init(type: DatabaseRelationshipType, sourceTable: String, sourceColumn: String,
                targetTable: String, targetColumn: String) {
        self.type = type
        self.sourceTable = sourceTable
        self.sourceColumn = sourceColumn
        self.targetTable = targetTable
        self.targetColumn = targetColumn
    }
}

public struct DatabaseTemplateTable: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var columns: [DatabaseTemplateColumn]
    public var relationships: [DatabaseTemplateRelationship]

    public init(name: String, columns: [DatabaseTemplateColumn], relationships: [DatabaseTemplateRelationship] = []) {
        self.name = name
        self.columns = columns
        self.relationships = relationships
    }
}

public struct DatabaseTemplate: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var category: String
    public var description: String
    public var tags: [String]
    public var tables: [DatabaseTemplateTable]
    public var isFavorite: Bool

    public init(id: UUID = UUID(), name: String, category: String, description: String,
                tags: [String] = [], tables: [DatabaseTemplateTable], isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.tags = tags
        self.tables = tables
        self.isFavorite = isFavorite
    }
}

@MainActor
public final class DatabaseTemplateManager {
    public static let shared = DatabaseTemplateManager()
    public static let templatesKey = "com.swiftcode.database.templates"

    public private(set) var templates: [DatabaseTemplate] = []
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadTemplates()
        if templates.isEmpty {
            templates = Self.seededTemplates
            saveTemplates()
        }
    }

    public static var seededTemplates: [DatabaseTemplate] {
        [
            DatabaseTemplate(
                name: "User Authentication", category: "Authentication",
                description: "Production-grade schema for user signups, credentials, roles, and profiles.",
                tags: ["Security", "Users", "Auth"],
                tables: [
                    DatabaseTemplateTable(name: "users", columns: [
                        DatabaseTemplateColumn(name: "id", type: "UUID", isPrimaryKey: true, isNullable: false),
                        DatabaseTemplateColumn(name: "email", type: "VARCHAR(255)", isNullable: false, isUnique: true),
                        DatabaseTemplateColumn(name: "password_hash", type: "TEXT", isNullable: false),
                        DatabaseTemplateColumn(name: "created_at", type: "TIMESTAMP", isNullable: false, defaultValue: "CURRENT_TIMESTAMP"),
                    ]),
                    DatabaseTemplateTable(name: "profiles", columns: [
                        DatabaseTemplateColumn(name: "user_id", type: "UUID", isPrimaryKey: true, isNullable: false, isForeignKey: true),
                        DatabaseTemplateColumn(name: "display_name", type: "VARCHAR(255)"),
                        DatabaseTemplateColumn(name: "avatar_url", type: "TEXT"),
                    ], relationships: [
                        DatabaseTemplateRelationship(type: .oneToOne, sourceTable: "profiles", sourceColumn: "user_id", targetTable: "users", targetColumn: "id"),
                    ]),
                ]
            ),
            DatabaseTemplate(
                name: "E-Commerce System", category: "E-Commerce",
                description: "Scalable schema containing users, products, orders, and structured line items.",
                tags: ["Sales", "Products", "Billing"],
                tables: [
                    DatabaseTemplateTable(name: "products", columns: [
                        DatabaseTemplateColumn(name: "id", type: "INTEGER", isPrimaryKey: true, isAutoIncrement: true),
                        DatabaseTemplateColumn(name: "sku", type: "VARCHAR(50)", isNullable: false, isUnique: true),
                        DatabaseTemplateColumn(name: "name", type: "VARCHAR(255)", isNullable: false),
                        DatabaseTemplateColumn(name: "price", type: "REAL", isNullable: false),
                        DatabaseTemplateColumn(name: "stock_quantity", type: "INTEGER", isNullable: false, defaultValue: "0"),
                    ]),
                    DatabaseTemplateTable(name: "orders", columns: [
                        DatabaseTemplateColumn(name: "id", type: "INTEGER", isPrimaryKey: true, isAutoIncrement: true),
                        DatabaseTemplateColumn(name: "user_id", type: "UUID", isNullable: false),
                        DatabaseTemplateColumn(name: "total_amount", type: "REAL", isNullable: false),
                        DatabaseTemplateColumn(name: "ordered_at", type: "TIMESTAMP", isNullable: false, defaultValue: "CURRENT_TIMESTAMP"),
                    ]),
                ]
            ),
        ]
    }

    public func addTemplate(_ template: DatabaseTemplate) {
        templates.append(template)
        saveTemplates()
    }

    public func toggleFavorite(_ template: DatabaseTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].isFavorite.toggle()
            saveTemplates()
        }
    }

    public static func createSQL(for template: DatabaseTemplate) -> String {
        template.tables.map { table in
            var parts: [String] = table.columns.map { column in
                var definition = "\(DatabaseSQL.quoted(column.name)) \(DatabaseSQL.sqliteType(column.type))"
                if column.isPrimaryKey { definition += " PRIMARY KEY" }
                if column.isAutoIncrement && DatabaseSQL.sqliteType(column.type) == "INTEGER" {
                    definition += " AUTOINCREMENT"
                }
                if column.isUnique { definition += " UNIQUE" }
                if !column.isNullable { definition += " NOT NULL" }
                if let defaultValue = column.defaultValue {
                    if defaultValue == "CURRENT_TIMESTAMP" || Double(defaultValue) != nil {
                        definition += " DEFAULT \(defaultValue)"
                    } else {
                        definition += " DEFAULT '\(defaultValue.replacingOccurrences(of: "'", with: "''"))'"
                    }
                }
                return definition
            }
            for relationship in table.relationships {
                parts.append("FOREIGN KEY (\(DatabaseSQL.quoted(relationship.sourceColumn))) REFERENCES \(DatabaseSQL.quoted(relationship.targetTable)) (\(DatabaseSQL.quoted(relationship.targetColumn)))")
            }
            return "CREATE TABLE \(DatabaseSQL.quoted(table.name)) (\n  \(parts.joined(separator: ",\n  "))\n);"
        }.joined(separator: "\n")
    }

    public func apply(_ template: DatabaseTemplate, to db: SQLiteDatabase) throws {
        try db.transaction {
            try db.execute(Self.createSQL(for: template))
        }
    }

    private func loadTemplates() {
        if let data = userDefaults.data(forKey: Self.templatesKey),
           let decoded = try? JSONDecoder().decode([DatabaseTemplate].self, from: data) {
            templates = decoded
        }
    }

    private func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            userDefaults.set(encoded, forKey: Self.templatesKey)
        }
    }
}
