import Foundation

public struct SchemaValidationIssue: Identifiable, Hashable {
    public let id = UUID()
    public var tableName: String
    public var message: String
    public var severity: String
}

public final class DatabaseValidationManager: Sendable {
    public static let shared = DatabaseValidationManager()

    private init() {}

    public func validateSchema(tables: [DatabaseTable]) -> [SchemaValidationIssue] {
        var issues: [SchemaValidationIssue] = []

        for table in tables {
            let hasPK = table.columns.contains { $0.isPrimaryKey }
            if !hasPK && !table.isView && !table.isMaterializedView {
                issues.append(SchemaValidationIssue(
                    tableName: table.name,
                    message: "Table '\(table.name)' has no primary key defined.",
                    severity: "ERROR"
                ))
            }

            var colNames = Set<String>()
            for col in table.columns {
                if colNames.contains(col.name) {
                    issues.append(SchemaValidationIssue(
                        tableName: table.name,
                        message: "Duplicate column '\(col.name)' defined in table '\(table.name)'.",
                        severity: "ERROR"
                    ))
                }
                colNames.insert(col.name)
            }

            for rel in table.relationships {
                let targetExists = tables.contains { $0.name == rel.targetTable }
                if !targetExists {
                    issues.append(SchemaValidationIssue(
                        tableName: table.name,
                        message: "Relationship points to a non-existent target table '\(rel.targetTable)'.",
                        severity: "ERROR"
                    ))
                } else if let targetTableObj = tables.first(where: { $0.name == rel.targetTable }) {
                    let targetColExists = targetTableObj.columns.contains { $0.name == rel.targetColumn }
                    if !targetColExists {
                        issues.append(SchemaValidationIssue(
                            tableName: table.name,
                            message: "Relationship points to a non-existent target column '\(rel.targetColumn)' in table '\(rel.targetTable)'.",
                            severity: "ERROR"
                        ))
                    }
                }
            }
        }

        return issues
    }
}
