import Foundation

public struct CallHierarchyTool: AgentTool {
    public static let identifier = "call_hierarchy"
    public let name = "call_hierarchy"
    public let description = "Displays the call hierarchy of a symbol."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "symbol": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["symbol"]
    ]

    public func run(symbol: String) async throws -> String {
        return "Call hierarchy for \(symbol)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let symbol = arguments["symbol"] as? String else {
            throw AgentError.toolError("Missing symbol")
        }
        return try await run(symbol: symbol)
    }
}
