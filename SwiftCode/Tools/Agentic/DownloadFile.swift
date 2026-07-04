import Foundation

public struct DownloadFileTool: AgentTool {
    public static let identifier = "download_file"
    public let name = "download_file"
    public let description = "Downloads a file from a URL."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "url": ["type": "string"] as [String: any Sendable],
            "destinationPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["url", "destinationPath"]
    ]

    public func run(url: String, destinationPath: String) async throws {
        guard let urlObj = URL(string: url) else { throw AppError.commonError("Invalid URL") }
        let (tempURL, _) = try await URLSession.shared.download(from: urlObj)
        let destURL = URL(fileURLWithPath: destinationPath)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let url = arguments["url"] as? String,
              let destinationPath = arguments["destinationPath"] as? String else {
            throw AgentError.toolError("Missing url or destinationPath")
        }
        try await run(url: url, destinationPath: destinationPath)
        return "Successfully downloaded \(url) to \(destinationPath)"
    }
}
