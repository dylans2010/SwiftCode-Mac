import Foundation

public struct AgentToolRegistry: Sendable {
    public static let shared = AgentToolRegistry()

    public func schema() -> [[String: any Sendable]] {
        return ListTools.shared.tools.map { (_, agentTool) in
            let function: [String: any Sendable] = [
                "name": agentTool.name,
                "description": agentTool.description,
                "parameters": agentTool.schema
            ]

            return [
                "type": "function",
                "function": function
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
