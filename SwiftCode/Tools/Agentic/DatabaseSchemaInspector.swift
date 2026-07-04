import Foundation

public struct DatabaseSchemaInspectorTool: AgentTool {
    public static let identifier = "database_schema_inspector"
    public let name = "database_schema_inspector"
    public let description = "Inspects the schema of a database."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "databasePath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["databasePath"]
    ]

    public func run(databasePath: String) async throws -> String {
        return "Schema for \(databasePath)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let databasePath = arguments["databasePath"] as? String else {
            throw AgentError.toolError("Missing databasePath")
        }
        return try await run(databasePath: databasePath)
    }
}
