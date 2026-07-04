import Foundation

public struct ParseXMLTool: AgentTool {
    public static let identifier = "parse_xml"
    public let name = "parse_xml"
    public let description = "Parses an XML string."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "xml": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["xml"]
    ]

    public func run(xml: String) async throws -> String {
        return "Parsed XML (simulated)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let xml = arguments["xml"] as? String else {
            throw AgentError.toolError("Missing xml")
        }
        return try await run(xml: xml)
    }
}
