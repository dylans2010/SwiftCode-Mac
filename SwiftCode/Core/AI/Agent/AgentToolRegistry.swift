import Foundation

public struct AgentToolRegistry: Sendable {
    public static let shared = AgentToolRegistry()

    public func schema() -> [[String: Any]] {
        return ListTools.shared.tools.compactMap { (name, tool) in
            guard let agentTool = tool as? AgentTool else { return nil }
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

    public func execute(name: String, arguments: [String: Any]) async throws -> String {
        guard let tool = ListTools.shared.tools[name] as? AgentTool else {
            throw AgentError.toolError("Tool \(name) not found or doesn't conform to AgentTool")
        }
        return try await tool.execute(arguments: arguments)
    }
}
