import Foundation

public struct DetectBugsTool: AgentTool {
    public static let identifier = "detect_bugs"
    public let name = "detect_bugs"
    public let description = "Detects bugs in Swift code."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "code": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["code"]
    ]

    public func run(code: String) async throws -> [String] {
        // Real implementation using swiftlint or similar if available, otherwise basic regex
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swiftlint"),
            arguments: ["lint", "--quiet"]
        )
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let code = arguments["code"] as? String else {
            throw AgentError.toolError("Missing code")
        }
        let bugs = try await run(code: code)
        if bugs.isEmpty {
            return "No bugs detected."
        }
        return bugs.joined(separator: "\n")
    }
}
