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

        // 1. Check if Code Review is enabled in settings
        let isReviewEnabled = UserDefaults.standard.object(forKey: "com.swiftcode.assist.enableCodeReview") as? Bool ?? true
        if !isReviewEnabled {
            await context.logger.info("Autonomous Code Review is disabled in settings. Skipping verification step.", toolId: id)
            let reviewData: [String: Any] = [
                "status": "task_ready",
                "summary": "Code Review skipped because Autonomous Code Review is disabled in settings.",
                "strengths": ["Bypassed Code Review Stage"],
                "issues": [] as [String],
                "recommendedFixes": [] as [String],
                "user_see": "Code Review bypassed per user configuration.",
                "confidence": 1.0
            ]
            await updateReviewState(reviewData: reviewData)
            return .success("Code Review disabled in settings. Bypassing review.", data: reviewData.mapValues { "\($0)" })
        }

        // 2. Load System Prompt from Resource Bundle
        let systemPrompt: String
        do {
            systemPrompt = try CodeReviewSystemLoader.getReviewSystemPrompt()
        } catch {
            let errorMsg = "System Configuration Error: Failed to load CodeReviewSystemAsset.md from bundle: \(error.localizedDescription)"
            await context.logger.error(errorMsg, toolId: id)
            return .failure(errorMsg)
        }

        // 3. Gather context
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

        // 4. Dynamic Model Selection & Fallback Queue
        let primaryModelID: String
        if FoundationModels.shared.isEnabled {
            primaryModelID = FoundationModels.shared.selectedModel.rawValue
        } else {
            primaryModelID = AppSettings.shared.selectedModel
        }

        var candidateModels = [primaryModelID]
        let defaultFallbacks = [
            "AFM 3 Core Advanced",
            "AFM 3 Core",
            "openai/gpt-4o-mini",
            "openai/gpt-4o",
            "anthropic/claude-3.5-sonnet",
            "google/gemini-2.5-pro",
            "meta-llama/llama-3-70b-instruct",
            "Codex",
            "gpt-4-codex",
            "gpt-4o",
            "gpt-4o-mini",
            "claude-3-5-sonnet-20241022",
            "gemini-1.5-pro",
            "gemini-1.5-flash"
        ]

        for item in defaultFallbacks {
            if !candidateModels.contains(item) {
                candidateModels.append(item)
            }
        }

        var finalResult: AssistToolResult? = nil

        for candidateModel in candidateModels {
            await context.logger.info("Attempting Autonomous Code Review with model: \(candidateModel)...", toolId: id)
            let resolvedProvider = LLMService.shared.provider(for: candidateModel)

            do {
                let messages = [
                    AIMessage(role: .system, content: systemPrompt),
                    AIMessage(role: .user, content: userPrompt)
                ]

                let response: LLMResponse

                if resolvedProvider == .offline || candidateModel == "AFM 3 Core" || candidateModel == "AFM 3 Core Advanced" {
                    // For FoundationModels, we temporarily toggle the selected model
                    let originalFMEnabled = FoundationModels.shared.isEnabled
                    let originalFM = FoundationModels.shared.selectedModel

                    FoundationModels.shared.isEnabled = true
                    if let appleModel = AppleFoundationModel(rawValue: candidateModel) {
                        FoundationModels.shared.selectedModel = appleModel
                    }

                    defer {
                        FoundationModels.shared.isEnabled = originalFMEnabled
                        FoundationModels.shared.selectedModel = originalFM
                    }

                    let resultText = try await FoundationModels.shared.generatePrivateResponse(prompt: userPrompt)
                    response = LLMResponse(
                        modelName: candidateModel,
                        completionText: resultText,
                        tokenUsage: nil,
                        latency: 1.0
                    )
                } else {
                    response = try await LLMService.shared.sendChatRequest(
                        model: candidateModel,
                        messages: messages,
                        providerOverride: resolvedProvider
                    )
                }

                let reviewText = response.completionText.trimmingCharacters(in: .whitespacesAndNewlines)

                // Robust JSON Parsing
                guard let reviewData = extractJSON(from: reviewText) else {
                    throw NSError(domain: "CodeReview", code: 400, userInfo: [NSLocalizedDescriptionKey: "Syntax Error: Reviewer returned an invalid or non-JSON formatted output."])
                }

                // Extract status to ensure contract compliance
                let status = (reviewData["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if status != "task_ready" && status != "task_failed" {
                    throw NSError(domain: "CodeReview", code: 400, userInfo: [NSLocalizedDescriptionKey: "Contract Error: Reviewer returned invalid status '\(status)'."])
                }

                // Update global code review manager state
                await updateReviewState(reviewData: reviewData)

                let output = "Review completed via \(candidateModel). Status: \(status). Summary: \(reviewData["summary"] as? String ?? "")"
                let serializedData = reviewData.mapValues { "\($0)" }
                finalResult = .success(output, data: serializedData)
                break // Succeeded! Stop trying fallbacks!

            } catch {
                await context.logger.warning("Code review attempt with \(candidateModel) failed: \(error.localizedDescription). Trying next compatible model...", toolId: id)
            }
        }

        if let result = finalResult {
            return result
        } else {
            return .failure("All available/compatible AI models failed to complete the Code Review request.")
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
