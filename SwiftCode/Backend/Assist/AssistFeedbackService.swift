//
//  AssistFeedbackService.swift
//  SwiftCode
//
//  Created on 2026-10-18.
//

import Foundation
import AppKit
import os

/// Dedicated diagnostic service that collects and compiles rich telemetry, execution logs,
/// fine-tuning records, system asset audits, and session data into an organized "Feedback Info"
/// directory with separate JSON files whenever a user reports dissatisfaction with an Assist response.
@MainActor
public final class AssistFeedbackService: ObservableObject {
    public static let shared = AssistFeedbackService()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistFeedbackService")
    private let fileManager = FileManager.default

    @Published public var isGenerating: Bool = false
    @Published public var lastGeneratedURL: URL? = nil
    @Published public var lastErrorMessage: String? = nil

    private init() {}

    /// Canonical Feedback Info root directory located where conversation files are persisted.
    public var feedbackInfoRootDirectory: URL {
        let base = AssistConversationHistory.shared.baseDirectoryURL
        let dir = base.appendingPathComponent("Feedback Info", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Generates a comprehensive debugging and model fine-tuning package containing separated JSON files.
    /// - Parameters:
    ///   - message: The specific AssistMessage the user clicked Feedback on (or nil for general feedback).
    ///   - reason: Optional user-provided reason or notes.
    /// - Returns: The URL to the newly created feedback package folder.
    public func generateFeedbackPackage(
        for message: AssistMessage? = nil,
        reason: String? = nil
    ) async throws -> URL {
        isGenerating = true
        lastErrorMessage = nil
        defer { isGenerating = false }

        logger.info("Starting Feedback Info diagnostic package generation...")

        // Brief smooth loading delay so user sees visual progress
        try? await Task.sleep(nanoseconds: 350_000_000)

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let dateString = timestampFormatter.string(from: Date())
        let folderName = "Feedback-\(dateString)-\(UUID().uuidString.prefix(6))"
        let packageURL = feedbackInfoRootDirectory.appendingPathComponent(folderName, isDirectory: true)

        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let messages = AssistManager.shared.messages
        let activeConvId = AssistConversationHistory.shared.activeConversationID ?? UUID()

        var generatedFiles: [String] = []

        func saveAndRecord(_ object: Any, filename: String) throws {
            try saveJSON(object, to: packageURL.appendingPathComponent(filename))
            generatedFiles.append(filename)
        }

        // 1. codebase_info.json
        try saveAndRecord(collectCodebaseInfo(), filename: "codebase_info.json")

        // 2. user_requests.json
        try saveAndRecord(collectUserRequests(from: messages), filename: "user_requests.json")

        // 3. full_transcription.json
        try saveAndRecord(collectFullTranscription(from: messages), filename: "full_transcription.json")

        // 4. tool_calls.json
        try saveAndRecord(collectToolCalls(from: messages), filename: "tool_calls.json")

        // 5. tool_metrics.json
        try saveAndRecord(collectToolMetrics(from: messages), filename: "tool_metrics.json")

        // 6. assist_settings.json
        try saveAndRecord(collectSettingsInfo(), filename: "assist_settings.json")

        // 7. model_telemetry.json
        try saveAndRecord(collectModelTelemetry(from: messages), filename: "model_telemetry.json")

        // 8. system_environment.json
        try saveAndRecord(collectSystemEnvironment(), filename: "system_environment.json")

        // 9. error_diagnostics.json
        try saveAndRecord(collectErrorDiagnostics(from: messages), filename: "error_diagnostics.json")

        // 10. conversation_metadata.json
        try saveAndRecord(collectConversationMetadata(messages: messages, activeConvId: activeConvId, message: message), filename: "conversation_metadata.json")

        // 11. feedback_metadata.json
        try saveAndRecord(collectFeedbackMetadata(message: message, reason: reason), filename: "feedback_metadata.json")

        // 12. fine_tuning_pairs.json (RLHF/SFT training-ready conversational dataset)
        try saveAndRecord(collectFineTuningPairs(messages: messages, flaggedMessage: message, reason: reason), filename: "fine_tuning_pairs.json")

        // 13. dpo_preference_dataset.json (Direct Preference Optimization dataset with rejected responses)
        try saveAndRecord(collectDPOPreferenceDataset(messages: messages, flaggedMessage: message, reason: reason), filename: "dpo_preference_dataset.json")

        // 14. negative_feedback_analysis.json (Deep failure taxonomy & root cause classification)
        try saveAndRecord(collectNegativeFeedbackAnalysis(flaggedMessage: message, reason: reason), filename: "negative_feedback_analysis.json")

        // 15. active_skills.json
        try saveAndRecord(collectActiveSkills(), filename: "active_skills.json")

        // 16. developer_memory.json
        try saveAndRecord(collectDeveloperMemory(), filename: "developer_memory.json")

        // 17. tasks_execution_plan.json
        try saveAndRecord(collectTasksExecutionPlan(), filename: "tasks_execution_plan.json")

        // 18. phase_coordinator_state.json (All 55+ standard engineering phases and runtime state)
        try saveAndRecord(collectPhaseCoordinatorState(), filename: "phase_coordinator_state.json")

        // 19. agent_context_state.json (Model context window, compaction, tokens, pressure)
        try saveAndRecord(collectAgentContextState(), filename: "agent_context_state.json")

        // 20. system_assets_manifest.json (All 24 bundled System Asset instruction files)
        try saveAndRecord(collectSystemAssetsManifest(), filename: "system_assets_manifest.json")

        // 21. system_assets_retrieval_ledger.json (SystemIndex retrieval ledger & status)
        try saveAndRecord(await collectSystemAssetsRetrievalLedger(), filename: "system_assets_retrieval_ledger.json")

        // 22. system_assets_coverage_audit.json (Audit of System Assets coverage and fine-tuning recommendations)
        try saveAndRecord(collectSystemAssetsCoverageAudit(messages: messages), filename: "system_assets_coverage_audit.json")

        // 23. code_editor_context.json
        try saveAndRecord(collectCodeEditorContext(), filename: "code_editor_context.json")

        // 24. runtime_performance_metrics.json (Execution latencies, thinking durations, averages)
        try saveAndRecord(collectPerformanceMetrics(from: messages), filename: "runtime_performance_metrics.json")

        // 25. framework_diagnostics.json (Autonomous decision engine, takeover session, goal graph)
        try saveAndRecord(collectFrameworkDiagnostics(), filename: "framework_diagnostics.json")

        // 26. api_endpoint_telemetry.json (Routing paths, backend models, failovers, quarantines)
        try saveAndRecord(collectApiEndpointTelemetry(), filename: "api_endpoint_telemetry.json")

        // 27. diagnostic_events_log.json (Full chronological DiagnosticEventBus event stream)
        try saveAndRecord(collectDiagnosticEvents(), filename: "diagnostic_events_log.json")

        // 28. alternative_keys_state.json (Alternative credential rotation status & cooldowns)
        try saveAndRecord(collectAlternativeKeysState(), filename: "alternative_keys_state.json")

        // 29. terminal_execution_telemetry.json (Approval settings, policy, execution logs, exit codes)
        try saveAndRecord(collectTerminalTelemetry(), filename: "terminal_execution_telemetry.json")

        // 30. prompt_enhancement_telemetry.json (Apple Foundation Models prompt rewrite telemetry)
        try saveAndRecord(collectPromptEnhancementTelemetry(messages: messages), filename: "prompt_enhancement_telemetry.json")

        // 31. user_intent_classification.json (Intent classification & profile breakdown)
        try saveAndRecord(collectUserIntentClassification(messages: messages), filename: "user_intent_classification.json")

        // 32. tool_routing_policy_eval.json (Tool routing compliance audit against ToolRoutingPolicy.md)
        try saveAndRecord(collectToolRoutingPolicyEval(messages: messages), filename: "tool_routing_policy_eval.json")

        // 33. git_state_snapshot.json (Real-time git status, branch, remotes)
        try saveAndRecord(collectGitStateSnapshot(), filename: "git_state_snapshot.json")

        // 34. repository_instructions.json (Discovered root and nested AGENTS.md instructions)
        try saveAndRecord(collectRepositoryInstructions(), filename: "repository_instructions.json")

        // 35. conversation_memory_graph.json (Multi-turn memory records, inspected & modified files)
        try saveAndRecord(collectConversationMemoryGraph(), filename: "conversation_memory_graph.json")

        // 36. verification_pipeline_diagnostics.json (Syntax checks, placeholders, conflict markers)
        try saveAndRecord(collectVerificationPipelineDiagnostics(), filename: "verification_pipeline_diagnostics.json")

        // 37. feedback_index.json (Package manifest index listing all generated telemetry files)
        try saveAndRecord(collectFeedbackIndex(fileNames: generatedFiles, folderName: folderName), filename: "feedback_index.json")

        self.lastGeneratedURL = packageURL
        logger.info("Successfully generated Feedback Info package at: \(packageURL.path) with \(generatedFiles.count) JSON telemetry files.")
        return packageURL
    }

    /// Opens the specified folder or file in macOS Finder.
    public func openInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Private JSON Persistence Helper

    private func saveJSON(_ object: Any, to fileURL: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Data Collectors

    private func collectCodebaseInfo() -> [String: Any] {
        let session = ProjectSessionStore.shared
        let openTabs = session.openFileTabs.map { ["name": $0.name, "path": $0.path] }
        let modifiedFiles = Array(session.modifiedFilePaths)
        let workspaceRoot = session.activeProject?.directoryURL ?? AssistContextBuilder.resolvedWorkspaceRoot()

        var hasPackageSwift = false
        var hasXcodeproj = false
        if let contents = try? fileManager.contentsOfDirectory(atPath: workspaceRoot.path) {
            hasPackageSwift = contents.contains("Package.swift")
            hasXcodeproj = contents.contains { $0.hasSuffix(".xcodeproj") }
        }

        return [
            "projectName": session.activeProject?.name ?? "No Project Open",
            "workspaceRootPath": workspaceRoot.path,
            "activeFilePath": session.activeFileNode?.path ?? "N/A",
            "activeFileName": session.activeFileNode?.name ?? "N/A",
            "activeFileContentLength": session.activeFileContent.count,
            "gitRepo": session.activeProject?.githubRepo ?? "none",
            "hasPackageSwift": hasPackageSwift,
            "hasXcodeProject": hasXcodeproj,
            "openFileTabsCount": openTabs.count,
            "openFileTabs": openTabs,
            "modifiedFilesCount": modifiedFiles.count,
            "modifiedFiles": modifiedFiles
        ]
    }

    private func collectUserRequests(from messages: [AssistMessage]) -> [[String: Any]] {
        messages.filter { $0.role == .user }.map { msg in
            let content = msg.content
            let codeBlocks = max(0, (content.components(separatedBy: "```").count - 1) / 2)
            return [
                "id": msg.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: msg.timestamp),
                "content": content,
                "characterCount": content.count,
                "wordCount": content.split(separator: " ").count,
                "attachmentsCount": msg.attachments?.count ?? 0,
                "envelope": msg.envelope?.slashCommand ?? "none",
                "hasCodeBlock": codeBlocks > 0,
                "codeBlockCount": codeBlocks,
                "hasQuestionMark": content.contains("?")
            ]
        }
    }

    private func collectFullTranscription(from messages: [AssistMessage]) -> [[String: Any]] {
        messages.map { msg -> [String: Any] in
            var dict: [String: Any] = [
                "id": msg.id.uuidString,
                "role": msg.role.rawValue,
                "timestamp": ISO8601DateFormatter().string(from: msg.timestamp),
                "content": msg.content,
                "hasActivity": msg.activityGroup?.hasContent ?? false,
                "toolCount": msg.activityGroup?.tools.count ?? 0,
                "hasThinking": msg.thinkingContent != nil,
                "thinkingContent": msg.thinkingContent ?? "",
                "thinkingDuration": msg.thinkingDuration ?? 0,
                "noticeLevel": msg.noticeLevel?.rawValue ?? "none"
            ]
            if let serverErr = msg.serverError {
                dict["serverErrorEndpoint"] = serverErr.endpoint
                dict["serverErrorStatus"] = serverErr.statusCode
                dict["serverErrorRaw"] = serverErr.rawBody
            }
            if let atts = msg.attachments, !atts.isEmpty {
                dict["attachments"] = atts.map { ["name": $0.filename, "size": $0.size] }
            }
            return dict
        }
    }

    private func collectToolCalls(from messages: [AssistMessage]) -> [[String: Any]] {
        var allTools: [[String: Any]] = []
        var sequence = 1
        for msg in messages {
            if let group = msg.activityGroup {
                for tool in group.tools {
                    allTools.append([
                        "sequenceIndex": sequence,
                        "toolId": tool.toolId,
                        "purpose": tool.purpose,
                        "status": tool.status.rawValue,
                        "durationSeconds": tool.duration,
                        "resultPreview": String(tool.result.prefix(500)),
                        "resultLength": tool.result.count,
                        "timestamp": ISO8601DateFormatter().string(from: tool.timestamp),
                        "messageId": msg.id.uuidString
                    ])
                    sequence += 1
                }
            }
        }
        return allTools
    }

    private func collectToolMetrics(from messages: [AssistMessage]) -> [String: Any] {
        let allHealth = AssistToolRegistry.shared.allHealth.map { health -> [String: Any] in
            [
                "toolId": health.toolId,
                "status": health.status.rawValue,
                "useCount": health.useCount,
                "lastUsedAt": health.lastUsedAt != nil ? ISO8601DateFormatter().string(from: health.lastUsedAt!) : "never",
                "lastError": health.lastError ?? "none"
            ]
        }

        var frequencyMap: [String: Int] = [:]
        var durationMap: [String: Double] = [:]
        var failureMap: [String: Int] = [:]

        for msg in messages {
            if let tools = msg.activityGroup?.tools {
                for t in tools {
                    frequencyMap[t.toolId, default: 0] += 1
                    durationMap[t.toolId, default: 0.0] += t.duration
                    if t.status == .failed {
                        failureMap[t.toolId, default: 0] += 1
                    }
                }
            }
        }

        var executionBreakdown: [[String: Any]] = []
        for (toolId, count) in frequencyMap {
            let totalDur = durationMap[toolId] ?? 0.0
            let avgDur = count > 0 ? (totalDur / Double(count)) : 0.0
            let fails = failureMap[toolId] ?? 0
            executionBreakdown.append([
                "toolId": toolId,
                "invocationCount": count,
                "failureCount": fails,
                "failureRate": count > 0 ? Double(fails) / Double(count) : 0.0,
                "totalDurationSeconds": totalDur,
                "averageDurationSeconds": avgDur
            ])
        }

        return [
            "registeredToolsCount": allHealth.count,
            "sessionTotalToolInvocations": frequencyMap.values.reduce(0, +),
            "totalFailedToolInvocations": failureMap.values.reduce(0, +),
            "toolExecutionBreakdown": executionBreakdown,
            "toolHealthStatuses": allHealth,
            "capabilities": AssistToolRegistry.shared.compactCapabilityRepresentation
        ]
    }

    private func collectSettingsInfo() -> [String: Any] {
        let s = AppSettings.shared
        return [
            "assistSystemID": s.assistSystemID,
            "assistToolkit": s.assistToolkit,
            "isMetaAssist": s.isMetaAssist,
            "isGoogleCloudAssist": s.isGoogleCloudAssist,
            "metaAssistModelID": s.metaAssistModelID,
            "metaReasoningEffort": s.metaReasoningEffort,
            "otherModelsWithMetaSDK": s.otherModelsWithMetaSDK,
            "swiftCodeCloudWithMetaSDK": s.swiftCodeCloudWithMetaSDK,
            "selectedAssistModelID": s.selectedAssistModelID
        ]
    }

    private func collectModelTelemetry(from messages: [AssistMessage]) -> [String: Any] {
        let s = AppSettings.shared
        let activeModel = s.isMetaAssist ? s.metaAssistModelID : s.assistSystemID
        let spec = AgentModelAdapter.shared.specification(for: activeModel)
        return [
            "providerID": s.assistSystemID,
            "activeModelID": activeModel,
            "modelDisplayName": spec.displayName,
            "reasoningEffort": s.metaReasoningEffort,
            "contextWindowTokens": spec.contextWindowTokens,
            "capabilitiesRawValue": spec.capabilities.rawValue,
            "foundationModels": [
                "isEnabled": FoundationModels.shared.isEnabled,
                "selectedModel": FoundationModels.shared.selectedModel.rawValue
            ],
            "messageTurnCount": messages.count,
            "assistantResponsesCount": messages.filter { $0.role == .assistant }.count,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
    }

    private func collectSystemEnvironment() -> [String: Any] {
        let process = ProcessInfo.processInfo
        let thermalString: String
        switch process.thermalState {
        case .nominal: thermalString = "nominal"
        case .fair: thermalString = "fair"
        case .serious: thermalString = "serious"
        case .critical: thermalString = "critical"
        @unknown default: thermalString = "unknown"
        }

        return [
            "osVersion": process.operatingSystemVersionString,
            "physicalMemoryBytes": process.physicalMemory,
            "physicalMemoryFormatted": ByteCountFormatter.string(fromByteCount: Int64(process.physicalMemory), countStyle: .memory),
            "processorCount": process.processorCount,
            "activeProcessorCount": process.activeProcessorCount,
            "systemUptimeSeconds": process.systemUptime,
            "hostName": process.hostName,
            "thermalState": thermalString,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "appBuild": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "com.swiftcode.app"
        ]
    }

    private func collectErrorDiagnostics(from messages: [AssistMessage]) -> [String: Any] {
        let manager = AssistManager.shared
        let serverErrors = messages.compactMap { msg -> [String: Any]? in
            guard let err = msg.serverError else { return nil }
            return [
                "messageId": msg.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: msg.timestamp),
                "endpoint": err.endpoint,
                "statusCode": err.statusCode,
                "rawBody": err.rawBody
            ]
        }

        let noticeErrors = messages.filter { $0.noticeLevel == .error }.map { msg in
            [
                "messageId": msg.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: msg.timestamp),
                "content": msg.content
            ]
        }

        var failedTools: [[String: Any]] = []
        for msg in messages {
            if let tools = msg.activityGroup?.tools {
                for t in tools where t.status == .failed {
                    failedTools.append([
                        "toolId": t.toolId,
                        "purpose": t.purpose,
                        "result": t.result,
                        "duration": t.duration,
                        "messageId": msg.id.uuidString
                    ])
                }
            }
        }

        return [
            "lastError": manager.lastError ?? "none",
            "lastErrorPhase": manager.lastErrorPhase ?? "none",
            "lastErrorDate": manager.lastErrorDate != nil ? ISO8601DateFormatter().string(from: manager.lastErrorDate!) : "none",
            "lastWarning": manager.lastWarning ?? "none",
            "totalServerErrors": serverErrors.count,
            "serverErrors": serverErrors,
            "totalNoticeErrors": noticeErrors.count,
            "noticeErrors": noticeErrors,
            "totalFailedTools": failedTools.count,
            "failedTools": failedTools
        ]
    }

    private func collectConversationMetadata(messages: [AssistMessage], activeConvId: UUID, message: AssistMessage?) -> [String: Any] {
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        let assistantCount = messages.filter { $0.role == .assistant }.count
        return [
            "conversationId": activeConvId.uuidString,
            "totalMessages": messages.count,
            "userMessages": messages.filter { $0.role == .user }.count,
            "assistantMessages": assistantCount,
            "systemMessages": messages.filter { $0.role == .system }.count,
            "totalCharacters": totalChars,
            "averageAssistantLength": assistantCount > 0 ? (totalChars / assistantCount) : 0,
            "createdDate": ISO8601DateFormatter().string(from: messages.first?.timestamp ?? Date()),
            "lastMessageDate": ISO8601DateFormatter().string(from: messages.last?.timestamp ?? Date()),
            "feedbackTargetMessageId": message?.id.uuidString ?? "none"
        ]
    }

    private func collectFeedbackMetadata(message: AssistMessage?, reason: String?) -> [String: Any] {
        [
            "feedbackId": UUID().uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "targetedMessageId": message?.id.uuidString ?? "none",
            "targetedMessagePreview": String(message?.content.prefix(300) ?? ""),
            "userReason": reason ?? "User clicked Feedback on Assist response",
            "status": "dissatisfied_response_flagged",
            "suggestedAction": "Inspect response against system instructions and consider System Assets prompt refinement or fine-tuning adjustment"
        ]
    }

    private func collectFineTuningPairs(messages: [AssistMessage], flaggedMessage: AssistMessage?, reason: String?) -> [[String: Any]] {
        var pairs: [[String: Any]] = []

        // If a specific message was flagged, match it with preceding user turn
        if let target = flaggedMessage, let targetIndex = messages.firstIndex(where: { $0.id == target.id }) {
            let precedingUser = messages[..<targetIndex].last(where: { $0.role == .user })
            pairs.append([
                "pairId": UUID().uuidString,
                "type": "flagged_negative_example",
                "model_identity": "Assist",
                "user_prompt": precedingUser?.content ?? "",
                "model_output": target.content,
                "model_thinking": target.thinkingContent ?? "",
                "feedback_reason": reason ?? "User flagged as unsatisfactory",
                "tools_used": target.activityGroup?.tools.map { $0.toolId } ?? [],
                "target_project": ProjectSessionStore.shared.activeProject?.name ?? "Unknown",
                "active_file": ProjectSessionStore.shared.activeFileNode?.name ?? "Unknown"
            ])
        }

        // Also compile all user/assistant dialogue turns for training corpus context
        for i in 0..<messages.count {
            let msg = messages[i]
            if msg.role == .user && i + 1 < messages.count {
                let nextMsg = messages[i + 1]
                if nextMsg.role == .assistant && !nextMsg.content.isEmpty {
                    pairs.append([
                        "pairId": UUID().uuidString,
                        "type": nextMsg.id == flaggedMessage?.id ? "flagged_turn" : "conversational_turn",
                        "model_identity": "Assist",
                        "user_prompt": msg.content,
                        "assistant_response": nextMsg.content,
                        "tools_invoked": nextMsg.activityGroup?.tools.map { $0.toolId } ?? []
                    ])
                }
            }
        }

        return pairs
    }

    private func collectDPOPreferenceDataset(messages: [AssistMessage], flaggedMessage: AssistMessage?, reason: String?) -> [[String: Any]] {
        guard let target = flaggedMessage, let targetIndex = messages.firstIndex(where: { $0.id == target.id }) else {
            return []
        }
        let precedingUser = messages[..<targetIndex].last(where: { $0.role == .user })
        return [
            [
                "dpo_pair_id": UUID().uuidString,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "model_identity": "Assist by SwiftCode",
                "prompt": precedingUser?.content ?? "",
                "rejected": target.content,
                "rejected_thinking": target.thinkingContent ?? "",
                "chosen": NSNull(),
                "critique": reason ?? "User clicked Feedback: Unsatisfactory response",
                "failure_flags": [
                    "has_thinking": target.thinkingContent != nil,
                    "has_failed_tools": (target.activityGroup?.tools.contains(where: { $0.status == .failed }) ?? false),
                    "has_server_error": target.serverError != nil
                ],
                "executed_tools": target.activityGroup?.tools.map { $0.toolId } ?? [],
                "system_asset_reference": "AgentSystemAsset.md, Safeguards.md, ToolRoutingPolicy.md"
            ]
        ]
    }

    private func collectNegativeFeedbackAnalysis(flaggedMessage: AssistMessage?, reason: String?) -> [String: Any] {
        guard let target = flaggedMessage else {
            return [
                "analysisStatus": "no_specific_message_targeted",
                "summary": "General session feedback submitted"
            ]
        }

        let content = target.content
        let lower = content.lowercased()
        let hasApology = lower.contains("sorry") || lower.contains("apologize") || lower.contains("unfortunately")
        let hasIncompleteSnippet = content.contains("// TODO") || content.contains("rest of code unchanged") || content.contains("// ...")
        let hasExecutionFailure = target.activityGroup?.tools.contains(where: { $0.status == .failed }) ?? false
        let hasServerError = target.serverError != nil

        let predictedCategory: String
        let recommendedRefinement: String
        if hasServerError {
            predictedCategory = "Backend Server Error"
            recommendedRefinement = "Check backend API routing and network failover in AssistModelRouter.swift."
        } else if hasExecutionFailure {
            predictedCategory = "Tool Execution Failure"
            recommendedRefinement = "Inspect parameters passed to tool and review ToolRoutingPolicy.md."
        } else if hasIncompleteSnippet {
            predictedCategory = "Incomplete Code / Truncation"
            recommendedRefinement = "Strengthen Safeguards.md and FileOperations.md against omitting code or inserting placeholders."
        } else if hasApology {
            predictedCategory = "Model Apology / Refusal"
            recommendedRefinement = "Reinforce Identity.md and SwiftUsage.md so Assist directly executes code instead of apologizing."
        } else {
            predictedCategory = "Semantic Quality / Logic Dissatisfaction"
            recommendedRefinement = "Consider fine-tuning pair addition and updating domain-specific System Assets (e.g. SwiftUsage.md or BuildAndTesting.md)."
        }

        return [
            "flaggedMessageId": target.id.uuidString,
            "contentLength": content.count,
            "hasApology": hasApology,
            "hasIncompleteSnippet": hasIncompleteSnippet,
            "hasExecutionFailure": hasExecutionFailure,
            "hasServerError": hasServerError,
            "predictedCategory": predictedCategory,
            "userProvidedReason": reason ?? "None provided",
            "recommendedRefinement": recommendedRefinement
        ]
    }

    private func collectActiveSkills() -> [[String: Any]] {
        SkillIndex.shared.skills.map { skill in
            [
                "id": skill.id,
                "name": skill.name,
                "description": skill.description,
                "sourceKind": skill.sourceKind.rawValue,
                "isEnabled": skill.isEnabled,
                "path": skill.path
            ]
        }
    }

    private func collectDeveloperMemory() -> [[String: Any]] {
        UserMemoryManager.shared.entries.map { entry in
            [
                "key": entry.key,
                "value": entry.value,
                "category": entry.category,
                "updatedAt": ISO8601DateFormatter().string(from: entry.updatedAt)
            ]
        }
    }

    private func collectTasksExecutionPlan() -> [String: Any] {
        let planner = TasksAIPlanner.shared
        let planDict: [String: Any]?
        if let plan = planner.currentPlan {
            let steps = plan.steps.map { step in
                [
                    "id": step.id.uuidString,
                    "toolId": step.toolId,
                    "description": step.description,
                    "status": step.status.rawValue,
                    "input": step.input
                ]
            }
            planDict = [
                "id": plan.id.uuidString,
                "goal": plan.goal,
                "status": plan.status.rawValue,
                "stepCount": plan.steps.count,
                "steps": steps
            ]
        } else {
            planDict = nil
        }

        return [
            "hasActivePlan": planDict != nil,
            "currentPlan": planDict ?? ["status": "no_active_plan"],
            "notesMarkdown": AgentNotesManager.shared.currentNotesMarkdown
        ]
    }

    private func collectPhaseCoordinatorState() -> [String: Any] {
        let coordinator = AgentPhaseCoordinator.shared
        let allPhases = coordinator.phases.map { phase -> [String: Any] in
            [
                "phaseId": phase.phaseId,
                "name": phase.name,
                "description": phase.description,
                "status": phase.status.rawValue,
                "startedAt": phase.startedAt != nil ? ISO8601DateFormatter().string(from: phase.startedAt!) : "none",
                "completedAt": phase.completedAt != nil ? ISO8601DateFormatter().string(from: phase.completedAt!) : "none",
                "durationSeconds": phase.duration ?? 0,
                "dependencies": phase.dependencies,
                "evidence": phase.evidence ?? "none",
                "failures": phase.failures,
                "recoveryNotes": phase.recoveryNotes ?? "none"
            ]
        }
        return [
            "totalPhasesCount": coordinator.phases.count,
            "activePhaseId": coordinator.activePhaseId ?? "none",
            "activePhaseName": coordinator.activePhase?.name ?? "none",
            "completedPhasesCount": coordinator.completedPhases.count,
            "remainingPhasesCount": coordinator.remainingPhases.count,
            "phases": allPhases
        ]
    }

    private func collectAgentContextState() -> [String: Any] {
        let manager = AssistManager.shared
        let sections = manager.modelContext.map { s in
            [
                "title": s.title,
                "estimatedTokens": s.estimatedTokens,
                "contentLength": s.content.count,
                "isFixed": s.isFixed
            ]
        }
        return [
            "contextSectionsCount": sections.count,
            "contextSections": sections,
            "contextPressure": [
                "capacity": manager.contextPressure?.capacity ?? 128_000,
                "estimatedUsage": manager.contextPressure?.estimatedUsage ?? 0,
                "safetyMargin": manager.contextPressure?.safetyMargin ?? 2048,
                "compactionStatus": "\(manager.contextPressure?.compactionStatus ?? .none)",
                "summaryDepth": manager.contextPressure?.summaryDepth ?? 0
            ],
            "requestPhase": manager.requestPhase.statusText
        ]
    }

    private func collectSystemAssetsManifest() -> [[String: Any]] {
        let manifestNames = [
            "Identity.md", "Safeguards.md", "AvailableTools.md", "FileOperations.md",
            "ToolRoutingPolicy.md", "ModelProviders.md", "AgentSystemAsset.md", "AgenticLoop.md",
            "Authentication.md", "BuildAndTesting.md", "CallTool.md", "CodeReviewSystemAsset.md",
            "ContextBudgeting.md", "Contexts.md", "CreatingAppAsset.md", "ErrorHandling.md",
            "ExecutionPlans.md", "ProjectContext.md", "ResponseFormatting.md", "Skills.md",
            "Streaming.md", "SwiftUsage.md", "SystemIndex.md", "TaskCompletion.md"
        ]
        let bundleURL = SystemIndexService.shared.bundledAssetsURL()
        return manifestNames.map { name in
            let fileURL = bundleURL?.appendingPathComponent(name)
            let exists = fileURL != nil && fileManager.fileExists(atPath: fileURL!.path)
            let size = (try? fileManager.attributesOfItem(atPath: fileURL?.path ?? "")[.size] as? Int) ?? 0
            return [
                "filename": name,
                "role": "System Asset Markdown Prompt Module",
                "existsInBundle": exists,
                "byteSize": size,
                "tokenEstimate": (size + 3) / 4,
                "isBaseline": SystemIndexService.baselineDocumentNames.contains(name),
                "isExpected": SystemIndexService.expectedDocumentNames.contains(name)
            ]
        }
    }

    private func collectSystemAssetsRetrievalLedger() async -> [String: Any] {
        let ledger = AssistManager.shared.activeRetrievalLedger
        let chunkIDs = Array(ledger?.retrievedChunkIDs ?? [])
        let readiness = await SystemIndexService.shared.status()
        let readinessStr: String
        switch readiness {
        case .ready(let docs, let chunks): readinessStr = "ready (\(docs) documents, \(chunks) chunks)"
        case .indexing: readinessStr = "indexing"
        case .notStarted: readinessStr = "notStarted"
        case .failed(let err): readinessStr = "failed: \(err)"
        }

        return [
            "retrievalRounds": ledger?.retrievalRounds ?? 0,
            "retrievedChunkIDsCount": chunkIDs.count,
            "retrievedChunkIDs": chunkIDs,
            "systemIndexReadiness": readinessStr,
            "totalIndexedDocuments": await SystemIndexService.shared.documentCount(),
            "totalIndexedChunks": await SystemIndexService.shared.chunkCount(),
            "diagnosticsNotes": await SystemIndexService.shared.lastDiagnostics()
        ]
    }

    private func collectSystemAssetsCoverageAudit(messages: [AssistMessage]) -> [String: Any] {
        let userTexts = messages.filter { $0.role == .user }.map { $0.content.lowercased() }.joined(separator: " ")
        let executedTools = messages.flatMap { $0.activityGroup?.tools.map { $0.toolId } ?? [] }

        var topicCoverage: [[String: Any]] = []

        let topics: [(asset: String, keywords: [String])] = [
            ("FileOperations.md", ["file", "directory", "read", "write", "folder", "replace", "edit", "path"]),
            ("SwiftUsage.md", ["swift", "swiftui", "actor", "sendable", "concurrency", "mainactor", "struct", "class"]),
            ("ToolRoutingPolicy.md", ["tool", "run", "execute", "terminal", "command", "build"]),
            ("BuildAndTesting.md", ["build", "test", "xcodebuild", "compiler", "error", "warning", "scheme"]),
            ("Safeguards.md", ["delete", "remove", "secret", "token", "password", "key", "safe"])
        ]

        for topic in topics {
            let matched = topic.keywords.filter { userTexts.contains($0) }
            topicCoverage.append([
                "asset": topic.asset,
                "relevantKeywordsFound": matched,
                "relevanceScore": Double(matched.count) / Double(topic.keywords.count),
                "triggered": !matched.isEmpty
            ])
        }

        return [
            "userPromptsEvaluated": messages.filter { $0.role == .user }.count,
            "toolsExecutedInSession": executedTools,
            "topicCoverage": topicCoverage,
            "recommendedAssetFocus": "Update ToolRoutingPolicy.md and FileOperations.md with specific edge-case routing rules to prevent user dissatisfaction"
        ]
    }

    private func collectCodeEditorContext() -> [String: Any] {
        let session = ProjectSessionStore.shared
        let activeContent = session.activeFileContent
        let linesCount = activeContent.components(separatedBy: .newlines).count

        return [
            "activeFileName": session.activeFileNode?.name ?? "None",
            "activeFilePath": session.activeFileNode?.path ?? "None",
            "activeFileLinesCount": linesCount,
            "activeFileSize": activeContent.count,
            "openTabsCount": session.openFileTabs.count,
            "openTabs": session.openFileTabs.map { ["name": $0.name, "path": $0.path] },
            "contentPreview": String(activeContent.prefix(500))
        ]
    }

    private func collectPerformanceMetrics(from messages: [AssistMessage]) -> [String: Any] {
        var totalToolDuration: Double = 0.0
        var totalToolsExecuted: Int = 0
        var totalThinkingDuration: TimeInterval = 0.0
        var thinkingCount: Int = 0

        for msg in messages {
            if let tools = msg.activityGroup?.tools {
                totalToolsExecuted += tools.count
                for t in tools {
                    totalToolDuration += t.duration
                }
            }
            if let dur = msg.thinkingDuration {
                totalThinkingDuration += dur
                thinkingCount += 1
            }
        }

        return [
            "totalToolsExecuted": totalToolsExecuted,
            "totalToolExecutionDurationSeconds": totalToolDuration,
            "averageToolDurationSeconds": totalToolsExecuted > 0 ? (totalToolDuration / Double(totalToolsExecuted)) : 0.0,
            "thinkingTurnsCount": thinkingCount,
            "totalThinkingDurationSeconds": totalThinkingDuration,
            "averageThinkingDurationSeconds": thinkingCount > 0 ? (totalThinkingDuration / Double(thinkingCount)) : 0.0
        ]
    }

    private func collectFrameworkDiagnostics() -> [String: Any] {
        let session = AssistTakeoverSessionState.shared
        let goalGraph = session.goalGraph
        let storedContextData = UserDefaults.standard.data(forKey: "com.swiftcode.assist.persistentContext")

        return [
            "takeoverEnabled": UserDefaults.standard.bool(forKey: "assist.takeoverEnabled"),
            "consecutiveFailures": session.consecutiveFailures,
            "goalGraph": [
                "rootGoal": goalGraph.rootGoal,
                "totalGoals": goalGraph.totalGoalCount,
                "pendingGoalsCount": goalGraph.pendingGoals.count,
                "completedGoalsCount": goalGraph.completedGoals.count,
                "rejectedGoalsCount": goalGraph.rejectedGoals.count,
                "maxDepth": goalGraph.maxDepth
            ],
            "hasPersistentContext": storedContextData != nil,
            "persistentContextByteSize": storedContextData?.count ?? 0
        ]
    }

    private func collectApiEndpointTelemetry() -> [String: Any] {
        let router = AssistModelRouter.shared
        let settings = AppSettings.shared
        var failoverHistory: [[String: Any]] = []
        for f in router.failoverHistory {
            failoverHistory.append([
                "failedModel": f.failedModelID,
                "failedProvider": f.failedProviderID,
                "newModel": f.newModelID,
                "newProvider": f.newProviderID,
                "failureClass": f.failureClass.rawValue,
                "reason": f.reason,
                "timestamp": ISO8601DateFormatter().string(from: f.timestamp)
            ])
        }

        var quarantined: [[String: Any]] = []
        for (model, unquar) in router.quarantinedModels {
            quarantined.append([
                "modelID": model,
                "unquarantineAt": ISO8601DateFormatter().string(from: unquar)
            ])
        }

        return [
            "selectedModelID": settings.selectedAssistModelID,
            "assistSystemID": settings.assistSystemID,
            "isMetaAssist": settings.isMetaAssist,
            "isGoogleCloudAssist": settings.isGoogleCloudAssist,
            "swiftCodeCloudWithMetaSDK": settings.swiftCodeCloudWithMetaSDK,
            "currentGeneration": AssistManager.shared.currentGeneration.value,
            "quarantinedModels": quarantined,
            "failedAttemptsCount": router.failedAttemptsCount,
            "failoverHistory": failoverHistory
        ]
    }

    private func collectDiagnosticEvents() -> [[String: Any]] {
        DiagnosticEventBus.shared.events.map { e in
            [
                "id": e.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: e.timestamp),
                "component": e.component,
                "provider": e.provider,
                "model": e.model,
                "executionMode": e.executionMode,
                "severity": e.severity,
                "category": e.category,
                "message": e.message,
                "errorDescription": e.errorDescription ?? "none"
            ]
        }
    }

    private func collectAlternativeKeysState() -> [String: Any] {
        let manager = AlternativeKeyManager.shared
        let keysData = manager.keys.map { key in
            [
                "id": key.id.uuidString,
                "maskedValue": key.maskedValue,
                "state": key.state.rawValue,
                "isRateLimited": key.isCurrentlyRateLimited,
                "isAvailable": key.isAvailableForUse,
                "rateLimitedUntil": key.rateLimitedUntil != nil ? ISO8601DateFormatter().string(from: key.rateLimitedUntil!) : "none",
                "lastUsed": key.lastUsed != nil ? ISO8601DateFormatter().string(from: key.lastUsed!) : "never",
                "failureCount": key.failureCount,
                "successCount": key.successCount,
                "orderIndex": key.orderIndex
            ]
        }
        return [
            "totalKeysConfigured": manager.keys.count,
            "activeKeyId": manager.activeKeyId?.uuidString ?? "none",
            "keys": keysData
        ]
    }

    private func collectTerminalTelemetry() -> [String: Any] {
        let settings = TerminalApprovalSettings.shared
        let manager = AssistManager.shared
        return [
            "fullAccessPolicy": settings.fullAccess,
            "allowedCommands": settings.allowedCommands,
            "presetCommandsCount": TerminalApprovalSettings.presetCommands.count,
            "isTerminalRunning": manager.terminalRunning,
            "terminalExitCode": manager.terminalExitCode ?? -1,
            "terminalCompleted": manager.terminalCompleted,
            "hasPendingApproval": manager.pendingTerminalRequest != nil,
            "pendingCommand": manager.pendingTerminalRequest?.command ?? "none",
            "liveOutputSnippet": String(manager.terminalLiveOutput.suffix(400))
        ]
    }

    private func collectPromptEnhancementTelemetry(messages: [AssistMessage]) -> [String: Any] {
        let fm = FoundationModels.shared
        let userPrompts = messages.filter { $0.role == .user }.map { msg in
            [
                "id": msg.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: msg.timestamp),
                "characterCount": msg.content.count,
                "hasCodeBlock": msg.content.contains("```"),
                "hasActionVerb": msg.content.lowercased().contains("fix") || msg.content.lowercased().contains("build") || msg.content.lowercased().contains("update") || msg.content.lowercased().contains("test"),
                "content": msg.content
            ]
        }
        return [
            "foundationModelsEnabled": fm.isEnabled,
            "selectedFoundationModel": fm.selectedModel.rawValue,
            "userPromptsCount": userPrompts.count,
            "userPrompts": userPrompts
        ]
    }

    private func collectUserIntentClassification(messages: [AssistMessage]) -> [[String: Any]] {
        let classifier = AssistIntentClassifier.shared
        let activeFile = ProjectSessionStore.shared.activeFileNode?.path
        return messages.filter { $0.role == .user }.map { msg in
            let result = classifier.classify(prompt: msg.content, activeFile: activeFile)
            var explicitDict: [String: Any] = [:]
            if let exp = result.explicitTool {
                explicitDict["toolId"] = exp.toolId
                explicitDict["explanation"] = exp.explanation
            }
            return [
                "messageId": msg.id.uuidString,
                "prompt": msg.content,
                "primaryIntent": "\(result.primaryIntent)",
                "profile": result.profile.rawValue,
                "confidence": result.confidence,
                "explanation": result.explanation,
                "deterministicToolId": result.deterministicToolId ?? "none",
                "explicitTool": explicitDict
            ]
        }
    }

    private func collectToolRoutingPolicyEval(messages: [AssistMessage]) -> [String: Any] {
        var toolSequence: [String] = []
        var mutatedPaths: Set<String> = []
        var readPaths: Set<String> = []

        for msg in messages {
            if let tools = msg.activityGroup?.tools {
                for t in tools {
                    toolSequence.append(t.toolId)
                    if t.toolId == "file_read" || t.toolId == "read_file" {
                        readPaths.insert(t.purpose)
                    } else if t.toolId == "file_write" || t.toolId == "code_replace" || t.toolId == "write_file" {
                        mutatedPaths.insert(t.purpose)
                    }
                }
            }
        }

        let hasMutations = !mutatedPaths.isEmpty
        let hasVerification = toolSequence.contains { $0.contains("test") || $0.contains("build") || $0.contains("verify") || $0.contains("syntax") }

        return [
            "totalToolsInvoked": toolSequence.count,
            "distinctToolsUsed": Array(Set(toolSequence)),
            "mutatedFilesCount": mutatedPaths.count,
            "verificationRanAfterMutations": hasMutations ? hasVerification : true,
            "policyComplianceSummary": hasMutations && !hasVerification ? "Warning: File mutations occurred without subsequent build/test verification." : "Compliant with ToolRoutingPolicy guidelines.",
            "policyRecommendations": [
                "Always invoke file_read before modifying any source file",
                "Always follow file mutations with swift build or syntax verification",
                "Prefer code_replace for localized edits to prevent context bloat"
            ]
        ]
    }

    private func collectGitStateSnapshot() -> [String: Any] {
        let project = ProjectSessionStore.shared.activeProject
        let gitManager = AssistGitManager(project: project)
        let gitStatus = (try? gitManager.status()) ?? "Git status unavailable"

        return [
            "projectName": project?.name ?? "No Project Open",
            "githubRepo": project?.githubRepo ?? "none",
            "gitStatus": gitStatus
        ]
    }

    private func collectRepositoryInstructions() -> [String: Any] {
        let root = ProjectSessionStore.shared.activeProject?.directoryURL ?? AssistContextBuilder.resolvedWorkspaceRoot()
        let instructions = AgentRepositoryScanner.shared.discoverInstructions(in: root)
        let mapped = instructions.map { inst in
            [
                "id": inst.id.uuidString,
                "filePath": inst.filePath,
                "directoryPath": inst.directoryPath,
                "isRoot": inst.isRoot,
                "contentLength": inst.content.count,
                "content": inst.content
            ]
        }
        return [
            "instructionsCount": instructions.count,
            "workspaceRoot": root.path,
            "instructions": mapped
        ]
    }

    private func collectConversationMemoryGraph() -> [String: Any] {
        let memory = AssistConversationMemory.shared
        let turns = memory.turns.map { turn in
            [
                "id": turn.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: turn.timestamp),
                "userPrompt": turn.userPrompt,
                "intentSummary": turn.intentSummary,
                "executedTools": turn.executedTools,
                "filesInspected": turn.filesInspected,
                "filesModified": turn.filesModified,
                "buildOutcome": turn.buildOutcome ?? "none",
                "finalSummary": turn.finalSummary ?? "none",
                "keyDecisions": turn.keyDecisions
            ]
        }
        return [
            "totalRecordedTurns": memory.turns.count,
            "inspectedFiles": Array(memory.inspectedFiles),
            "modifiedFiles": Array(memory.modifiedFiles),
            "establishedDecisions": memory.establishedDecisions,
            "rollingSummary": memory.rollingSummary,
            "lastVerifiedBuildOutcome": memory.lastVerifiedBuildOutcome ?? "none",
            "turns": turns
        ]
    }

    private func collectVerificationPipelineDiagnostics() -> [String: Any] {
        let pipeline = AssistVerificationPipeline.shared
        let session = ProjectSessionStore.shared
        let content = session.activeFileContent

        return [
            "developerDir": pipeline.resolveDeveloperDir(),
            "activeFilePath": session.activeFileNode?.path ?? "none",
            "activeFileName": session.activeFileNode?.name ?? "none",
            "hasPlaceholders": assistContainsPlaceholderToken(content),
            "hasConflictMarkers": assistHasConflictMarkers(content)
        ]
    }

    private func collectFeedbackIndex(fileNames: [String], folderName: String) -> [String: Any] {
        [
            "package": folderName,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "totalJsonFiles": fileNames.count,
            "files": fileNames,
            "categories": [
                "codebase": ["codebase_info.json", "code_editor_context.json", "git_state_snapshot.json", "repository_instructions.json"],
                "conversation": ["user_requests.json", "full_transcription.json", "conversation_metadata.json", "conversation_memory_graph.json"],
                "tools": ["tool_calls.json", "tool_metrics.json", "tool_routing_policy_eval.json"],
                "model_and_finetuning": ["model_telemetry.json", "fine_tuning_pairs.json", "dpo_preference_dataset.json", "negative_feedback_analysis.json", "user_intent_classification.json", "prompt_enhancement_telemetry.json"],
                "frameworks_and_phases": ["framework_diagnostics.json", "phase_coordinator_state.json", "tasks_execution_plan.json", "agent_context_state.json", "active_skills.json", "developer_memory.json"],
                "system_assets": ["system_assets_manifest.json", "system_assets_retrieval_ledger.json", "system_assets_coverage_audit.json"],
                "backend_and_system": ["assist_settings.json", "api_endpoint_telemetry.json", "diagnostic_events_log.json", "alternative_keys_state.json", "terminal_execution_telemetry.json", "error_diagnostics.json", "system_environment.json", "runtime_performance_metrics.json", "verification_pipeline_diagnostics.json", "feedback_metadata.json"]
            ]
        ]
    }
}
