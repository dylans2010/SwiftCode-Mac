import Foundation

public struct UpdateEnvironmentVariablesTool: AgentTool {
    public static let identifier = "update_environment_variables"
    public let name = "update_environment_variables"
    public let description = "Updates environment variables."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "variables": [
                "type": "object",
                "additionalProperties": ["type": "string"] as [String: any Sendable]
            ] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["variables"]
    ]

    public func run(variables: [String: String]) async throws {
        for (key, value) in variables {
            setenv(key, value, 1)
        }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let variables = arguments["variables"] as? [String: String] else {
            throw AgentError.toolError("Missing variables")
        }
        try await run(variables: variables)
        return "Environment variables updated"
    }
}
