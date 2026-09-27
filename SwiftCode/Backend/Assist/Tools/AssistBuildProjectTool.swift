import Foundation

public struct AssistBuildProjectTool: AssistTool {
    public let id = "project_build"
    public let name = "Build Project"
    public let description = "Builds the project incrementally and verifies compilation using real developer toolchains."
    public let capability: ToolCapability = .compilation
    public let riskLevel: ToolRiskLevel = .execution

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds the active Xcode or SwiftPM project.",
            properties: [
                "scheme": JSONSchema(type: "string", description: "The scheme to build (defaults to active project or 'SwiftCode')."),
                "configuration": JSONSchema(type: "string", description: "Build configuration (Debug or Release). Default is Debug.")
            ],
            required: []
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let scheme = input["scheme"] as? String
        let configuration = input["configuration"] as? String ?? "Debug"

        await context.logger.info("Executing build via AssistVerificationPipeline (scheme: \(scheme ?? "default"), config: \(configuration))", toolId: id)

        let outcome = await AssistVerificationPipeline.shared.verifyCompilation(context: context)

        let diagStrings = outcome.diagnostics.map { "\($0.filePath):\($0.line): \($0.severity.rawValue): \($0.message)" }
        let resultData: [String: String] = [
            "status": outcome.isSuccess ? "Passed" : "Failed",
            "duration": String(format: "%.2fs", outcome.duration),
            "diagnostics_count": "\(outcome.diagnostics.count)"
        ]

        if outcome.isSuccess {
            return AssistToolResult(
                success: true,
                output: "Build Succeeded (\(String(format: "%.2fs", outcome.duration))):\n\(outcome.output)",
                data: resultData,
                diagnostics: diagStrings,
                duration: outcome.duration,
                exitCode: 0,
                suggestedNextActions: ["project_test", "code_review"]
            )
        } else {
            let diagnosticSummary = diagStrings.prefix(5).joined(separator: "\n")
            return AssistToolResult(
                success: false,
                output: "Build Failed with \(outcome.diagnostics.count) errors (\(String(format: "%.2fs", outcome.duration))):\n\(diagnosticSummary)\n\n\(outcome.error ?? "")",
                data: resultData,
                error: outcome.error ?? "Compilation errors encountered during build.",
                errorCode: 1,
                diagnostics: diagStrings,
                duration: outcome.duration,
                exitCode: 1,
                suggestedNextActions: ["file_read", "code_replace", "diagnostic_inspect"]
            )
        }
    }
}
