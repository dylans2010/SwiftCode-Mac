import Foundation

public struct KubernetesApplyTool {
    public static let identifier = "kubernetes_apply"

    public func run(path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/kubectl"),
            arguments: ["apply", "-f", path]
        )
        return result.stdout + result.stderr
    }
}
