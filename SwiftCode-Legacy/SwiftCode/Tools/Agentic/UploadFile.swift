import Foundation

public struct UploadFileTool: AgentTool {
    public static let identifier = "upload_file"
    public let name = "upload_file"
    public let description = "Uploads a file to a URL."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable],
            "url": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path", "url"]
    ]

    public func run(path: String, url: String) async throws -> String {
        guard let urlObj = URL(string: url) else { throw AppError.commonError("Invalid URL") }
        let fileURL = URL(fileURLWithPath: path)
        var request = URLRequest(url: urlObj)
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String,
              let url = arguments["url"] as? String else {
            throw AgentError.toolError("Missing path or url")
        }
        return try await run(path: path, url: url)
    }
}
