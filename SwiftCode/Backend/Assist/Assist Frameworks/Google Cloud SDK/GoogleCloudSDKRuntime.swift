//
//  GoogleCloudSDKRuntime.swift
//  SwiftCode
//
//  Primary native entry point and high-level manager for the Google Cloud SDK / Antigravity runtime.
//

import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.swiftcode.GoogleCloudSDK", category: "GoogleCloudSDKRuntime")

@Observable
@MainActor
public final class GoogleCloudSDKRuntime: Sendable {
    public static let shared = GoogleCloudSDKRuntime()

    public var isAvailable: Bool = false
    public var isStarting: Bool = false
    public var isRunning: Bool = false
    public var sdkVersion: String = "unknown"
    public var activeSessionsCount: Int = 0
    public var liveLogs: [String] = []
    public var lastError: String? = nil
    public var statusDescription: String = "Offline"

    private let bridge = GoogleCloudSDKBridge()
    private var activeSessions: [String: GoogleCloudSDKSession] = [:]
    private var eventSubscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var handlersInstalled = false
    @ObservationIgnored private var startTask: Task<Void, Error>?
    /// PID of the running bridge, cached for synchronous teardown at app exit.
    @ObservationIgnored private var bridgePID: Int32?
    /// Stable UUIDs for SDK worker ids (`call_…` strings are not UUIDs).
    @ObservationIgnored private var workerUUIDs: [String: UUID] = [:]
    @ObservationIgnored private var workerNames: [String: String] = [:]
    @ObservationIgnored private var sessionTaskUUIDs: [String: UUID] = [:]

    /// Upper bound for a single tool payload returned to the model.
    private static let maxToolPayloadCharacters = 200_000

    /// Pure, argument-determined reads whose results may be reused until the next
    /// mutation. Interactive, planning, diff, log and validation tools are never cached.
    private static let cacheableToolIDs: Set<String> = [
        "file_read", "dir_read", "tree_view", "search_text", "search_regex", "search_symbol",
    ]

    /// Swift tools that delete data and therefore need explicit user approval.
    public static let destructiveToolIDs: Set<String> = ["file_delete", "dir_delete"]

    private init() {
        // Resolve availability synchronously so the very first sendMessage sees
        // the correct value instead of racing an async audit.
        if let dir = GoogleCloudSDKProcess.resolveSDKDirectory() {
            self.isAvailable = true
            self.statusDescription = "Installed at \(dir.lastPathComponent)"
        } else {
            self.isAvailable = false
            self.statusDescription = "Runtime not found"
        }
        Task { @MainActor in
            await self.installBridgeHandlersIfNeeded()
        }
    }

    /// Configures the Swift tool execution and approval callbacks on the bridge.
    private func installBridgeHandlersIfNeeded() async {
        guard !handlersInstalled else { return }
        handlersInstalled = true
        await bridge.setToolExecutionHandler { @Sendable request in
            await GoogleCloudSDKRuntime.shared.executeSwiftTool(request: request)
        }
        await bridge.setApprovalHandler { @Sendable request in
            await GoogleCloudSDKRuntime.shared.approveBuiltinTool(request: request)
        }
    }

    /// Pre-warms the Antigravity bridge process and IPC transport in the background
    /// to ensure instantaneous first-turn execution without bridge launch delay.
    public func prewarm() {
        guard !isRunning, !isStarting else { return }
        Task { @MainActor in
            _ = try? await self.start()
        }
    }

    /// Validates, checks permissions, and executes a SwiftCode tool for Antigravity.
    private func executeSwiftTool(request: GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?) {
        let toolRegistry = AssistManager.shared.registry
        let toolName = request.toolName
        let args = request.arguments
        let callId = request.callId ?? request.requestId

        // Instantly notify AssistManager that a tool has started execution
        AssistManager.shared.reportToolStarted(
            callId: callId,
            toolName: toolName,
            arguments: args
        )

        guard let tool = toolRegistry.getTool(toolName) else {
            let errorMsg = "Tool '\(toolName)' is not registered in SwiftCode"
            AssistManager.shared.reportToolFailed(
                callId: callId,
                toolName: toolName,
                error: errorMsg,
                arguments: args
            )
            return (false, nil, errorMsg)
        }

        // Validate arguments
        let validation = toolRegistry.validate(toolId: toolName, arguments: args)
        guard validation.isValid else {
            let errorMsg = "Invalid arguments for '\(toolName)': \(validation.issue ?? "Schema mismatch")"
            AssistManager.shared.reportToolFailed(
                callId: callId,
                toolName: toolName,
                error: errorMsg,
                arguments: args
            )
            return (false, nil, errorMsg)
        }

        // Fast execution context retrieval via AssistPromptOptimizer memoization
        let sessionUUID = stableUUID(for: request.sessionId, in: &sessionTaskUUIDs)
        let workspaceRoot = ProjectSessionStore.shared.activeProject?.directoryURL ?? URL(fileURLWithPath: "/")
        let context = AssistPromptOptimizer.shared.executionContext(for: sessionUUID, workspaceRoot: workspaceRoot)

        // Exact tool-id permission check; destructive tools go through the
        // approval UI instead of being silently denied (or allowed).
        if !context.permissions.authorizeOperation(tool.id) {
            let approved = await requestDestructiveApproval(toolId: tool.id, arguments: args)
            if !approved {
                let errorMsg = "The user declined '\(tool.id)'"
                AssistManager.shared.reportToolFailed(
                    callId: callId,
                    toolName: toolName,
                    error: errorMsg,
                    arguments: args
                )
                return (false, nil, errorMsg)
            }
        }

        let effectiveArgs = validation.correctedInput ?? args
        let isCacheable = Self.cacheableToolIDs.contains(tool.id)
        let cacheKey = Self.cacheKey(toolId: tool.id, arguments: effectiveArgs)

        // Result reuse only for pure, argument-determined reads.
        if isCacheable, let cached = toolRegistry.getCachedResult(semanticKey: cacheKey) {
            AssistManager.shared.reportToolCompleted(
                callId: callId,
                toolName: toolName,
                output: cached,
                arguments: args
            )
            return (true, cached, nil)
        }

        do {
            toolRegistry.markUsed(toolName)
            let isTerminalTool = tool.id == "use_terminal"
            let result = try await withTaskCancellationHandler {
                try await tool.execute(input: effectiveArgs, context: context)
            } onCancel: {
                // The bridge cancelled this call (turn cancelled or tool timeout):
                // release a pending approval prompt and stop a running command.
                if isTerminalTool {
                    Task { @MainActor in
                        AssistManager.shared.denyTerminalRequest()
                        AssistManager.shared.cancelTerminalExecution()
                    }
                }
            }

            if Task.isCancelled {
                AssistManager.shared.reportToolFailed(callId: callId, toolName: toolName, error: "Cancelled", arguments: args)
                return (false, nil, "Cancelled")
            }

            // Anything other than a pure read may have changed the workspace.
            if !isCacheable {
                toolRegistry.invalidateReadOnlyCache()
            }

            let payload = Self.modelPayload(for: result)
            if result.success {
                if isCacheable {
                    toolRegistry.setCachedResult(payload, for: cacheKey)
                }
                AssistManager.shared.reportToolCompleted(
                    callId: callId,
                    toolName: toolName,
                    output: payload,
                    arguments: args
                )
                return (true, payload, nil)
            } else {
                let errStr = result.error ?? result.output
                toolRegistry.markError(toolName, error: errStr)
                AssistManager.shared.reportToolFailed(
                    callId: callId,
                    toolName: toolName,
                    error: errStr,
                    arguments: args
                )
                // Give the model the full failure context (stdout/stderr, diagnostics).
                return (false, nil, payload)
            }
        } catch {
            toolRegistry.markError(toolName, error: error.localizedDescription)
            let errStr = "Tool '\(toolName)' execution error: \(error.localizedDescription)"
            AssistManager.shared.reportToolFailed(
                callId: callId,
                toolName: toolName,
                error: errStr,
                arguments: args
            )
            return (false, nil, errStr)
        }
    }

    /// Builds the text returned to the model for a tool result: the summary line
    /// plus every structured field (`data`, diagnostics, diff, changed files), so
    /// the model actually sees file contents, logs, trees, etc.
    static func modelPayload(for result: AssistToolResult) -> String {
        var sections: [String] = []
        let summary = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            sections.append(summary)
        }
        if !result.success, let error = result.error, !error.isEmpty, error != result.output {
            sections.append("Error: \(error)")
        }
        if let data = result.data, !data.isEmpty {
            for key in data.keys.sorted() {
                guard let value = data[key], !value.isEmpty else { continue }
                if key == AssistToolDataKey.diff, result.diff == value { continue }
                sections.append("[\(key)]\n\(value)")
            }
        }
        if let diff = result.diff, !diff.isEmpty {
            sections.append("[diff]\n\(diff)")
        }
        if !result.filesChanged.isEmpty {
            sections.append("[filesChanged]\n" + result.filesChanged.joined(separator: "\n"))
        }
        if !result.diagnostics.isEmpty {
            sections.append("[diagnostics]\n" + result.diagnostics.joined(separator: "\n"))
        }
        if let exitCode = result.exitCode, result.data?["exitCode"] == nil {
            sections.append("[exitCode] \(exitCode)")
        }
        var payload = sections.joined(separator: "\n\n")
        if payload.count > maxToolPayloadCharacters {
            payload = String(payload.prefix(maxToolPayloadCharacters)) + "\n…[truncated \(payload.count - maxToolPayloadCharacters) characters]"
        }
        return payload
    }

    /// Cache key covering the tool id and *all* arguments.
    private static func cacheKey(toolId: String, arguments: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data()
        return "\(toolId)|\(String(decoding: data, as: UTF8.self))"
    }

    private func stableUUID(for key: String, in map: inout [String: UUID]) -> UUID {
        if let uuid = UUID(uuidString: key) { return uuid }
        if let existing = map[key] { return existing }
        let created = UUID()
        map[key] = created
        return created
    }

    /// Asks the user (through the existing approval overlay) to confirm a destructive Swift tool.
    private func requestDestructiveApproval(toolId: String, arguments: [String: Any]) async -> Bool {
        let target = (arguments["path"] as? String)
            ?? (arguments["filePath"] as? String)
            ?? (arguments["directory"] as? String)
            ?? (arguments["dirPath"] as? String)
            ?? Self.compactJSON(arguments)
        let request = TerminalApprovalRequest(
            command: "\(toolId) \(target)",
            workingDirectory: ".",
            explanation: "",
            estimatedImpact: "",
            modifiesRepo: true
        )
        return await AssistManager.shared.requestOperationApproval(request)
    }

    /// Answers `tool.approve` for SDK built-in tools (Cloud toolkit `run_command`).
    fileprivate func approveBuiltinTool(request: GoogleCloudSDKToolApprovalRequest) async -> Bool {
        let args = request.arguments
        let command = (args["CommandLine"] as? String)
            ?? (args["command"] as? String)
            ?? (args["commandLine"] as? String)
            ?? "\(request.toolName) \(Self.compactJSON(args))"
        let cwd = (args["Cwd"] as? String) ?? (args["cwd"] as? String) ?? "."
        let approval = TerminalApprovalRequest(
            command: command,
            workingDirectory: cwd,
            explanation: "",
            estimatedImpact: "",
            modifiesRepo: false
        )
        appendLog("[\(request.sessionId)] Approval requested for \(request.toolName): \(command)")
        return await AssistManager.shared.requestOperationApproval(approval)
    }

    private static func compactJSON(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Verifies availability of the bundled Google Cloud SDK on disk.
    public func auditEnvironment() async {
        if let dir = GoogleCloudSDKProcess.resolveSDKDirectory() {
            self.isAvailable = true
            self.statusDescription = "Installed at \(dir.lastPathComponent)"
            appendLog("Discovered Google Cloud SDK runtime at: \(dir.path)")
        } else {
            self.isAvailable = false
            self.statusDescription = "Runtime not found"
            appendLog("Google Cloud SDK runtime not found in bundle or resources.")
        }
    }

    /// Starts the Antigravity runtime bridge. Concurrent callers share one start.
    public func start() async throws {
        guard !isRunning else { return }
        if let inFlight = startTask {
            try await inFlight.value
            return
        }
        let task = Task { @MainActor in
            try await self.performStart()
        }
        startTask = task
        defer { startTask = nil }
        try await task.value
    }

    private func performStart() async throws {
        await installBridgeHandlersIfNeeded()

        isStarting = true
        statusDescription = "Starting..."
        lastError = nil

        do {
            try await bridge.start()
            self.sdkVersion = await bridge.reportedSDKVersion
            self.bridgePID = await bridge.processIdentifier
            self.isRunning = true
            self.isStarting = false
            self.statusDescription = "Ready (v\(sdkVersion))"
            appendLog("Google Cloud SDK runtime is ready.")

            startEventSubscription()
        } catch {
            self.isStarting = false
            self.isRunning = false
            self.lastError = error.localizedDescription
            self.statusDescription = "Failed: \(error.localizedDescription)"
            appendLog("Failed to start runtime: \(error.localizedDescription)")
            throw error
        }
    }

    /// Ensures the runtime is ready before performing operations.
    public func ensureStarted() async throws {
        if !isRunning {
            try await start()
        }
    }

    /// Stops the Antigravity runtime and terminates the Python subprocess.
    public func stop() async {
        eventSubscriptionTask?.cancel()
        eventSubscriptionTask = nil

        await bridge.stop()
        self.bridgePID = nil
        self.isRunning = false
        self.isStarting = false
        self.activeSessions.removeAll()
        self.activeSessionsCount = 0
        self.statusDescription = "Stopped"
        appendLog("Google Cloud SDK runtime stopped.")
    }

    /// Synchronous teardown for `applicationWillTerminate`, where awaiting the
    /// bridge actor is not possible. Terminates the bridge and its harness children.
    public func terminateForAppExit() {
        eventSubscriptionTask?.cancel()
        eventSubscriptionTask = nil
        if let pid = bridgePID {
            GoogleCloudSDKProcess.terminateSynchronously(pid: pid)
        }
        bridgePID = nil
        isRunning = false
    }

    /// Restarts the runtime.
    public func restart() async throws {
        await stop()
        try await start()
    }

    /// Creates and returns a new native Antigravity session. When the config
    /// carries a `conversationId`, the SDK resumes that persisted conversation.
    public func createSession(id: String = UUID().uuidString, config: GoogleCloudSDKConfiguration? = nil) async throws -> GoogleCloudSDKSession {
        try await ensureStarted()

        let resolvedConfig = config ?? GoogleCloudSDKConfiguration.resolveDefault()
        let resp: GoogleCloudSDKResponse
        if let conversationId = resolvedConfig.conversationId, !conversationId.isEmpty {
            resp = try await bridge.resumeSession(sessionId: id, config: resolvedConfig)
        } else {
            resp = try await bridge.createSession(sessionId: id, config: resolvedConfig)
        }
        let convId = resp.conversationId ?? resolvedConfig.conversationId

        let session = GoogleCloudSDKSession(id: id, config: resolvedConfig, bridge: bridge, conversationId: convId)
        self.activeSessions[id] = session
        self.activeSessionsCount = activeSessions.count

        appendLog("Created session '\(id)' (Conversation ID: \(convId ?? "N/A"))")
        return session
    }

    /// Whether the bridge still knows this session (false after a crash/restart).
    public func isSessionLive(_ id: String) -> Bool {
        isRunning && activeSessions[id] != nil
    }

    /// True for errors meaning the bridge lost the session (restart, crash, close).
    public static func isSessionLostError(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("not found or closed")
            || lower.contains("session not found")
            || lower.contains("-32001")
            || lower.contains("socket is not connected")
            || lower.contains("connection closed")
    }

    /// Retrieves an active session by identifier.
    public func getSession(id: String) -> GoogleCloudSDKSession? {
        activeSessions[id]
    }

    /// Closes an active session.
    public func closeSession(id: String) async {
        if let session = activeSessions.removeValue(forKey: id) {
            try? await session.close()
            self.activeSessionsCount = activeSessions.count
            appendLog("Closed session '\(id)'")
        }
    }

    private func startEventSubscription() {
        eventSubscriptionTask?.cancel()

        let bridge = self.bridge
        eventSubscriptionTask = Task { @MainActor [weak self] in
            let stream = await bridge.subscribeEvents()
            for await event in stream {
                self?.handleIncomingEvent(event)
            }
        }
    }

    private func handleIncomingEvent(_ event: GoogleCloudSDKEvent) {
        switch event {
        case .runtimeReady(let ver, let pid):
            self.sdkVersion = ver
            self.statusDescription = "Ready (PID \(pid))"
            appendLog("Antigravity bridge reports ready (v\(ver), PID \(pid))")

        case .runtimeStopped:
            // The bridge exited or the socket dropped: every session it held is gone.
            self.isRunning = false
            self.bridgePID = nil
            self.activeSessions.removeAll()
            self.activeSessionsCount = 0
            self.statusDescription = "Offline"
            appendLog("Antigravity bridge stopped")

        case .agentStarted(let sid, let prompt):
            appendLog("[\(sid)] Agent started turn: \(prompt ?? "")")

        case .agentCompleted(let sid, _, let stopReason, let usage):
            let tokens = usage?.totalTokens ?? 0
            appendLog("[\(sid)] Agent completed turn (Stop: \(stopReason ?? "ok"), Tokens: \(tokens))")

        case .agentFailed(let sid, let err):
            appendLog("[\(sid)] Agent turn error: \(err)")

        case .toolStarted(let tool):
            appendLog("[\(tool.sessionId)] Tool started: \(tool.name)")

        case .toolProgress(let sid, let id, let msg, let chunk, let callId):
            let effectiveId = (callId?.isEmpty == false ? callId : nil) ?? id
            let detail = chunk.map { "\(msg) (chunk: \($0))" } ?? msg
            appendLog("[\(sid)] Tool progress (\(effectiveId)): \(detail)")

        case .toolCompleted(let res):
            appendLog("[\(res.sessionId)] Tool completed: \(res.name)")
            // SDK built-in tools (Cloud toolkit) mutate files outside the Swift
            // tool path; drop cached reads after anything that is not a pure read.
            let readOnlyBuiltins: Set<String> = ["view_file", "list_directory", "search_directory", "find_file", "grep_search", "codebase_search"]
            if !readOnlyBuiltins.contains(res.name) && !Self.cacheableToolIDs.contains(res.name) {
                AssistManager.shared.registry.invalidateReadOnlyCache()
            }

        case .toolFailed(let sid, let id, let name, let err):
            appendLog("[\(sid)] Tool failed: \(name) (\(id)): \(err)")

        case .workerStarted(let sid, let workerId, let name, let args):
            appendLog("[\(sid)] Worker \(name) (\(workerId)) started with args: \(args)")
            let wID = stableUUID(for: workerId, in: &workerUUIDs)
            workerNames[workerId] = name
            let worker = Worker(
                id: wID,
                name: name,
                scope: name,
                task: args,
                status: .working,
                parentTaskID: stableUUID(for: sid, in: &sessionTaskUUIDs)
            )
            WorkerRuntimeState.shared.register(worker: worker)

            let wEvent = WorkerEvent(
                workerID: wID,
                type: .workerStarted,
                title: name,
                details: args,
                metadata: ["sessionId": sid, "workerId": workerId]
            )
            WorkerEventBus.shared.publish(wEvent)

        case .workerProgress(let sid, let workerId, let progress):
            appendLog("[\(sid)] Worker \(workerId) progress: \(progress)")
            let wID = stableUUID(for: workerId, in: &workerUUIDs)
            WorkerRuntimeState.shared.updateProgress(id: wID, progress: WorkerProgress(narrative: progress, currentAction: progress))

            let wEvent = WorkerEvent(
                workerID: wID,
                type: .workerProgressUpdated,
                title: workerNames[workerId] ?? workerId,
                details: progress,
                metadata: ["sessionId": sid, "workerId": workerId]
            )
            WorkerEventBus.shared.publish(wEvent)

        case .workerCompleted(let sid, let workerId, let result):
            appendLog("[\(sid)] Worker \(workerId) completed: \(result)")
            let wID = stableUUID(for: workerId, in: &workerUUIDs)
            WorkerRuntimeState.shared.transitionWorker(id: wID, to: .completed, reason: result)

            let wEvent = WorkerEvent(
                workerID: wID,
                type: .workerCompleted,
                title: workerNames[workerId] ?? workerId,
                details: result,
                metadata: ["sessionId": sid, "workerId": workerId]
            )
            WorkerEventBus.shared.publish(wEvent)
            workerNames.removeValue(forKey: workerId)
            workerUUIDs.removeValue(forKey: workerId)

        case .workerFailed(let sid, let workerId, let err):
            appendLog("[\(sid)] Worker \(workerId) failed: \(err)")
            let wID = stableUUID(for: workerId, in: &workerUUIDs)
            WorkerRuntimeState.shared.transitionWorker(id: wID, to: .failed, reason: err)

            let wEvent = WorkerEvent(
                workerID: wID,
                type: .workerFailed,
                title: workerNames[workerId] ?? workerId,
                details: err,
                metadata: ["sessionId": sid, "workerId": workerId]
            )
            WorkerEventBus.shared.publish(wEvent)
            workerNames.removeValue(forKey: workerId)
            workerUUIDs.removeValue(forKey: workerId)

        case .error(let msg):
            self.lastError = msg
            appendLog("[Error] \(msg)")

        default:
            break
        }
    }

    public func appendLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logLine = "[\(timestamp)] \(message)"
        logger.log("\(logLine)")
        liveLogs.append(logLine)
        if liveLogs.count > 500 {
            liveLogs.removeFirst(liveLogs.count - 500)
        }
    }
}
