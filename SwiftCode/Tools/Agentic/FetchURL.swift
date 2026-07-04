import Foundation

public struct FetchURLTool: AgentTool {
    public static let identifier = "fetch_url"
    public let name = "fetch_url"
    public let description = "Fetches the content of a URL."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "url": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["url"]
    ]

    public func run(url: String) async throws -> String {
        guard let urlObj = URL(string: url) else { throw AppError.commonError("Invalid URL") }
        let (data, _) = try await URLSession.shared.data(from: urlObj)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let url = arguments["url"] as? String else {
            throw AgentError.toolError("Missing url")
        }
        return try await run(url: url)
    }
}
