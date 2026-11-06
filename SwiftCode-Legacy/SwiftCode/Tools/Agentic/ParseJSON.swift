import Foundation

public struct ParseJSONTool: AgentTool {
    public static let identifier = "parse_json"
    public let name = "parse_json"
    public let description = "Parses a JSON string."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "json": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["json"]
    ]

    public func run(json: String) async throws -> [String: any Sendable] {
        guard let data = json.data(using: .utf8) else { throw AppError.commonError("Invalid JSON") }
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: any Sendable] else {
            throw AppError.commonError("JSON is not a dictionary")
        }
        return dictionary
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let json = arguments["json"] as? String else {
            throw AgentError.toolError("Missing json")
        }
        let result = try await run(json: json)
        return "\(result)"
    }
}
