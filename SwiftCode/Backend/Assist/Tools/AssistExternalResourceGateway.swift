import Foundation

public struct AssistExternalResourceGateway: AssistTool {
    public let id = "external_resource_gateway"
    public let name = "External Resource Gateway"
    public let description = "Fetches external APIs and returns structured JSON response data."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Performs an HTTP GET against an external URL and returns structured JSON response data.",
            properties: [
                "url": JSONSchema(type: "string", description: "Fully qualified HTTP(S) URL to fetch. Must return a JSON body.")
            ],
            required: ["url"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let urlString = input["url"] as? String, let url = URL(string: urlString) else {
            return .failure("Missing or invalid url")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { return .failure("Invalid HTTP response") }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let normalized = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        let payload = String(data: normalized, encoding: .utf8) ?? "{}"

        return .success("Fetched external resource.", data: ["status_code": "\(http.statusCode)", "json": payload])
    }
}
