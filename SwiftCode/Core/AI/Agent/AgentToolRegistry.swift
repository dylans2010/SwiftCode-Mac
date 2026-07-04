import Foundation

public struct AgentToolRegistry: Sendable {
    public static let shared = AgentToolRegistry()

    public func schema() -> [[String: any Sendable]] {
        return ListTools.shared.tools.compactMap { (name, agentTool) in
            return [
                "type": "function",
                "function": [
                    "name": agentTool.name,
                    "description": agentTool.description,
                    "parameters": agentTool.schema
                ]
            ]
        }
    }

    public func execute(name: String, arguments: [String: any Sendable]) async throws -> String {
        guard let tool = ListTools.shared.tools[name] else {
            throw AgentError.toolError("Tool \(name) not found")
        }
        return try await tool.execute(arguments: arguments)
    }
}
