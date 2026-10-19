import Foundation

public struct AssistArtboardRunAppTool: AssistTool {
    public let id = "artboard_run_app"
    public let name = "Run Full App"
    public let description = "Builds the active project and runs it directly inside an iOS/macOS simulator, reporting logs and execution status."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds and runs the full app on the target simulator.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let runManager = FullAppRunManager.shared
        if runManager.isRunning {
            return .failure("An application execution run is already in progress.")
        }

        await runManager.runFullApp()

        let logs = runManager.runLogs.joined(separator: "\n")
        let isFailed = logs.localizedCaseInsensitiveContains("failed") || logs.localizedCaseInsensitiveContains("error:")

        if isFailed {
            return .failure("Full app run failed.\nStep: \(runManager.currentStep)\nLogs:\n\(logs.suffix(2000))")
        } else {
            return .success("Full application compiled and launched successfully.\nDuration: \(String(format: "%.1fs", runManager.buildDuration))\nLogs:\n\(logs.suffix(1000))", data: [
                "duration": "\(runManager.buildDuration)",
                "step": runManager.currentStep
            ])
        }
    }
}
