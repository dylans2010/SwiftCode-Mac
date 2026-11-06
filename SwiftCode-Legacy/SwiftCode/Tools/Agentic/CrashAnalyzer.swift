import Foundation

public struct CrashAnalyzerTool: AgentTool {
    public static let identifier = "crash_analyzer"
    public let name = "crash_analyzer"
    public let description = "Analyzes crash logs."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "logPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["logPath"]
    ]

    public func run(logPath: String) async throws -> String {
        return "Analysis of crash log at \(logPath)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let logPath = arguments["logPath"] as? String else {
            throw AgentError.toolError("Missing logPath")
        }
        return try await run(logPath: logPath)
    }
}
