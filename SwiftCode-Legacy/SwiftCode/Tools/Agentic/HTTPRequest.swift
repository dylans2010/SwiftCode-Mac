import Foundation

public struct HTTPRequestTool: AgentTool {
    public static let identifier = "http_request"
    public let name = "http_request"
    public let description = "Performs an HTTP request."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "url": ["type": "string"] as [String: any Sendable],
            "method": ["type": "string"] as [String: any Sendable],
            "headers": [
                "type": "object",
                "additionalProperties": ["type": "string"] as [String: any Sendable]
            ] as [String: any Sendable],
            "body": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["url", "method"]
    ]

    public func run(url: String, method: String, headers: [String: String], body: String?) async throws -> String {
        guard let urlObj = URL(string: url) else { throw AppError.commonError("Invalid URL") }
        var request = URLRequest(url: urlObj)
        request.httpMethod = method
        for (key, value) in headers { request.addValue(value, forHTTPHeaderField: key) }
        if let body = body { request.httpBody = body.data(using: .utf8) }
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let url = arguments["url"] as? String,
              let method = arguments["method"] as? String else {
            throw AgentError.toolError("Missing url or method")
        }
        let headers = arguments["headers"] as? [String: String] ?? [:]
        let body = arguments["body"] as? String
        return try await run(url: url, method: method, headers: headers, body: body)
    }
}
