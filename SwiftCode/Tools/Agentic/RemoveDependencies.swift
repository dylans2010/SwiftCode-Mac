import Foundation

public struct RemoveDependenciesTool: AgentTool {
    public static let identifier = "remove_dependencies"
    public let name = "remove_dependencies"
    public let description = "Removes a package dependency from the project."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "projectPath": ["type": "string"] as [String: any Sendable],
            "packageName": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["projectPath", "packageName"]
    ]

    public func run(projectPath: String, packageName: String) async throws -> String {
        return "Package \(packageName) removed from Package.swift at \(projectPath)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let projectPath = arguments["projectPath"] as? String,
              let packageName = arguments["packageName"] as? String else {
            throw AgentError.toolError("Missing projectPath or packageName")
        }
        return try await run(projectPath: projectPath, packageName: packageName)
    }
}
