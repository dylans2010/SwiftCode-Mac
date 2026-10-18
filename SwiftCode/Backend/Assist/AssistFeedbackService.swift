//
//  AssistFeedbackService.swift
//  SwiftCode
//
//  Created on 2026-10-18.
//

import Foundation
import AppKit
import os

// MARK: - Assist User Action Log

/// Static, in-memory log of explicit user actions on Assist messages (copies,
/// retries, feedback votes, artifact opens). Any view can record without an
/// instance; the feedback package serializes the events into `user_actions.json`.
@MainActor
public enum AssistUserActionLog {
    public enum AssistUserAction: Sendable {
        case copied(messageID: UUID)
        case retryRequested(messageID: UUID)
        case artifactOpened(artifactID: UUID, title: String)
        case editApplied(messageID: UUID)
        case positiveFeedback(messageID: UUID)
        case negativeFeedback(messageID: UUID)
    }

    private static var recordedEvents: [(action: AssistUserAction, recordedAt: Date)] = []

    public static func record(_ action: AssistUserAction) {
        recordedEvents.append((action, Date()))
    }

    public static func events() -> [AssistUserAction] {
        recordedEvents.map { $0.action }
    }

    public static func reset() {
        recordedEvents.removeAll()
    }

    /// Timestamped events for the feedback pipeline's `user_actions.json` and
    /// retry-outcome correlation.
    static func datedEvents() -> [(action: AssistUserAction, recordedAt: Date)] {
        recordedEvents
    }
}

// MARK: - Assist Feedback Vote Log

/// Static, in-memory log of structured feedback votes: thumbs-up taps and
/// the thumbs-down sheet's category/comment/severity. Recorded at the vote
/// call sites in `AssistMainView`; the feedback package serializes the votes
/// into `feedback_votes_history.json`, and the waterfall timeline correlates
/// them with the turns they judged.
@MainActor
public enum AssistFeedbackVoteLog {
    public struct AssistFeedbackVote: Sendable {
        public let voteID: UUID
        public let messageID: UUID
        public let isPositive: Bool
        public let modelId: String?
        public let providerID: String?
        public let conversationID: UUID?
        public let reasonCategory: String?
        public let userComment: String?
        public let severity: String?
        public let recordedAt: Date
    }

    private static var votes: [AssistFeedbackVote] = []

    public static func recordPositive(
        messageID: UUID,
        modelId: String?,
        providerID: String?,
        conversationID: UUID? = nil
    ) {
        votes.append(AssistFeedbackVote(
            voteID: UUID(),
            messageID: messageID,
            isPositive: true,
            modelId: modelId,
            providerID: providerID,
            conversationID: conversationID,
            reasonCategory: nil,
            userComment: nil,
            severity: nil,
            recordedAt: Date()
        ))
    }

    public static func recordNegative(
        messageID: UUID,
        category: String,
        comment: String?,
        severity: String
    ) {
        votes.append(AssistFeedbackVote(
            voteID: UUID(),
            messageID: messageID,
            isPositive: false,
            modelId: nil,
            providerID: nil,
            conversationID: nil,
            reasonCategory: category,
            userComment: comment,
            severity: severity,
            recordedAt: Date()
        ))
    }

    public static func allVotes() -> [AssistFeedbackVote] {
        votes
    }

    public static func reset() {
        votes.removeAll()
    }
}

// MARK: - Feedback Package Mode

/// Feedback package generation mode: `.full` writes the complete diagnostic
/// set; `.quick` writes only the essential triage files.
public enum FeedbackPackageMode: String, Codable, Sendable {
    case quick
    case full
}

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
    ///   - reasonCategory: Structured feedback category (e.g. "Wrong code") chosen in the feedback sheet.
    ///   - userComment: Optional free-text comment from the feedback sheet.
    ///   - mode: `.full` (default) writes the complete diagnostic set; `.quick` writes triage essentials only.
    /// - Returns: The URL to the newly created feedback package folder.
    public func generateFeedbackPackage(
        for message: AssistMessage? = nil,
        reason: String? = nil,
        reasonCategory: String? = nil,
        userComment: String? = nil,
        mode: FeedbackPackageMode = .full
    ) async throws -> URL {
        isGenerating = true
        lastErrorMessage = nil
        defer { isGenerating = false }

        logger.info("Starting Feedback Info diagnostic package generation (mode: \(mode.rawValue))...")

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

        let isQuick = (mode == .quick)

        if isQuick {
            // Quick mode: triage essentials only (flagged turn ±2 for the transcription).
            try saveAndRecord(collectFeedbackMetadata(message: message, reason: reason, reasonCategory: reasonCategory, userComment: userComment, mode: mode), filename: "feedback_metadata.json")
            try saveAndRecord(collectConversationMetadata(messages: messages, activeConvId: activeConvId, message: message), filename: "conversation_metadata.json")
            try saveAndRecord(collectFullTranscription(from: messages, centeredOn: message, window: 2), filename: "full_transcription.json")
            try saveAndRecord(collectTurnTelemetry(from: messages), filename: "turn_telemetry.json")
            try saveAndRecord(collectToolCalls(from: messages), filename: "tool_calls.json")
            try saveAndRecord(collectErrorDiagnostics(from: messages), filename: "error_diagnostics.json")
        } else {
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
            try saveAndRecord(collectFeedbackMetadata(message: message, reason: reason, reasonCategory: reasonCategory, userComment: userComment, mode: mode), filename: "feedback_metadata.json")

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

            // 37. turn_telemetry.json (Per-turn model/provider/token-usage/request-metrics telemetry)
            try saveAndRecord(collectTurnTelemetry(from: messages), filename: "turn_telemetry.json")

            // 38. retry_outcomes.json (Regenerations and whether they followed user feedback)
            try saveAndRecord(collectRetryOutcomes(from: messages), filename: "retry_outcomes.json")

            // 39. user_actions.json (In-session user action log: copies, retries, votes, artifact opens)
            try saveAndRecord(collectUserActions(), filename: "user_actions.json")

            // 40. artifacts_linked.json (Artifacts created this session with source message linkage)
            try saveAndRecord(collectArtifactsLinked(), filename: "artifacts_linked.json")

            // 41. tool_schemas_snapshot.json (Parameter schemas for every tool invoked this session)
            try saveAndRecord(collectToolSchemasSnapshot(from: messages), filename: "tool_schemas_snapshot.json")

            // 42. session_timeline_waterfall.json (Single chronological event stream: messages, tools, actions, votes, diagnostics)
            try saveAndRecord(collectSessionTimelineWaterfall(from: messages), filename: "session_timeline_waterfall.json")

            // 43. message_revision_lineage.json (Regeneration chains: original → retries per retried message)
            try saveAndRecord(collectMessageRevisionLineage(from: messages), filename: "message_revision_lineage.json")

            // 44. prompt_context_snapshot.json (Prompt context assembly at feedback time)
            try saveAndRecord(collectPromptContextSnapshot(), filename: "prompt_context_snapshot.json")

            // 45. conversation_attachments.json (Every attachment with its message linkage)
            try saveAndRecord(collectConversationAttachments(from: messages), filename: "conversation_attachments.json")

            // 46. feedback_votes_history.json (Structured thumbs-up/down vote history)
            try saveAndRecord(collectFeedbackVotes(), filename: "feedback_votes_history.json")

            // 47. model_registry_snapshot.json (Full discovered-model registry state)
            try saveAndRecord(collectModelRegistrySnapshot(), filename: "model_registry_snapshot.json")

            // 48. tool_result_full_failures.json (Complete untruncated failed tool results)
            try saveAndRecord(collectFullFailedToolResults(from: messages), filename: "tool_result_full_failures.json")

            // 49. session_overview.json (Session-level aggregate summary)
            try saveAndRecord(collectSessionOverview(from: messages), filename: "session_overview.json")
        }

        // Privacy notice ships with every package (not counted as a JSON telemetry file).
        try savePrivacyNotice(to: packageURL)

        // feedback_index.json (Package manifest index listing all generated telemetry files — always last)
        try saveAndRecord(collectFeedbackIndex(fileNames: generatedFiles, folderName: folderName, mode: mode), filename: "feedback_index.json")

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
        let redacted = redactForPrivacy(object)
        let data = try JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }

    /// Privacy redaction pass applied to every object before it is written to
    /// a feedback package: string values under credential-shaped keys
    /// (`token`, `secret`, `password`, `key`, `auth` — case-insensitive) are
    /// replaced with `<redacted>`, and occurrences of the user's home
    /// directory path in any string collapse to `~`.
    private func redactForPrivacy(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var redacted: [String: Any] = [:]
            for (key, nested) in dict {
                let loweredKey = key.lowercased()
                let isCredentialKey = ["token", "secret", "password", "key", "auth"].contains(where: { loweredKey.contains($0) })
                if isCredentialKey, nested is String {
                    redacted[key] = "<redacted>"
                } else {
                    redacted[key] = redactForPrivacy(nested)
                }
            }
            return redacted
        }
        if let array = value as? [Any] {
            return array.map { redactForPrivacy($0) }
        }
        if let string = value as? String {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if !homePath.isEmpty, string.contains(homePath) {
                return string.replacingOccurrences(of: homePath, with: "~")
            }
            return string
        }
        return value
    }

    /// Writes the privacy notice shipped with every feedback package.
    private func savePrivacyNotice(to packageURL: URL) throws {
        let notice = """
        ASSIST FEEDBACK PACKAGE — PRIVACY NOTICE
        ========================================

        This package contains the FULL TEXT of your Assist conversation in this
        session (user prompts, assistant responses, tool inputs/outputs, file
        paths, and error details), plus diagnostic telemetry about models,
        tools, and system state.

        Before sharing this package with anyone (including the SwiftCode
        developers):

        1. Open the JSON files and search for anything you would not want
           shared: passwords, API keys, tokens, private file contents,
           customer data, or internal project details.
        2. Credential-shaped values are automatically replaced with
           "<redacted>" and your home directory path is collapsed to "~",
           but automatic redaction cannot catch everything — review manually.
        3. Delete any file you are uncomfortable sharing, or redact the
           sensitive portions before sending.
        4. Share only through a channel you trust, and prefer private
           support threads over public forums.

        Generated: \(ISO8601DateFormatter().string(from: Date()))
        """
        try notice.write(to: packageURL.appendingPathComponent("privacy_notice.txt"), atomically: true, encoding: .utf8)
    }

    /// Appends a single-line JSON record to `positive_feedback.jsonl` in the
    /// Feedback Info root. Used by the thumbs-up action — no package is generated.
    /// The optional context parameters enrich the entry so a bare thumbs-up
    /// still carries the model, provider, conversation, and a content preview.
    public static func appendPositiveFeedbackEntry(
        messageID: UUID,
        modelId: String?,
        providerID: String? = nil,
        conversationID: UUID? = nil,
        contentPreview: String? = nil,
        toolCallCount: Int? = nil
    ) {
        let url = shared.feedbackInfoRootDirectory.appendingPathComponent("positive_feedback.jsonl")
        var entry: [String: Any] = [
            "messageID": messageID.uuidString,
            "modelId": modelId ?? "unknown",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let providerID { entry["providerID"] = providerID }
        if let conversationID { entry["conversationID"] = conversationID.uuidString }
        if let contentPreview { entry["contentPreview"] = String(contentPreview.prefix(300)) }
        if let toolCallCount { entry["toolCallCount"] = toolCallCount }
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8),
              let lineData = (line + "\n").data(using: .utf8) else { return }
        if let existing = try? Data(contentsOf: url) {
            var combined = existing
            combined.append(lineData)
            try? combined.write(to: url, options: .atomic)
        } else {
            try? lineData.write(to: url, options: .atomic)
        }
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

    private func collectFullTranscription(from messages: [AssistMessage], centeredOn flagged: AssistMessage? = nil, window: Int? = nil) -> [[String: Any]] {
        let visible: [AssistMessage]
        if let flagged, let window, let flaggedIndex = messages.firstIndex(where: { $0.id == flagged.id }) {
            let lower = max(0, flaggedIndex - window)
            let upper = min(messages.count, flaggedIndex + window + 1)
            visible = Array(messages[lower..<upper])
        } else {
            visible = messages
        }
        return visible.map { msg -> [String: Any] in
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
            if msg.role == .assistant {
                dict["modelId"] = msg.modelId ?? "unknown"
                dict["providerID"] = msg.providerID ?? "unknown"
                if let usage = msg.tokenUsage {
                    dict["tokenUsage"] = [
                        "promptTokens": usage.promptTokens,
                        "completionTokens": usage.completionTokens,
                        "totalTokens": usage.totalTokens
                    ]
                }
                if let retryOf = msg.retryOfMessageID {
                    dict["retryOfMessageID"] = retryOf.uuidString
                }
                dict["regenerationCount"] = msg.regenerationCount
            }
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
                    var entry: [String: Any] = [
                        "sequenceIndex": sequence,
                        "toolId": tool.toolId,
                        "purpose": tool.purpose,
                        "status": tool.status.rawValue,
                        "durationSeconds": tool.duration,
                        "resultPreview": String(tool.result.prefix(500)),
                        "resultLength": tool.result.count,
                        "timestamp": ISO8601DateFormatter().string(from: tool.timestamp),
                        "messageId": msg.id.uuidString
                    ]
                    if let summary = tool.argumentsSummary, !summary.isEmpty {
                        entry["argumentsSummary"] = summary
                    }
                    allTools.append(entry)
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
            "selectedAssistModelID": s.selectedAssistModelID,
            "useOtherModelsWhenRateLimited": s.useOtherModelsWhenRateLimited,
            "metaSelectedOtherModelID": s.metaSelectedOtherModelID,
            "metaSelectedOtherModelProvider": s.metaSelectedOtherModelProvider,
            "onlyUseFreeModels": s.onlyUseFreeModels,
            "swiftCloudModelsEnabled": s.swiftCloudModelsEnabled,
            "useSavedModels": s.useSavedModels,
            "assistModelRoutingStrategy": s.assistModelRoutingStrategy,
            "useSwiftCodeCloudModel": s.useSwiftCodeCloudModel,
            "assistGoogleAuthMode": s.assistGoogleAuthMode,
            "assistGoogleCloudProject": s.assistGoogleCloudProject,
            "assistGoogleOAuthClientIDOverride": s.assistGoogleOAuthClientIDOverride
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

    private func collectFeedbackMetadata(message: AssistMessage?, reason: String?, reasonCategory: String?, userComment: String?, mode: FeedbackPackageMode) -> [String: Any] {
        [
            "feedbackId": UUID().uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "targetedMessageId": message?.id.uuidString ?? "none",
            "targetedMessagePreview": String(message?.content.prefix(300) ?? ""),
            "userReason": reason ?? "User clicked Feedback on Assist response",
            "reasonCategory": reasonCategory ?? "none",
            "userComment": userComment ?? "",
            "packageMode": mode.rawValue,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
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

    private func collectFeedbackIndex(fileNames: [String], folderName: String, mode: FeedbackPackageMode) -> [String: Any] {
        [
            "package": folderName,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "packageMode": mode.rawValue,
            "totalJsonFiles": fileNames.count,
            "files": fileNames,
            "privacyNotice": "privacy_notice.txt",
            "categories": [
                "codebase": ["codebase_info.json", "code_editor_context.json", "git_state_snapshot.json", "repository_instructions.json"],
                "conversation": ["user_requests.json", "full_transcription.json", "conversation_metadata.json", "conversation_memory_graph.json", "turn_telemetry.json", "retry_outcomes.json", "user_actions.json", "artifacts_linked.json"],
                "tools": ["tool_calls.json", "tool_metrics.json", "tool_routing_policy_eval.json", "tool_schemas_snapshot.json"],
                "model_and_finetuning": ["model_telemetry.json", "fine_tuning_pairs.json", "dpo_preference_dataset.json", "negative_feedback_analysis.json", "user_intent_classification.json", "prompt_enhancement_telemetry.json"],
                "frameworks_and_phases": ["framework_diagnostics.json", "phase_coordinator_state.json", "tasks_execution_plan.json", "agent_context_state.json", "active_skills.json", "developer_memory.json"],
                "system_assets": ["system_assets_manifest.json", "system_assets_retrieval_ledger.json", "system_assets_coverage_audit.json"],
                "backend_and_system": ["assist_settings.json", "api_endpoint_telemetry.json", "diagnostic_events_log.json", "alternative_keys_state.json", "terminal_execution_telemetry.json", "error_diagnostics.json", "system_environment.json", "runtime_performance_metrics.json", "verification_pipeline_diagnostics.json", "feedback_metadata.json"]
            ]
        ]
    }

    // MARK: - New Collectors (turn telemetry, retries, user actions, artifacts, tool schemas)

    /// Per-turn model/provider/token-usage/request-metrics telemetry for every
    /// assistant message in the session.
    private func collectTurnTelemetry(from messages: [AssistMessage]) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        let manager = AssistManager.shared
        return messages.filter { $0.role == .assistant }.map { msg in
            var dict: [String: Any] = [
                "messageId": msg.id.uuidString,
                "timestamp": iso.string(from: msg.timestamp),
                "modelId": msg.modelId ?? "unknown",
                "providerID": msg.providerID ?? "unknown",
                "regenerationCount": msg.regenerationCount,
                "retryOfMessageID": msg.retryOfMessageID?.uuidString ?? "none",
                "contentLength": msg.content.count,
                "toolCallCount": msg.activityGroup?.tools.count ?? 0,
                "noticeLevel": msg.noticeLevel?.rawValue ?? "none"
            ]
            if let usage = msg.tokenUsage {
                dict["tokenUsage"] = [
                    "promptTokens": usage.promptTokens,
                    "completionTokens": usage.completionTokens,
                    "totalTokens": usage.totalTokens
                ]
            }
            if let metrics = manager.requestMetricsByMessageID[msg.id] {
                var checkpoints: [String: String] = ["messageSubmitted": iso.string(from: metrics.messageSubmitted)]
                let dated: [(String, Date?)] = [
                    ("sessionResolved", metrics.sessionResolved),
                    ("modelResolved", metrics.modelResolved),
                    ("credentialsResolved", metrics.credentialsResolved),
                    ("systemIndexRetrievalStarted", metrics.systemIndexRetrievalStarted),
                    ("systemIndexRetrievalCompleted", metrics.systemIndexRetrievalCompleted),
                    ("toolsPrepared", metrics.toolsPrepared),
                    ("requestCreated", metrics.requestCreated),
                    ("requestSent", metrics.requestSent),
                    ("modelStarted", metrics.modelStarted),
                    ("firstEventReceived", metrics.firstEventReceived),
                    ("firstReasoningDelta", metrics.firstReasoningDelta),
                    ("firstTextDelta", metrics.firstTextDelta),
                    ("firstVisibleRender", metrics.firstVisibleRender),
                    ("firstToolCall", metrics.firstToolCall),
                    ("toolExecutionStarted", metrics.toolExecutionStarted),
                    ("toolExecutionCompleted", metrics.toolExecutionCompleted),
                    ("followUpRequestInitiated", metrics.followUpRequestInitiated),
                    ("responseCompleted", metrics.responseCompleted)
                ]
                for (name, date) in dated {
                    if let date { checkpoints[name] = iso.string(from: date) }
                }
                dict["requestCheckpoints"] = checkpoints
                var latencies: [String: Double] = [:]
                let timed: [(String, TimeInterval?)] = [
                    ("timeToRequest", metrics.timeToRequest),
                    ("timeToFirstEvent", metrics.timeToFirstEvent),
                    ("timeToFirstReasoning", metrics.timeToFirstReasoning),
                    ("timeToFirstText", metrics.timeToFirstText),
                    ("timeToFirstVisibleRender", metrics.timeToFirstVisibleRender),
                    ("timeToFirstToolCall", metrics.timeToFirstToolCall),
                    ("preparationDuration", metrics.preparationDuration),
                    ("systemIndexRetrievalDuration", metrics.systemIndexRetrievalDuration),
                    ("totalResponseTime", metrics.totalResponseTime)
                ]
                for (name, value) in timed {
                    if let value { latencies[name] = value }
                }
                dict["latenciesSeconds"] = latencies
            } else {
                dict["requestMetrics"] = "unavailable"
            }
            return dict
        }
    }

    /// Messages that regenerate a previous response, with whether the retry
    /// came after explicit user feedback on the retried message.
    private func collectRetryOutcomes(from messages: [AssistMessage]) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        let datedEvents = AssistUserActionLog.datedEvents()
        return messages.filter { $0.retryOfMessageID != nil }.map { msg in
            let retryOf = msg.retryOfMessageID!
            let cameAfterFeedback = datedEvents.contains { entry in
                switch entry.action {
                case .negativeFeedback(let id), .positiveFeedback(let id):
                    return id == retryOf && entry.recordedAt <= msg.timestamp
                default:
                    return false
                }
            }
            return [
                "messageId": msg.id.uuidString,
                "retryOfMessageID": retryOf.uuidString,
                "regenerationCount": msg.regenerationCount,
                "timestamp": iso.string(from: msg.timestamp),
                "modelId": msg.modelId ?? "unknown",
                "cameAfterFeedback": cameAfterFeedback,
                "contentLength": msg.content.count
            ] as [String: Any]
        }
    }

    /// In-session user action log: copies, retry requests, feedback votes,
    /// artifact opens, and applied edits.
    private func collectUserActions() -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        return AssistUserActionLog.datedEvents().map { entry in
            var dict: [String: Any] = ["recordedAt": iso.string(from: entry.recordedAt)]
            switch entry.action {
            case .copied(let messageID):
                dict["type"] = "copied"
                dict["messageID"] = messageID.uuidString
            case .retryRequested(let messageID):
                dict["type"] = "retryRequested"
                dict["messageID"] = messageID.uuidString
            case .artifactOpened(let artifactID, let title):
                dict["type"] = "artifactOpened"
                dict["artifactID"] = artifactID.uuidString
                dict["title"] = title
            case .editApplied(let messageID):
                dict["type"] = "editApplied"
                dict["messageID"] = messageID.uuidString
            case .positiveFeedback(let messageID):
                dict["type"] = "positiveFeedback"
                dict["messageID"] = messageID.uuidString
            case .negativeFeedback(let messageID):
                dict["type"] = "negativeFeedback"
                dict["messageID"] = messageID.uuidString
            }
            return dict
        }
    }

    /// Artifacts created this session, linked to their source message when
    /// available. `sourceMessageID` is read defensively via Mirror so this
    /// collector works with or without the Area 3 `AssistArtifactRecord`
    /// extension.
    private func collectArtifactsLinked() -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        return AssistArtifactStore.shared.records.map { record in
            var dict: [String: Any] = [
                "id": record.id.uuidString,
                "filename": record.filename,
                "title": record.title,
                "kind": "\(record.kind)",
                "relativePath": record.relativePath,
                "createdAt": iso.string(from: record.createdAt),
                "modifiedAt": iso.string(from: record.modifiedAt)
            ]
            var sourceMessageID = "unknown"
            let mirror = Mirror(reflecting: record)
            if let child = mirror.children.first(where: { $0.label == "sourceMessageID" }) {
                if let uuid = child.value as? UUID {
                    sourceMessageID = uuid.uuidString
                } else {
                    // Optional<UUID>: unwrap one level via Mirror.
                    let inner = Mirror(reflecting: child.value)
                    if inner.displayStyle == .optional,
                       let first = inner.children.first,
                       let uuid = first.value as? UUID {
                        sourceMessageID = uuid.uuidString
                    }
                }
            }
            dict["sourceMessageID"] = sourceMessageID
            return dict
        }
    }

    /// Parameter schemas for every tool invoked this session (id + JSON schema).
    private func collectToolSchemasSnapshot(from messages: [AssistMessage]) -> [[String: Any]] {
        let invokedIDs = Set(messages.flatMap { $0.activityGroup?.tools.map { $0.toolId } ?? [] })
        let schemasByName: [String: [String: Any]] = Dictionary(
            uniqueKeysWithValues: AssistToolRegistry.shared.getToolSchemas().compactMap { dict -> (String, [String: Any])? in
                guard let name = dict["name"] as? String else { return nil }
                return (name, dict)
            }
        )
        return invokedIDs.sorted().map { toolId in
            var entry: [String: Any] = ["id": toolId]
            if let schema = schemasByName[toolId], let params = schema["parameters"] {
                entry["parametersSchema"] = params
            } else {
                entry["parametersSchema"] = "unavailable"
            }
            return entry
        }
    }

    /// Single chronological waterfall of the whole session: user/assistant
    /// messages, tool calls, user actions, feedback votes, and diagnostic
    /// events, sorted by timestamp. The first file to open when reconstructing
    /// what happened and in what order.
    private func collectSessionTimelineWaterfall(from messages: [AssistMessage]) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        let manager = AssistManager.shared
        var events: [(date: Date, kind: String, payload: [String: Any])] = []

        for msg in messages {
            var payload: [String: Any] = [
                "messageID": msg.id.uuidString,
                "role": msg.role.rawValue,
                "contentLength": msg.content.count,
                "contentPreview": String(msg.content.prefix(200))
            ]
            if msg.role == .assistant {
                payload["modelId"] = msg.modelId ?? "unknown"
                payload["providerID"] = msg.providerID ?? "unknown"
                if let total = manager.requestMetricsByMessageID[msg.id]?.totalResponseTime {
                    payload["totalResponseTimeSeconds"] = total
                }
            }
            events.append((msg.timestamp, "message", payload))

            if let tools = msg.activityGroup?.tools {
                for tool in tools {
                    events.append((tool.timestamp, "tool_call", [
                        "messageID": msg.id.uuidString,
                        "toolId": tool.toolId,
                        "status": tool.status.rawValue,
                        "durationSeconds": tool.duration,
                        "purpose": tool.purpose
                    ]))
                }
            }
        }

        for entry in AssistUserActionLog.datedEvents() {
            let payload: [String: Any]
            switch entry.action {
            case .copied(let id):
                payload = ["action": "copied", "messageID": id.uuidString]
            case .retryRequested(let id):
                payload = ["action": "retryRequested", "messageID": id.uuidString]
            case .artifactOpened(let id, let title):
                payload = ["action": "artifactOpened", "artifactID": id.uuidString, "title": title]
            case .editApplied(let id):
                payload = ["action": "editApplied", "messageID": id.uuidString]
            case .positiveFeedback(let id):
                payload = ["action": "positiveFeedback", "messageID": id.uuidString]
            case .negativeFeedback(let id):
                payload = ["action": "negativeFeedback", "messageID": id.uuidString]
            }
            events.append((entry.recordedAt, "user_action", payload))
        }

        for vote in AssistFeedbackVoteLog.allVotes() {
            events.append((vote.recordedAt, "feedback_vote", [
                "voteID": vote.voteID.uuidString,
                "messageID": vote.messageID.uuidString,
                "isPositive": vote.isPositive,
                "reasonCategory": vote.reasonCategory ?? "none"
            ]))
        }

        for e in DiagnosticEventBus.shared.events {
            events.append((e.timestamp, "diagnostic_event", [
                "component": e.component,
                "severity": e.severity,
                "category": e.category,
                "message": e.message
            ]))
        }

        return events.sorted { $0.date < $1.date }.map { entry in
            var dict = entry.payload
            dict["timestamp"] = iso.string(from: entry.date)
            dict["eventKind"] = entry.kind
            return dict
        }
    }

    /// Regeneration chains: for every retried assistant message, the lineage
    /// original → retries, with per-revision model, timestamps, content sizes,
    /// and failure markers. Orphan retries (root outside this session) are
    /// grouped under their nearest known ancestor.
    private func collectMessageRevisionLineage(from messages: [AssistMessage]) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        let assistants = messages.filter { $0.role == .assistant }
        let byID = Dictionary(uniqueKeysWithValues: assistants.map { ($0.id, $0) })

        func rootOf(_ msg: AssistMessage) -> AssistMessage {
            var current = msg
            var seen: Set<UUID> = [current.id]
            while let parentID = current.retryOfMessageID,
                  let parent = byID[parentID],
                  !seen.contains(parentID) {
                seen.insert(parentID)
                current = parent
            }
            return current
        }

        var chains: [UUID: [AssistMessage]] = [:]
        for msg in assistants where msg.retryOfMessageID != nil {
            let root = rootOf(msg)
            chains[root.id, default: []].append(msg)
        }

        return chains.map { rootID, retries in
            let root = byID[rootID]
            let ordered = retries.sorted { $0.timestamp < $1.timestamp }
            return [
                "rootMessageID": rootID.uuidString,
                "rootTimestamp": root.map { iso.string(from: $0.timestamp) } ?? "unknown",
                "rootModelId": root?.modelId ?? "unknown",
                "rootProviderID": root?.providerID ?? "unknown",
                "rootContentLength": root?.content.count ?? 0,
                "revisionCount": ordered.count,
                "revisions": ordered.map { rev -> [String: Any] in
                    [
                        "messageID": rev.id.uuidString,
                        "timestamp": iso.string(from: rev.timestamp),
                        "modelId": rev.modelId ?? "unknown",
                        "providerID": rev.providerID ?? "unknown",
                        "regenerationCount": rev.regenerationCount,
                        "contentLength": rev.content.count,
                        "toolCallCount": rev.activityGroup?.tools.count ?? 0,
                        "hadServerError": rev.serverError != nil,
                        "hadFailedTools": rev.activityGroup?.tools.contains(where: { $0.status == .failed }) ?? false,
                        "noticeLevel": rev.noticeLevel?.rawValue ?? "none"
                    ]
                }
            ] as [String: Any]
        }
    }

    /// Snapshot of the prompt context assembly at feedback time: section
    /// titles with token estimates and previews, plus the active SystemIndex
    /// retrieval ledger. Honestly labeled as a snapshot — it reflects the
    /// assembly when the package was generated, not per-turn history.
    private func collectPromptContextSnapshot() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let manager = AssistManager.shared
        let sections = manager.modelContext.map { s -> [String: Any] in
            [
                "title": s.title,
                "estimatedTokens": s.estimatedTokens,
                "contentLength": s.content.count,
                "contentPreview": String(s.content.prefix(300)),
                "isFixed": s.isFixed
            ]
        }
        let ledger = manager.activeRetrievalLedger
        return [
            "capturedAt": iso.string(from: Date()),
            "snapshotScope": "prompt-context at feedback-package generation time (not per-turn history)",
            "sectionCount": sections.count,
            "totalEstimatedTokens": sections.reduce(0) { $0 + ($1["estimatedTokens"] as? Int ?? 0) },
            "sections": sections,
            "retrievalLedger": [
                "retrievalRounds": ledger?.retrievalRounds ?? 0,
                "retrievedChunkIDs": Array(ledger?.retrievedChunkIDs ?? [])
            ]
        ]
    }

    /// Consolidated index of every attachment across the session, each linked
    /// to its message — the single place to see what files rode along.
    private func collectConversationAttachments(from messages: [AssistMessage]) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        var out: [[String: Any]] = []
        for msg in messages {
            guard let atts = msg.attachments, !atts.isEmpty else { continue }
            for att in atts {
                out.append([
                    "messageID": msg.id.uuidString,
                    "role": msg.role.rawValue,
                    "timestamp": iso.string(from: msg.timestamp),
                    "filename": att.filename,
                    "sizeBytes": att.size
                ])
            }
        }
        return out
    }

    /// Structured thumbs-up / thumbs-down vote history for the session, with
    /// the down-vote category, comment, and severity captured at vote time.
    private func collectFeedbackVotes() -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        return AssistFeedbackVoteLog.allVotes().map { vote in
            var dict: [String: Any] = [
                "voteID": vote.voteID.uuidString,
                "messageID": vote.messageID.uuidString,
                "isPositive": vote.isPositive,
                "recordedAt": iso.string(from: vote.recordedAt)
            ]
            if let modelId = vote.modelId { dict["modelId"] = modelId }
            if let providerID = vote.providerID { dict["providerID"] = providerID }
            if let conversationID = vote.conversationID { dict["conversationID"] = conversationID.uuidString }
            if let category = vote.reasonCategory { dict["reasonCategory"] = category }
            if let comment = vote.userComment, !comment.isEmpty { dict["userComment"] = comment }
            if let severity = vote.severity { dict["severity"] = severity }
            return dict
        }
    }

    /// Full snapshot of the discovered model registry: every model's identity,
    /// capabilities, availability, and failure state at feedback time — so a
    /// bad response can be correlated against what the router could choose.
    private func collectModelRegistrySnapshot() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let service = AssistModelDiscoveryService.shared
        let models = service.discoveredModels.map { m -> [String: Any] in
            var dict: [String: Any] = [
                "id": m.id,
                "displayName": m.displayName,
                "providerID": m.providerID,
                "providerName": m.providerName,
                "modelIdentifier": m.modelIdentifier,
                "source": m.source.rawValue,
                "isConfigured": m.isConfigured,
                "isAvailable": m.isAvailable,
                "supportsStreaming": m.supportsStreaming,
                "supportsToolCalling": m.supportsToolCalling,
                "supportsVision": m.supportsVision,
                "supportsStructuredOutput": m.supportsStructuredOutput,
                "supportsAgenticUse": m.supportsAgenticUse,
                "supportsSubagents": m.supportsSubagents,
                "priority": m.priority,
                "status": m.status.rawValue,
                "statusDescription": m.statusDescription,
                "isCurrentlyRateLimited": m.isCurrentlyRateLimited,
                "contextWindow": m.contextWindow
            ]
            if let until = m.rateLimitedUntil { dict["rateLimitedUntil"] = iso.string(from: until) }
            if let reason = m.lastFailureReason { dict["lastFailureReason"] = reason }
            if let url = m.endpointURL { dict["endpointURL"] = url }
            return dict
        }
        return [
            "capturedAt": iso.string(from: Date()),
            "isDiscovering": service.isDiscovering,
            "lastDiscoveryDate": service.lastDiscoveryDate.map { iso.string(from: $0) } ?? "never",
            "lastDiscoveryErrors": service.lastDiscoveryErrors,
            "hiddenProviderNames": Array(service.hiddenProviderNames),
            "removedModelIDs": Array(service.removedModelIDs),
            "totalModels": models.count,
            "models": models
        ]
    }

    /// Full (untruncated) results of every failed tool call this session —
    /// the complete error text, where `tool_calls.json` only keeps a
    /// 500-character preview.
    private func collectFullFailedToolResults(from messages: [AssistMessage]) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        var out: [[String: Any]] = []
        var sequence = 1
        for msg in messages {
            guard let tools = msg.activityGroup?.tools else { continue }
            for tool in tools where tool.status == .failed {
                var entry: [String: Any] = [
                    "sequenceIndex": sequence,
                    "messageID": msg.id.uuidString,
                    "timestamp": iso.string(from: tool.timestamp),
                    "toolId": tool.toolId,
                    "purpose": tool.purpose,
                    "durationSeconds": tool.duration,
                    "resultLength": tool.result.count,
                    "fullResult": tool.result
                ]
                if let summary = tool.argumentsSummary, !summary.isEmpty {
                    entry["argumentsSummary"] = summary
                }
                out.append(entry)
                sequence += 1
            }
        }
        return out
    }

    /// Session-level aggregates: the one-file summary of the whole session —
    /// volume, models, tokens, latency, failures, and feedback activity.
    private func collectSessionOverview(from messages: [AssistMessage]) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let manager = AssistManager.shared
        let assistants = messages.filter { $0.role == .assistant }

        var totalPrompt = 0
        var totalCompletion = 0
        var modelsUsed: Set<String> = []
        var responseTimes: [Double] = []
        var failedTools = 0
        var totalTools = 0
        var serverErrors = 0
        for msg in assistants {
            if let id = msg.modelId { modelsUsed.insert(id) }
            if let usage = msg.tokenUsage {
                totalPrompt += usage.promptTokens
                totalCompletion += usage.completionTokens
            }
            if let total = manager.requestMetricsByMessageID[msg.id]?.totalResponseTime {
                responseTimes.append(total)
            }
            if let tools = msg.activityGroup?.tools {
                totalTools += tools.count
                failedTools += tools.filter { $0.status == .failed }.count
            }
            if msg.serverError != nil { serverErrors += 1 }
        }

        let modelSequence = assistants.compactMap { $0.modelId }
        var modelSwitches = 0
        for i in 1..<modelSequence.count where modelSequence[i] != modelSequence[i - 1] {
            modelSwitches += 1
        }

        let votes = AssistFeedbackVoteLog.allVotes()
        let actions = AssistUserActionLog.datedEvents()
        func actionCount(_ matches: (AssistUserActionLog.AssistUserAction) -> Bool) -> Int {
            actions.filter { matches($0.action) }.count
        }

        return [
            "capturedAt": iso.string(from: Date()),
            "sessionStart": messages.first.map { iso.string(from: $0.timestamp) } ?? "unknown",
            "sessionEnd": messages.last.map { iso.string(from: $0.timestamp) } ?? "unknown",
            "totalMessages": messages.count,
            "userMessages": messages.filter { $0.role == .user }.count,
            "assistantMessages": assistants.count,
            "modelsUsed": Array(modelsUsed).sorted(),
            "modelSwitchCount": modelSwitches,
            "totalPromptTokens": totalPrompt,
            "totalCompletionTokens": totalCompletion,
            "totalTokens": totalPrompt + totalCompletion,
            "turnsWithLatencyMetrics": responseTimes.count,
            "avgResponseTimeSeconds": responseTimes.isEmpty ? 0 : responseTimes.reduce(0, +) / Double(responseTimes.count),
            "maxResponseTimeSeconds": responseTimes.max() ?? 0,
            "totalToolCalls": totalTools,
            "failedToolCalls": failedTools,
            "serverErrors": serverErrors,
            "retryCount": messages.filter { $0.retryOfMessageID != nil }.count,
            "positiveVotes": votes.filter { $0.isPositive }.count,
            "negativeVotes": votes.filter { !$0.isPositive }.count,
            "copies": actionCount { if case .copied = $0 { return true }; return false },
            "retryRequests": actionCount { if case .retryRequested = $0 { return true }; return false },
            "artifactsOpened": actionCount { if case .artifactOpened = $0 { return true }; return false },
            "activeConversationID": AssistConversationHistory.shared.activeConversationID?.uuidString ?? "none"
        ]
    }
}
