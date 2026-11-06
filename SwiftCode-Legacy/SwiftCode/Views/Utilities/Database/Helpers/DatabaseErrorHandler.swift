import Foundation

public enum DatabaseError: Error, LocalizedError {
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
        case .connectionFailed(let msg):
            return "Connection Failed: \(msg)"
        case .queryExecutionFailed(let msg, let sql):
            return "SQL Execution Error: \(msg) [SQL: \(sql)]"
        case .schemaModificationFailed(let msg):
            return "Schema Modification Failed: \(msg)"
        case .tableNotFound(let name):
            return "Table not found: \(name)"
        case .validationFailed(let msg):
            return "Validation Error: \(msg)"
        case .importFailed(let msg):
            return "Import Failed: \(msg)"
        case .exportFailed(let msg):
            return "Export Failed: \(msg)"
        case .syncFailed(let msg):
            return "Sync Failed: \(msg)"
        }
    }
}
