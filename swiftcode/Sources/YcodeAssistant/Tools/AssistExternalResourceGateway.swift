import Foundation

public struct AssistExternalResourceGateway: AssistTool {
    public let id = "external_resource_gateway"
    public let name = "External Resource Gateway"
    public let description = "Fetches external APIs and returns structured JSON response data."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .externalSideEffect }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Performs an HTTPS GET against an external URL and returns structured JSON response data. HTTPS only; non-2xx responses are failures. 30s timeout.",
            properties: [
                "url": JSONSchema(type: "string", description: "Fully qualified HTTPS URL to fetch. Must return a JSON body. http://, file://, and other schemes are rejected.")
            ],
            required: ["url"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let urlString = input["url"] as? String, let url = URL(string: urlString) else {
            return .failure("Missing or invalid url")
        }
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            return .failure("Only HTTPS URLs with a host are allowed (got '\(urlString)').")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failure("Fetch failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { return .failure("Invalid HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            return .failure("HTTP \(http.statusCode) from \(urlString).")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .failure("Response was not valid JSON: \(error.localizedDescription)")
        }
        let normalized = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        let payload = String(data: normalized, encoding: .utf8) ?? "{}"

        return .success("Fetched external resource.", data: ["status_code": "\(http.statusCode)", "json": payload])
    }
}
