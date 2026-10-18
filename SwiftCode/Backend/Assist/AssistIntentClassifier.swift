//
//  AssistIntentClassifier.swift
//  SwiftCode
//
//  Authoritative intent classification and tool routing engine for SwiftCode Assist.
//  Identifies primary user intent from ordinary natural language, extracts target applications
//  and resources, determines task complexity budgets, prevents unintended tool execution
//  for informational queries, and provides dependency-aware routing.
//

import Foundation

public enum GitAction: String, Sendable, Codable {
    case status
    case diff
    case commit
    case branch
    case rollback
    case log
}

public enum FileAction: String, Sendable, Codable {
    case read
    case write
    case replace
    case create
    case delete
    case move
    case rename
    case openInFinder
    case revealInFinder
}

public enum SearchType: String, Sendable, Codable {
    case symbol
    case text
    case regex
}

public enum CodingActionType: String, Sendable, Codable {
    case explain
    case refactor
    case documentation
    case preview
    case custom
}

public enum UserIntent: Sendable, Equatable {
    case git(action: GitAction, details: [String: String])
    case build(scheme: String?, configuration: String?)
    case test(target: String?)
    case codeSearch(type: SearchType, query: String)
    case fileOperation(action: FileAction, path: String?)
    case codingAction(action: CodingActionType, context: String?)
    case workerDelegation(tasks: [String])
    case complexEngineering(goal: String)
    case conversational(text: String)

    // Natural-Language Tool Intelligence intents
    case screenshot(targetApp: String?, isRegion: Bool, purpose: String?)
    case screenRecording(targetApp: String?, duration: Double?, purpose: String?)
    case appInteraction(targetApp: String?, action: String?, targetElement: String?, purpose: String?)
    indirect case multiStep(intents: [UserIntent])
    case informational(topic: String)
}

public enum TaskExecutionProfile: String, Sendable, Codable {
    case simple      // 1 direct native call, no repo exploration, no execution_plan
    case moderate    // Targeted edit/inspection, minimal exploration
    case complex     // Multi-operation, dependency graph, workers if needed
    case heavy       // Project rewrite / scratch build, multi-milestone
}

public struct ExplicitToolRequest: @unchecked Sendable, Equatable {
    public let toolId: String
    public let suggestedInput: [String: Any]
    public let explanation: String

    public static func == (lhs: ExplicitToolRequest, rhs: ExplicitToolRequest) -> Bool {
        return lhs.toolId == rhs.toolId && lhs.explanation == rhs.explanation
    }
}

public struct IntentClassificationResult: @unchecked Sendable {
    public let primaryIntent: UserIntent
    public let profile: TaskExecutionProfile
    public let explicitTool: ExplicitToolRequest?
    public let deterministicToolId: String?
    public let deterministicInput: [String: Any]?
    public let confidence: Double
    public let explanation: String
}

@MainActor
public final class AssistIntentClassifier: Sendable {
    public static let shared = AssistIntentClassifier()

    private init() {}

    /// Classifies user text into structured intent, profile, and routing recommendations.
    public func classify(prompt: String, activeFile: String? = nil) -> IntentClassificationResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Check for informational requests FIRST to avoid unintended tool execution
        if let topic = checkInformationalRequest(lower, original: trimmed) {
            return IntentClassificationResult(
                primaryIntent: .informational(topic: topic),
                profile: .simple,
                explicitTool: nil,
                deterministicToolId: nil,
                deterministicInput: nil,
                confidence: 0.98,
                explanation: "Informational inquiry ('\(topic)'); answer directly in text without executing tools."
            )
        }

        // 2. Check for explicit tool priority requests
        let explicit = detectExplicitTool(lower: lower, original: trimmed, activeFile: activeFile)

        // 3. Explicit `@Reverse` invocation: deterministic route to the native Reverse subsystem
        if let reverse = ReverseCommandParser.parse(message: trimmed) {
            var input: [String: Any] = [
                "targetPath": reverse.targetPath ?? "",
                "operation": reverse.operation.rawValue,
                "task": reverse.task,
            ]
            if let objdump = reverse.objdumpOperation {
                input["objdumpOperation"] = objdump.rawValue
            }
            if let symbol = reverse.symbol {
                input["symbol"] = symbol
            }
            return IntentClassificationResult(
                primaryIntent: .complexEngineering(goal: trimmed),
                profile: .moderate,
                explicitTool: ExplicitToolRequest(toolId: "reverse_analyze", suggestedInput: input, explanation: "Explicit @Reverse investigation routed to the native Reverse subsystem"),
                deterministicToolId: "reverse_analyze",
                deterministicInput: input,
                confidence: 0.99,
                explanation: "Explicit @Reverse command routed to reverse_analyze"
            )
        }

        // 4. High-confidence Git Operations
        if isGitStatusRequest(lower) {
            return IntentClassificationResult(
                primaryIntent: .git(action: .status, details: [:]),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "status"], explanation: "Inspect git working tree status"),
                deterministicToolId: "version_control_operator",
                deterministicInput: ["action": "status"],
                confidence: 0.98,
                explanation: "Direct Git status request routed to native version control operator"
            )
        }

        if isGitDiffRequest(lower) {
            return IntentClassificationResult(
                primaryIntent: .git(action: .diff, details: [:]),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "diff"], explanation: "Inspect working tree diff"),
                deterministicToolId: "version_control_operator",
                deterministicInput: ["action": "diff"],
                confidence: 0.95,
                explanation: "Direct Git diff request routed to native version control operator"
            )
        }

        if isGitCommitRequest(lower) {
            let msg = extractCommitMessage(from: trimmed) ?? "Assist automated commit"
            return IntentClassificationResult(
                primaryIntent: .git(action: .commit, details: ["message": msg]),
                profile: .moderate,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "commit", "message": msg], explanation: "Commit changes using git"),
                deterministicToolId: "version_control_operator",
                deterministicInput: ["action": "commit", "message": msg],
                confidence: 0.95,
                explanation: "Git commit request routed to native version control operator"
            )
        }

        if isGitBranchRequest(lower) {
            let branch = extractBranchName(from: trimmed) ?? "status"
            return IntentClassificationResult(
                primaryIntent: .git(action: .branch, details: ["name": branch]),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "branch", "name": branch], explanation: "Inspect or manage git branch"),
                deterministicToolId: "version_control_operator",
                deterministicInput: ["action": "branch", "name": branch],
                confidence: 0.92,
                explanation: "Git branch request routed to native version control operator"
            )
        }

        // 5. Multi-step workflows (e.g. "Open Finder, navigate to Downloads, and take a screenshot")
        if let multiSteps = detectMultiStepWorkflows(lower: lower, original: trimmed) {
            let firstPrereqToolId = multiSteps.first?.suggestedToolId
            let firstInput = multiSteps.first?.suggestedInput
            return IntentClassificationResult(
                primaryIntent: .multiStep(intents: multiSteps.map(\.intent)),
                profile: .complex,
                explicitTool: explicit,
                deterministicToolId: firstPrereqToolId,
                deterministicInput: firstInput,
                confidence: 0.94,
                explanation: "Multi-tool dependency sequence identified: \(multiSteps.map(\.label).joined(separator: " -> "))"
            )
        }

        // 6. High-confidence Screen Recording Operations
        if isScreenRecordingRequest(lower) {
            let targetApp = extractTargetApplication(from: trimmed)
            let duration = extractRecordingDuration(from: lower) ?? 10.0
            let input: [String: Any] = [
                "app_identifier": targetApp ?? "Xcode",
                "recording_duration": duration,
                "capture_mode": "window"
            ]
            return IntentClassificationResult(
                primaryIntent: .screenRecording(targetApp: targetApp, duration: duration, purpose: trimmed),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "take_screenrecord", suggestedInput: input, explanation: "Record screen of target application"),
                deterministicToolId: "take_screenrecord",
                deterministicInput: input,
                confidence: 0.96,
                explanation: "Screen recording intent detected for target '\(targetApp ?? "current application")' (duration: \(duration)s)"
            )
        }

        // 7. High-confidence Screenshot / Visual Capture Operations
        if isScreenshotRequest(lower) {
            let isRegion = lower.contains("selected part") || lower.contains("region") || lower.contains("part of my screen") || lower.contains("crop")
            let targetApp = extractTargetApplication(from: trimmed)
            let captureMode = isRegion ? "region" : "fullscreen"
            var input: [String: Any] = [
                "capture_mode": captureMode,
                "purpose": trimmed
            ]
            if let targetApp {
                input["target_app"] = targetApp
            }

            return IntentClassificationResult(
                primaryIntent: .screenshot(targetApp: targetApp, isRegion: isRegion, purpose: trimmed),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "take_screenshot", suggestedInput: input, explanation: "Capture screenshot for visual analysis"),
                deterministicToolId: "take_screenshot",
                deterministicInput: input,
                confidence: 0.96,
                explanation: "Visual screenshot intent detected (mode: \(captureMode), target: \(targetApp ?? "display"))"
            )
        }

        // 8. Application Interaction Operations (e.g. "Open Finder", "Navigate to Downloads")
        if isAppInteractionRequest(lower) {
            let targetApp = extractTargetApplication(from: trimmed) ?? "Finder"
            let action = lower.contains("click") ? "click" : "activate"
            let input: [String: Any] = [
                "action": action,
                "app_identifier": targetApp
            ]
            return IntentClassificationResult(
                primaryIntent: .appInteraction(targetApp: targetApp, action: action, targetElement: nil, purpose: trimmed),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "use_app", suggestedInput: input, explanation: "Operate macOS application via Accessibility and UI automation"),
                deterministicToolId: "use_app",
                deterministicInput: input,
                confidence: 0.94,
                explanation: "Application interaction intent detected for '\(targetApp)' (action: \(action))"
            )
        }

        // 9. High-confidence Build Operations
        if isBuildRequest(lower) {
            let scheme = extractScheme(from: trimmed)
            let config = lower.contains("release") ? "Release" : "Debug"
            var input: [String: Any] = ["configuration": config]
            if let s = scheme { input["scheme"] = s }

            return IntentClassificationResult(
                primaryIntent: .build(scheme: scheme, configuration: config),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "project_build", suggestedInput: input, explanation: "Build active project"),
                deterministicToolId: "project_build",
                deterministicInput: input,
                confidence: 0.95,
                explanation: "Direct build request routed to native project build tool"
            )
        }

        // 10. High-confidence Test Operations
        if isTestRequest(lower) {
            return IntentClassificationResult(
                primaryIntent: .test(target: nil),
                profile: .moderate,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "project_test", suggestedInput: [:], explanation: "Run project tests"),
                deterministicToolId: "project_test",
                deterministicInput: [:],
                confidence: 0.92,
                explanation: "Test request routed to native test runner"
            )
        }

        // 11. High-confidence Finder File Operations
        if isFinderOpenRequest(lower) {
            let path = extractPath(from: trimmed) ?? activeFile ?? "."
            return IntentClassificationResult(
                primaryIntent: .fileOperation(action: .openInFinder, path: path),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "open_in_finder", suggestedInput: ["path": path], explanation: "Open item in Finder"),
                deterministicToolId: "open_in_finder",
                deterministicInput: ["path": path],
                confidence: 0.95,
                explanation: "Finder open request routed to native open_in_finder tool"
            )
        }

        if isFinderRevealRequest(lower) {
            let path = extractPath(from: trimmed) ?? activeFile ?? "."
            return IntentClassificationResult(
                primaryIntent: .fileOperation(action: .revealInFinder, path: path),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "reveal_in_finder", suggestedInput: ["path": path], explanation: "Reveal item in Finder"),
                deterministicToolId: "reveal_in_finder",
                deterministicInput: ["path": path],
                confidence: 0.95,
                explanation: "Finder reveal request routed to native reveal_in_finder tool"
            )
        }

        // 12. High-confidence Symbol Search
        if isSymbolSearchRequest(lower) {
            let sym = extractSymbolName(from: trimmed)
            return IntentClassificationResult(
                primaryIntent: .codeSearch(type: .symbol, query: sym),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "search_symbol", suggestedInput: ["symbolName": sym], explanation: "Locate symbol definition"),
                deterministicToolId: "search_symbol",
                deterministicInput: ["symbolName": sym],
                confidence: 0.90,
                explanation: "Symbol search routed to native symbol search tool"
            )
        }

        // 13. Explicit Worker Delegation Request
        if lower.contains("use_workers") || lower.contains("delegate to workers") || lower.contains("parallel workers") {
            return IntentClassificationResult(
                primaryIntent: .workerDelegation(tasks: []),
                profile: .complex,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "use_workers", suggestedInput: [:], explanation: "Coordinate subagent workers"),
                deterministicToolId: nil,
                deterministicInput: nil,
                confidence: 0.92,
                explanation: "Worker delegation request detected"
            )
        }

        // 14. Conversational greetings
        if isPureGreeting(lower) {
            return IntentClassificationResult(
                primaryIntent: .conversational(text: trimmed),
                profile: .simple,
                explicitTool: nil,
                deterministicToolId: nil,
                deterministicInput: nil,
                confidence: 0.99,
                explanation: "Standard conversational greeting"
            )
        }

        // 15. Complex multi-phase engineering tasks
        let isHeavy = lower.contains("rewrite") || lower.contains("from scratch") || lower.contains("create an app") || lower.contains("refactor the whole")
        let profile: TaskExecutionProfile = isHeavy ? .heavy : .complex

        return IntentClassificationResult(
            primaryIntent: .complexEngineering(goal: trimmed),
            profile: profile,
            explicitTool: explicit,
            deterministicToolId: nil,
            deterministicInput: nil,
            confidence: 0.75,
            explanation: "Multi-stage autonomous engineering task"
        )
    }

    // MARK: - Informational Query Detection

    private func checkInformationalRequest(_ lower: String, original: String) -> String? {
        // Exclude direct imperative commands
        let imperativeCommands = [
            "open finder for me", "open xcode for me", "take a screenshot now",
            "record now", "run build now", "commit now", "please do it",
            "open and ", "navigate to and ", "capture now"
        ]
        for cmd in imperativeCommands where lower.contains(cmd) {
            return nil
        }

        // Specific informational patterns
        if lower.hasPrefix("what is a screenshot") || lower.hasPrefix("what is screenshot") || lower == "what is a screenshot?" {
            return "screenshot concept"
        }
        if lower.hasPrefix("what does the screenshot tool do") || lower.contains("what does the screenshot tool do") {
            return "screenshot tool capabilities"
        }
        if lower.hasPrefix("explain how screen recording works") || lower.contains("explain how screen recording works") {
            return "screen recording procedure"
        }
        if lower.hasPrefix("how does screen recording work") || lower.contains("how does screen recording work") {
            return "screen recording mechanism"
        }
        if lower.hasPrefix("how can i navigate finder using keyboard shortcuts") || lower.contains("navigate finder using keyboard shortcuts") {
            return "Finder keyboard navigation"
        }
        if lower.hasPrefix("how do i open finder") || lower.hasPrefix("how can i open finder") {
            return "opening Finder guide"
        }
        if lower.hasPrefix("how do i ") || lower.hasPrefix("how can i ") || lower.hasPrefix("what is ") || lower.hasPrefix("what does ") || lower.hasPrefix("explain ") {
            // General informational inquiry unless followed by an explicit imperative action
            if !lower.contains("take a screenshot") && !lower.contains("open ") && !lower.contains("record ") {
                return original
            }
        }
        return nil
    }

    // MARK: - Multi-Step Workflow Detection

    private struct StepPlan {
        let intent: UserIntent
        let suggestedToolId: String?
        let suggestedInput: [String: Any]?
        let label: String
    }

    private func detectMultiStepWorkflows(lower: String, original: String) -> [StepPlan]? {
        var steps: [StepPlan] = []

        // Pattern: "Open Finder, navigate to Downloads, and take a screenshot"
        if lower.contains("open finder") && lower.contains("screenshot") {
            steps.append(StepPlan(
                intent: .appInteraction(targetApp: "Finder", action: "activate", targetElement: nil, purpose: "Activate Finder"),
                suggestedToolId: "use_app",
                suggestedInput: ["action": "activate", "app_identifier": "Finder"],
                label: "Activate Finder"
            ))
            let isRegion = lower.contains("region") || lower.contains("selected part")
            steps.append(StepPlan(
                intent: .screenshot(targetApp: "Finder", isRegion: isRegion, purpose: original),
                suggestedToolId: "take_screenshot",
                suggestedInput: ["capture_mode": isRegion ? "region" : "fullscreen", "purpose": "Screenshot Finder window"],
                label: "Capture Screenshot"
            ))
            return steps
        }

        // Pattern: "Open Xcode, reproduce the issue, record the result, and summarize what happened"
        if lower.contains("xcode") && (lower.contains("record") || lower.contains("video")) && (lower.contains("reproduce") || lower.contains("issue") || lower.contains("open")) {
            steps.append(StepPlan(
                intent: .appInteraction(targetApp: "Xcode", action: "activate", targetElement: nil, purpose: "Activate Xcode"),
                suggestedToolId: "use_app",
                suggestedInput: ["action": "activate", "app_identifier": "Xcode"],
                label: "Activate Xcode"
            ))
            let duration = extractRecordingDuration(from: lower) ?? 10.0
            steps.append(StepPlan(
                intent: .screenRecording(targetApp: "Xcode", duration: duration, purpose: original),
                suggestedToolId: "take_screenrecord",
                suggestedInput: ["app_identifier": "Xcode", "recording_duration": duration, "capture_mode": "window"],
                label: "Record Xcode"
            ))
            return steps
        }

        // Pattern: "Inspect the current application, change the requested setting, and verify that it changed"
        if lower.contains("inspect") && (lower.contains("setting") || lower.contains("change")) && lower.contains("verify") {
            let targetApp = extractTargetApplication(from: original) ?? "System Settings"
            steps.append(StepPlan(
                intent: .appInteraction(targetApp: targetApp, action: "inspect_ui", targetElement: nil, purpose: "Inspect UI"),
                suggestedToolId: "use_app",
                suggestedInput: ["action": "inspect_ui", "app_identifier": targetApp],
                label: "Inspect UI"
            ))
            steps.append(StepPlan(
                intent: .appInteraction(targetApp: targetApp, action: "verify", targetElement: nil, purpose: "Verify change"),
                suggestedToolId: "use_app",
                suggestedInput: ["action": "verify", "app_identifier": targetApp],
                label: "Verify Setting"
            ))
            return steps
        }

        // Pattern: "Find the relevant file, open it in the appropriate application, and capture the resulting interface"
        if (lower.contains("find") || lower.contains("search")) && lower.contains("file") && (lower.contains("capture") || lower.contains("screenshot")) {
            steps.append(StepPlan(
                intent: .codeSearch(type: .text, query: extractQuery(from: original) ?? "file"),
                suggestedToolId: "search_text",
                suggestedInput: ["query": extractQuery(from: original) ?? "file"],
                label: "Find File"
            ))
            steps.append(StepPlan(
                intent: .screenshot(targetApp: nil, isRegion: false, purpose: original),
                suggestedToolId: "take_screenshot",
                suggestedInput: ["capture_mode": "fullscreen", "purpose": "Capture interface"],
                label: "Capture Result"
            ))
            return steps
        }

        // Pattern: "Open Finder and tell me what you see" / "Check whether the file is visible in Finder"
        if lower.contains("finder") && (lower.contains("what you see") || lower.contains("whether the file is visible") || lower.contains("tell me what you see")) {
            steps.append(StepPlan(
                intent: .appInteraction(targetApp: "Finder", action: "activate", targetElement: nil, purpose: "Open Finder"),
                suggestedToolId: "use_app",
                suggestedInput: ["action": "activate", "app_identifier": "Finder"],
                label: "Activate Finder"
            ))
            steps.append(StepPlan(
                intent: .screenshot(targetApp: "Finder", isRegion: false, purpose: original),
                suggestedToolId: "take_screenshot",
                suggestedInput: ["capture_mode": "fullscreen", "purpose": "Inspect Finder content"],
                label: "Capture Finder"
            ))
            return steps
        }

        return nil
    }

    // MARK: - Natural-Language Screen Recording Detection

    private func isScreenRecordingRequest(_ lower: String) -> Bool {
        return lower.contains("take_screenrecord") ||
               lower.contains("screen record") ||
               lower.contains("screen recording") ||
               lower.contains("record xcode") ||
               lower.contains("record what happens") ||
               lower.contains("capture a video") ||
               lower.contains("record the specified application window") ||
               lower.contains("recording of this application's visible behavior") ||
               lower.contains("record the application window") ||
               (lower.contains("record") && (lower.contains("seconds") || lower.contains("video") || lower.contains("window")))
    }

    // MARK: - Natural-Language Screenshot Detection

    private func isScreenshotRequest(_ lower: String) -> Bool {
        return lower.contains("take a screenshot") ||
               lower.contains("take screenshot") ||
               lower.contains("screenshot of") ||
               lower.contains("show me what finder looks like right now") ||
               lower.contains("show me what") && lower.contains("looks like") ||
               lower.contains("look at the finder window") ||
               lower.contains("look at the current finder window") ||
               lower.contains("look at the current xcode window") ||
               lower.contains("can you inspect what's on my desktop") ||
               lower.contains("inspect what's on my desktop") ||
               lower.contains("capture the xcode editor") ||
               lower.contains("take a picture of the selected part of my screen") ||
               lower.contains("take a picture of") ||
               lower.contains("capture the screen") ||
               lower.contains("capture screen")
    }

    // MARK: - Natural-Language App Interaction Detection

    private func isAppInteractionRequest(_ lower: String) -> Bool {
        return lower == "open finder" ||
               lower == "open finder." ||
               lower == "open xcode" ||
               lower == "open xcode." ||
               lower == "open finder for me" ||
               lower.contains("navigate to the downloads folder in finder") ||
               lower.contains("open system settings and inspect the current") ||
               lower.contains("navigate through this application and test its export feature") ||
               lower.contains("click the appropriate control and tell me whether it worked") ||
               lower.hasPrefix("open finder") ||
               lower.hasPrefix("open xcode") ||
               lower.hasPrefix("open system settings")
    }

    // MARK: - Explicit Tool Request Detection

    private func detectExplicitTool(lower: String, original: String, activeFile: String?) -> ExplicitToolRequest? {
        if lower.contains("run_command") || lower.contains("execute_terminal_command") || lower.contains("use_terminal") {
            return ExplicitToolRequest(toolId: "use_terminal", suggestedInput: ["command": "echo 'ok'"], explanation: "Explicit terminal tool requested")
        }
        if lower.contains("view_file") || lower.contains("read_file") || lower.contains("file_read") {
            let path = extractPath(from: original) ?? activeFile ?? "."
            return ExplicitToolRequest(toolId: "file_read", suggestedInput: ["path": path], explanation: "Explicit file read tool requested")
        }
        if lower.contains("take_screenshot") {
            return ExplicitToolRequest(toolId: "take_screenshot", suggestedInput: ["capture_mode": "fullscreen"], explanation: "Explicit screenshot tool requested")
        }
        if lower.contains("take_screenrecord") {
            return ExplicitToolRequest(toolId: "take_screenrecord", suggestedInput: ["app_identifier": "Xcode", "recording_duration": 10.0], explanation: "Explicit screen recording tool requested")
        }
        if lower.contains("use_app") {
            return ExplicitToolRequest(toolId: "use_app", suggestedInput: ["action": "activate", "app_identifier": "Finder"], explanation: "Explicit use_app tool requested")
        }
        if lower.contains("use the git tool") || lower.contains("use git tool") || lower.contains("run git status") {
            return ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "status"], explanation: "Explicitly requested Git tool")
        }
        if lower.contains("run the build tool") || lower.contains("use the build tool") || lower.contains("run build tool") {
            return ExplicitToolRequest(toolId: "project_build", suggestedInput: [:], explanation: "Explicitly requested build tool")
        }
        if lower.contains("use the test tool") || lower.contains("run the test tool") {
            return ExplicitToolRequest(toolId: "project_test", suggestedInput: [:], explanation: "Explicitly requested test tool")
        }
        if lower.contains("use use_workers") || lower.contains("use the worker tool") || lower.contains("use workers tool") {
            return ExplicitToolRequest(toolId: "use_workers", suggestedInput: [:], explanation: "Explicitly requested use_workers tool")
        }
        if lower.contains("use the file-search tool") || lower.contains("use search tool") || lower.contains("use file search tool") {
            let q = extractQuery(from: original) ?? ""
            return ExplicitToolRequest(toolId: "search_text", suggestedInput: ["query": q], explanation: "Explicitly requested search tool")
        }
        if lower.contains("open in finder") || lower.contains("open this in finder") {
            let p = extractPath(from: original) ?? activeFile ?? "."
            return ExplicitToolRequest(toolId: "open_in_finder", suggestedInput: ["path": p], explanation: "Explicitly requested open in Finder")
        }
        if lower.contains("reveal in finder") {
            let p = extractPath(from: original) ?? activeFile ?? "."
            return ExplicitToolRequest(toolId: "reveal_in_finder", suggestedInput: ["path": p], explanation: "Explicitly requested reveal in Finder")
        }
        return nil
    }

    // MARK: - Extraction Helpers

    private func extractTargetApplication(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("system settings") { return "System Settings" }
        if lower.contains("finder") { return "Finder" }
        if lower.contains("xcode") { return "Xcode" }
        if lower.contains("safari") { return "Safari" }
        if lower.contains("terminal") { return "Terminal" }
        if lower.contains("calculator") { return "Calculator" }
        return nil
    }

    private func extractRecordingDuration(from lower: String) -> Double? {
        if lower.contains("ten seconds") || lower.contains("10 seconds") || lower.contains("10s") { return 10.0 }
        if lower.contains("next few seconds") || lower.contains("few seconds") || lower.contains("5 seconds") || lower.contains("5s") { return 5.0 }
        if lower.contains("twenty seconds") || lower.contains("20 seconds") || lower.contains("20s") { return 20.0 }
        if lower.contains("thirty seconds") || lower.contains("30 seconds") || lower.contains("30s") { return 30.0 }

        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*(?:seconds|second|sec|s)"#, options: []) {
            let ns = lower as NSString
            if let match = regex.firstMatch(in: lower, options: [], range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 {
                let numStr = ns.substring(with: match.range(at: 1))
                if let val = Double(numStr) {
                    return max(1.0, min(val, 60.0))
                }
            }
        }
        return nil
    }

    private func isGitStatusRequest(_ lower: String) -> Bool {
        return lower == "git status" ||
               lower == "check git status" ||
               lower == "check the current git status" ||
               lower == "check current git status" ||
               lower == "show git status" ||
               lower == "git state" ||
               lower.contains("check git status") ||
               lower.contains("check the git status") ||
               lower.contains("what is the git status") ||
               (lower.contains("git") && lower.contains("status"))
    }

    private func isGitDiffRequest(_ lower: String) -> Bool {
        return lower == "git diff" ||
               lower == "show git diff" ||
               lower.contains("git diff") ||
               lower.contains("check git diff") ||
               lower.contains("show working tree diff")
    }

    private func isGitCommitRequest(_ lower: String) -> Bool {
        return lower.hasPrefix("git commit") ||
               lower.contains("commit these changes") ||
               lower.contains("commit all changes") ||
               lower.contains("commit the changes")
    }

    private func isGitBranchRequest(_ lower: String) -> Bool {
        return lower == "git branch" ||
               lower.contains("current branch") ||
               lower.contains("which branch") ||
               lower.contains("show the current branch") ||
               lower.contains("create branch") ||
               lower.contains("checkout branch")
    }

    private func isBuildRequest(_ lower: String) -> Bool {
        return lower == "build this project" ||
               lower == "build project" ||
               lower == "run build" ||
               lower == "build the app" ||
               lower == "compile this project" ||
               lower == "compile project" ||
               lower.contains("build the project") ||
               lower.contains("build this project") ||
               lower.contains("run the project build")
    }

    private func isTestRequest(_ lower: String) -> Bool {
        return lower == "run tests" ||
               lower == "run the tests" ||
               lower == "test this project" ||
               lower.contains("execute unit tests") ||
               lower.contains("run the test suite")
    }

    private func isFinderOpenRequest(_ lower: String) -> Bool {
        return lower.contains("open in finder") ||
               lower.contains("open this file in finder") ||
               lower.contains("open the directory in finder")
    }

    private func isFinderRevealRequest(_ lower: String) -> Bool {
        return lower.contains("reveal in finder") ||
               lower.contains("reveal this file in finder") ||
               lower.contains("show in finder")
    }

    private func isSymbolSearchRequest(_ lower: String) -> Bool {
        return lower.contains("find the definition of") ||
               lower.contains("find symbol") ||
               lower.contains("where is") && (lower.contains("defined") || lower.contains("declared"))
    }

    private func isPureGreeting(_ lower: String) -> Bool {
        let greetings = ["hello", "hi", "hey", "good morning", "good afternoon", "howdy", "sup"]
        let words = lower.split(separator: " ").map { String($0) }
        guard let first = words.first else { return false }
        return greetings.contains(first) && words.count <= 3
    }

    private func extractCommitMessage(from text: String) -> String? {
        if let range = text.range(of: "message:") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = text.range(of: "-m ") {
            return String(text[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'\n\r\t "))
        }
        return nil
    }

    private func extractBranchName(from text: String) -> String? {
        let components = text.components(separatedBy: .whitespaces)
        if let idx = components.firstIndex(of: "branch"), idx + 1 < components.count {
            let candidate = components[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if !candidate.isEmpty && candidate != "name" && candidate != "called" {
                return candidate
            }
        }
        return nil
    }

    private func extractScheme(from text: String) -> String? {
        let components = text.components(separatedBy: .whitespaces)
        if let idx = components.firstIndex(of: "scheme"), idx + 1 < components.count {
            return components[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        return nil
    }

    private func extractPath(from text: String) -> String? {
        let words = text.components(separatedBy: .whitespaces)
        for word in words {
            let clean = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,;()"))
            if clean.contains("/") || clean.hasSuffix(".swift") || clean.hasSuffix(".json") || clean.hasSuffix(".md") {
                return clean
            }
        }
        return nil
    }

    private func extractSymbolName(from text: String) -> String {
        let words = text.components(separatedBy: .whitespaces)
        if let idx = words.firstIndex(of: "function"), idx + 1 < words.count {
            return words[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        if let idx = words.firstIndex(of: "symbol"), idx + 1 < words.count {
            return words[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        if let idx = words.firstIndex(of: "of"), idx + 1 < words.count {
            return words[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        return words.last?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) ?? ""
    }

    private func extractQuery(from text: String) -> String? {
        if let range = text.range(of: "for ") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
