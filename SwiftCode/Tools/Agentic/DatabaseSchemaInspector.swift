import Foundation

public struct DatabaseSchemaInspectorTool {
    public static let identifier = "database_schema_inspector"

    public func run(databasePath: String) async throws -> String {
        return "Schema for \(databasePath)"
    }
}
