import Foundation

public struct DatabaseUtilities {
    public static func defaultSQLForCreateTable(table: DatabaseTable, provider: DatabaseProvider) -> String {
        var sql = "CREATE TABLE \(table.name) (\n"
        var columnsSql: [String] = []

        for col in table.columns {
            var colDef = "    \(col.name) \(col.type)"
            if col.isPrimaryKey {
                if provider == .sqlite && col.isAutoIncrement {
                    colDef += " PRIMARY KEY AUTOINCREMENT"
                } else if provider == .postgresql || provider == .supabase {
                    if col.isAutoIncrement {
                        colDef = "    \(col.name) SERIAL PRIMARY KEY"
                    } else {
                        colDef += " PRIMARY KEY"
                    }
                } else {
                    colDef += " PRIMARY KEY"
                    if col.isAutoIncrement {
                        colDef += " AUTO_INCREMENT"
                    }
                }
            } else {
                if !col.isNullable {
                    colDef += " NOT NULL"
                }
                if col.isUnique {
                    colDef += " UNIQUE"
                }
                if let df = col.defaultValue {
                    colDef += " DEFAULT \(df)"
                }
                if let chk = col.checkConstraint {
                    colDef += " CHECK (\(chk))"
                }
            }
            columnsSql.append(colDef)
        }

        // Relationships / Foreign Keys
        for rel in table.relationships {
            if rel.type == .oneToMany || rel.type == .oneToOne {
                var fkDef = "    FOREIGN KEY (\(rel.sourceColumn)) REFERENCES \(rel.targetTable)(\(rel.targetColumn))"
                if rel.onDelete != .noAction {
                    fkDef += " ON DELETE \(rel.onDelete.rawValue)"
                }
                if rel.onUpdate != .noAction {
                    fkDef += " ON UPDATE \(rel.onUpdate.rawValue)"
                }
                columnsSql.append(fkDef)
            }
        }

        sql += columnsSql.joined(separator: ",\n")
        sql += "\n);"
        return sql
    }
}
