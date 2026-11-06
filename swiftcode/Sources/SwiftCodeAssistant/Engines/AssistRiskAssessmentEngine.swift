// STAGED PORT — SwiftCode-Legacy `Backend/Assist/Assist Frameworks/AssistRiskAssessmentEngine.swift`
// (Legacy main d51a8f0d; Dylan's own code, direct port authorised under MIT).
// Target: SwiftCodeAssistant. Body is Legacy verbatim unless noted below.
// Dependency of _AssistCriticalAutonomousEngine (risk phase). Ledger SUPERSEDED by SwiftCodeMCP/Host/MCPServer.swift — the MCP server, non-importable from SwiftCodeAssistant, exposes no assessRisk(plan:) -> RiskAssessment class API. Ported verbatim.
// Remaining deps (now staged in AssistModels.swift by the parallel port — see _notes/agent-models-decisions.md): AssistContext (logger, safetyLevel), AssistExecutionPlan.

import Foundation

/// Assesses risks in planned operations before execution
@MainActor
public final class AssistRiskAssessmentEngine {
    private let context: AssistContext

    public enum RiskLevel {
        case low
        case medium
        case high
        case critical
    }

    public struct RiskAssessment {
        let level: RiskLevel
        let concerns: [String]
        let shouldProceed: Bool
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Assesses the risk of executing a plan
    public func assessRisk(plan: AssistExecutionPlan) async -> RiskAssessment {
        await context.logger.info("Assessing execution risk for: \(plan.goal)", toolId: "RiskAssessment")

        var concerns: [String] = []
        var riskScore = 0

        // Check for destructive operations
        let destructiveTools = ["deleteFile", "deleteDirectory", "file_delete"]
        for step in plan.steps where destructiveTools.contains(step.toolId) {
            concerns.append("Destructive operation: \(step.toolId)")
            riskScore += 2
        }

        // Check for external operations
        let externalTools = ["external_resource", "network_request"]
        for step in plan.steps where externalTools.contains(step.toolId) {
            concerns.append("External operation: \(step.toolId)")
            riskScore += 1
        }

        // Check for project structure modifications
        if plan.steps.contains(where: { $0.input["path"]?.contains(".xcodeproj") == true }) {
            concerns.append("Project structure modification detected")
            riskScore += 1
        }

        // Determine risk level
        let level: RiskLevel
        if riskScore >= 5 {
            level = .critical
        } else if riskScore >= 3 {
            level = .high
        } else if riskScore >= 1 {
            level = .medium
        } else {
            level = .low
        }

        // Decide if we should proceed
        let shouldProceed: Bool
        switch level {
        case .low, .medium:
            shouldProceed = true
        case .high:
            shouldProceed = context.safetyLevel != .conservative
        case .critical:
            shouldProceed = false
        }

        if !concerns.isEmpty {
            await context.logger.warning("Risk assessment: \(level) - \(concerns.joined(separator: ", "))", toolId: "RiskAssessment")
        }

        return RiskAssessment(level: level, concerns: concerns, shouldProceed: shouldProceed)
    }
}
