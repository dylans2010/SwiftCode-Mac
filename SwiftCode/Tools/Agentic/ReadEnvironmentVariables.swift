import Foundation

public struct ReadEnvironmentVariablesTool: AgentTool {
    public static let identifier = "read_environment_variables"
    public let name = "read_environment_variables"
    public let description = "Reads environment variables."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [:] as [String: any Sendable]
    ]

    public func run() async throws -> [String: String] {
        return ProcessInfo.processInfo.environment
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        let env = try await run()
        return env.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }
}
