import Foundation

public struct AssistTestRunnerTool: AssistTool {
    public let id = "project_test"
    public let name = "Run Tests"
    public let description = "Executes test suites and test plans using xcodebuild test with proper platform targeting."
    public let capability: ToolCapability = .testing
    public let riskLevel: ToolRiskLevel = .execution

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs tests for the current project or a specific scheme.",
            properties: [
                "scheme": JSONSchema(type: "string", description: "The scheme to test (defaults to active project or 'SwiftCode')."),
                "testPlan": JSONSchema(type: "string", description: "Optional name of the test plan to execute.")
            ],
            required: []
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let scheme = input["scheme"] as? String
        _ = scheme
        let testPlan = input["testPlan"] as? String
        _ = testPlan

        await context.logger.info("Executing tests via AssistVerificationPipeline", toolId: id)

        let outcome = await AssistVerificationPipeline.shared.verifyTests(context: context)

        let diagStrings = outcome.diagnostics.map { "\($0.filePath):\($0.line): \($0.severity.rawValue): \($0.message)" }
        let resultData: [String: String] = [
            "status": outcome.isSuccess ? "Passed" : "Failed",
            "duration": String(format: "%.2fs", outcome.duration),
            "diagnostics_count": "\(outcome.diagnostics.count)"
        ]

        if outcome.isSuccess {
            return AssistToolResult(
                success: true,
                output: "Tests Passed (\(String(format: "%.2fs", outcome.duration))):\n\(outcome.output)",
                data: resultData,
                diagnostics: diagStrings,
                duration: outcome.duration,
                exitCode: 0,
                suggestedNextActions: ["code_review", "project_diff"]
            )
        } else {
            let diagnosticSummary = diagStrings.prefix(5).joined(separator: "\n")
            return AssistToolResult(
                success: false,
                output: "Tests Failed (\(String(format: "%.2fs", outcome.duration))):\n\(diagnosticSummary)\n\n\(outcome.error ?? "")",
                data: resultData,
                error: outcome.error ?? "Test failures encountered during test run.",
                errorCode: 1,
                diagnostics: diagStrings,
                duration: outcome.duration,
                exitCode: 1,
                suggestedNextActions: ["file_read", "code_replace", "project_build"]
            )
        }
    }
}
