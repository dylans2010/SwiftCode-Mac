import Foundation

public struct DatabaseMigrationTool: AgentTool {
    public static let identifier = "database_migration"
    public let name = "database_migration"
    public let description = "Applies a database migration."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "databasePath": ["type": "string"] as [String: any Sendable],
            "migrationPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["databasePath", "migrationPath"]
    ]

    public func run(databasePath: String, migrationPath: String) async throws -> String {
        return "Migration applied to \(databasePath)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let databasePath = arguments["databasePath"] as? String,
              let migrationPath = arguments["migrationPath"] as? String else {
            throw AgentError.toolError("Missing databasePath or migrationPath")
        }
        return try await run(databasePath: databasePath, migrationPath: migrationPath)
    }
}
