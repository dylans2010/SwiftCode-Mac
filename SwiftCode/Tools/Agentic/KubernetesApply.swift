import Foundation

public struct KubernetesApplyTool: AgentTool {
    public static let identifier = "kubernetes_apply"
    public let name = "kubernetes_apply"
    public let description = "Applies a Kubernetes configuration."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path"]
    ]

    public func run(path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/kubectl"),
            arguments: ["apply", "-f", path]
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AgentError.toolError("Missing path")
        }
        return try await run(path: path)
    }
}
