import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "CodeReviewTool")

@MainActor
public struct CodeReviewTool: AssistTool {
    public let id = "code_review"
    public let name = "Code Review Validation"
    public let description = "Validates the completed implementation using an independent AI reviewer stage before finishing the task."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "No input parameters needed. Automatically gathers task history, repository modifications, and build state to perform an independent verification."
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        AssistManager.shared.isCodeReviewRunning = true
        AssistManager.shared.hasCodeReviewBeenInvoked = true
        defer {
            AssistManager.shared.isCodeReviewRunning = false
        }

        await context.logger.info("Initializing Autonomous Code Review stage...", toolId: id)

        // 1. Load System Prompt from Resource Bundle
        let systemPrompt: String
        do {
            systemPrompt = try CodeReviewSystemLoader.getReviewSystemPrompt()
        } catch {
            let errorMsg = "System Configuration Error: Failed to load CodeReviewSystemAsset.md from bundle: \(error.localizedDescription)"
            await context.logger.error(errorMsg, toolId: id)
            return .failure(errorMsg)
        }

        // 2. Gather context
        let originalRequest = AssistManager.shared.agentSession.state.objective
        let isAgentMode = UserDefaults.standard.bool(forKey: "com.swiftcode.assist.mode")
        let executionMode = isAgentMode ? "com.SwiftCode.Assist-Agent (Agentic Mode)" : "com.SwiftCode.Assist-Chat (Chat Mode)"

        // Compile action & tool executions
        let completedActions = AssistManager.shared.agentSession.state.completedActions.joined(separator: "\n- ")
        let toolHistory = AssistManager.shared.agentSession.state.events.map { event in
            "[\(event.timestamp.description)] [\(event.state.rawValue)]: \(event.summary)"
        }.joined(separator: "\n")

        // Build planning summary
        let planSummary = AssistManager.shared.agentSession.state.plan.map { step in
            "Step: \(step.description) (Tool: \(step.toolId)) - Status: \(step.status.rawValue)"
        }.joined(separator: "\n")

        // Gather repo changes (created, modified, deleted)
        var changesSummary = "No snapshots or changes detected."
        do {
            let snapshots = try AssistSnapshotFunctions.listSnapshots()
            if let latest = snapshots.first {
                let diffs = try AssistSnapshotFunctions.compare(project: context.workspaceRoot, withSnapshot: latest.id)
                if !diffs.isEmpty {
                    let added = diffs.filter { $0.status == .added }.map { $0.path }
                    let modified = diffs.filter { $0.status == .modified }.map { $0.path }
                    let deleted = diffs.filter { $0.status == .deleted }.map { $0.path }

                    changesSummary = """
                    Created files:
                    - \(added.isEmpty ? "None" : added.joined(separator: "\n- "))

                    Modified files:
                    - \(modified.isEmpty ? "None" : modified.joined(separator: "\n- "))

                    Deleted files:
                    - \(deleted.isEmpty ? "None" : deleted.joined(separator: "\n- "))
                    """
                }
            }
        } catch {
            changesSummary = "Failed to query repository changes: \(error.localizedDescription)"
        }

        // Gather build results, validation results, and compiler diagnostics from events
        let buildEvents = AssistManager.shared.agentSession.state.events.filter { $0.summary.contains("Build") || $0.summary.contains("build") }
        let buildSummary = buildEvents.map { $0.summary }.joined(separator: "\n")

        let userPrompt = """
        # OBJECTIVE / ORIGINAL USER REQUEST
        \(originalRequest)

        # CURRENT RUNTIME STATE
        - Active Execution Mode: \(executionMode)
        - Tool Call Count: \(AssistManager.shared.agentSession.state.toolCallCount)

        # IMPLEMENTATION PROGRESS
        Completed Actions:
        - \(completedActions.isEmpty ? "No actions recorded yet." : completedActions)

        Planning Checklist:
        \(planSummary.isEmpty ? "No explicit plan recorded." : planSummary)

        # TOOL EXECUTION EVENT HISTORY
        \(toolHistory.isEmpty ? "No tool executions recorded." : toolHistory)

        # REPOSITORY FILE MODIFICATIONS
        \(changesSummary)

        # BUILD AND VALIDATION STATUS SUMMARY
        \(buildSummary.isEmpty ? "No recent build or validation tool output detected." : buildSummary)
        """

        // 3. Independent Model Selection (Must not be identical to implementation model)
        let implementationModel = AppSettings.shared.selectedModel
        let isFMEnabled = FoundationModels.shared.isEnabled

        let activeProvider: LLMProvider
        do {
            activeProvider = try LLMService.shared.resolvedRoutingProvider()
        } catch {
            activeProvider = .openRouter
        }

        let reviewerModel: String
        var providerOverride: LLMProvider? = nil

        if isFMEnabled {
            // Apple foundation models: swap between afm3Core and afm3CoreAdvanced
            let currentFM = FoundationModels.shared.selectedModel
            let otherFM: AppleFoundationModel = (currentFM == .afm3Core) ? .afm3CoreAdvanced : .afm3Core
            reviewerModel = otherFM.rawValue
        } else if activeProvider == .codex {
            // Codex: fallback to OpenRouter gpt-4o-mini
            reviewerModel = "openai/gpt-4o-mini"
            providerOverride = .openRouter
        } else {
            // OpenRouter: find an alternative model
            let candidates = [
                "openai/gpt-4o-mini",
                "openai/gpt-4o",
                "anthropic/claude-3.5-sonnet",
                "google/gemini-2.5-pro",
                "meta-llama/llama-3-70b-instruct"
            ]
            reviewerModel = candidates.first { $0 != implementationModel } ?? "openai/gpt-4o-mini"
        }

        await context.logger.info("Selected Reviewer Model: \(reviewerModel)", toolId: id)

        // 4. Invoke LLMService
        do {
            let messages = [
                AIMessage(role: .system, content: systemPrompt),
                AIMessage(role: .user, content: userPrompt)
            ]

            let response: LLMResponse
            if isFMEnabled {
                // For FoundationModels, we temporarily toggle the selected model
                let originalFM = FoundationModels.shared.selectedModel
                if let appleModel = AppleFoundationModel(rawValue: reviewerModel) {
                    FoundationModels.shared.selectedModel = appleModel
                }
                defer {
                    FoundationModels.shared.selectedModel = originalFM
                }

                let resultText = try await FoundationModels.shared.generatePrivateResponse(prompt: userPrompt)
                response = LLMResponse(
                    modelName: reviewerModel,
                    completionText: resultText,
                    tokenUsage: nil,
                    latency: 1.0
                )
            } else {
                response = try await LLMService.shared.sendChatRequest(
                    model: reviewerModel,
                    messages: messages,
                    providerOverride: providerOverride
                )
            }

            let reviewText = response.completionText.trimmingCharacters(in: .whitespacesAndNewlines)

            // 5. Robust JSON Parsing
            guard let reviewData = extractJSON(from: reviewText) else {
                let parseError = "Syntax Error: Reviewer returned an invalid or non-JSON formatted output."
                await context.logger.error(parseError + " Content:\n\(reviewText)", toolId: id)
                return .failure(parseError)
            }

            // Extract status to ensure contract compliance
            let status = (reviewData["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if status != "task_ready" && status != "task_failed" {
                let contractViolation = "Contract Error: Reviewer returned invalid status '\(status)'. Required exactly: 'task_ready' or 'task_failed'."
                await context.logger.error(contractViolation, toolId: id)
                return .failure(contractViolation)
            }

            // Update global code review manager state
            await updateReviewState(reviewData: reviewData)

            let output = "Review completed. Status: \(status). Summary: \(reviewData["summary"] as? String ?? "")"
            // We return success with output and structured payload
            let serializedData = reviewData.mapValues { "\($0)" }
            return .success(output, data: serializedData)

        } catch {
            let errorMsg = "Review invocation failed: \(error.localizedDescription)"
            await context.logger.error(errorMsg, toolId: id)
            return .failure(errorMsg)
        }
    }

    private func extractJSON(from response: String) -> [String: Any]? {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func updateReviewState(reviewData: [String: Any]) async {
        let status = reviewData["status"] as? String ?? "task_failed"
        let summary = reviewData["summary"] as? String ?? ""
        let strengths = reviewData["strengths"] as? [String] ?? []
        let issues = reviewData["issues"] as? [String] ?? []
        let recommendedFixes = reviewData["recommendedFixes"] as? [String] ?? []
        let userSee = reviewData["user_see"] as? String ?? ""
        let confidence = reviewData["confidence"] as? Double ?? 0.0

        let result = CodeReviewInternalResult(
            status: status,
            summary: summary,
            strengths: strengths,
            issues: issues,
            recommendedFixes: recommendedFixes,
            userSee: userSee,
            confidence: confidence
        )

        AssistManager.shared.currentCodeReview = result
    }
}

// MARK: - Internal Helper Types

public struct CodeReviewInternalResult: Codable, Sendable {
    public let status: String
    public let summary: String
    public let strengths: [String]
    public let issues: [String]
    public let recommendedFixes: [String]
    public let userSee: String
    public let confidence: Double
}

@MainActor
public final class CodeReviewSystemLoader {
    private static var cachedPrompt: String?

    public static func getReviewSystemPrompt() throws -> String {
        if let cached = cachedPrompt {
            return cached
        }

        guard let url = Bundle.main.url(forResource: "CodeReviewSystemAsset", withExtension: "md") else {
            throw NSError(domain: "CodeReviewSystemLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to locate CodeReviewSystemAsset.md in application bundle."])
        }

        let prompt = try String(contentsOf: url, encoding: .utf8)
        cachedPrompt = prompt
        return prompt
    }
}
