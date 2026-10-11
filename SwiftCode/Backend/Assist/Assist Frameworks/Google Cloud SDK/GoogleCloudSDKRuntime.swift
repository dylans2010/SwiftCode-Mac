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
    public var sdkVersion: String = "0.1.20"
    public var activeSessionsCount: Int = 0
    public var liveLogs: [String] = []
    public var lastError: String? = nil
    public var statusDescription: String = "Offline"

    private let bridge = GoogleCloudSDKBridge()
    private var activeSessions: [String: GoogleCloudSDKSession] = [:]
    private var eventSubscriptionTask: Task<Void, Never>?
    private var workerIdToUUID: [String: UUID] = [:]

    private init() {
        if let dir = GoogleCloudSDKProcess.resolveSDKDirectory() {
            self.isAvailable = true
            self.statusDescription = "Installed at \(dir.lastPathComponent)"
        }
        Task { @MainActor in
            await self.auditEnvironment()
            await self.setupToolExecutionBridge()
        }
    }

    /// Prewarms the runtime environment in the background.
    public func prewarm() {
        Task { @MainActor in
            _ = try? await self.ensureStarted()
        }
    }

    private func resolvedWorkerUUID(for workerId: String) -> UUID {
        if let existing = workerIdToUUID[workerId] {
            return existing
        }
        let id = UUID(uuidString: workerId) ?? UUID()
        workerIdToUUID[workerId] = id
        return id
    }

    /// Configures the Swift tool execution bridge callback on the bridge.
    private func setupToolExecutionBridge() async {
        await bridge.setToolExecutionHandler { @Sendable request in
            await GoogleCloudSDKRuntime.shared.executeSwiftTool(request: request)
        }
    }

    /// Validates, checks permissions, and executes a SwiftCode tool for Antigravity.
    private func executeSwiftTool(request: GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?) {
        let toolRegistry = AssistManager.shared.registry
        let toolName = request.toolName
        let args = request.arguments
        let callId = request.requestId

        // Instantly notify AssistManager that a tool has started execution on the main actor
        await MainActor.run {
            AssistManager.shared.reportToolStarted(
                callId: callId,
                toolName: toolName,
                arguments: args
            )
        }

        guard let tool = toolRegistry.getTool(toolName) else {
            let errorMsg = "Tool '\(toolName)' is not registered in SwiftCode"
            await MainActor.run {
                AssistManager.shared.reportToolFailed(
                    callId: callId,
                    toolName: toolName,
                    error: errorMsg,
                    arguments: args
                )
            }
            return (false, nil, errorMsg)
        }

        // Validate arguments
        let validation = toolRegistry.validate(toolId: toolName, arguments: args)
        guard validation.isValid else {
            let errorMsg = "Invalid arguments for '\(toolName)': \(validation.issue ?? "Schema mismatch")"
            await MainActor.run {
                AssistManager.shared.reportToolFailed(
                    callId: callId,
                    toolName: toolName,
                    error: errorMsg,
                    arguments: args
                )
            }
            return (false, nil, errorMsg)
        }

        // Ensure workspace root is valid; fail closed if no active project
        guard let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL else {
            let errorMsg = "Execution failed: No active workspace project selected."
            await MainActor.run {
                AssistManager.shared.reportToolFailed(
                    callId: callId,
                    toolName: toolName,
                    error: errorMsg,
                    arguments: args
                )
            }
            return (false, nil, errorMsg)
        }

        // Build execution context
        let context = AssistContextBuilder(
            logger: AssistManager.shared.logger,
            permissions: AssistPermissionsManager(),
            memory: AssistMemoryGraph(),
            fileSystem: AssistFileSystem(workspaceRoot: projectURL),
            git: AssistGitManager(project: ProjectSessionStore.shared.activeProject)
        ).buildContext(sessionId: UUID(uuidString: request.sessionId) ?? UUID())

        // Evaluate permissions via AssistPermissionsManager
        let permissions = AssistPermissionsManager()
        if !permissions.authorizeOperation(toolName) {
            let errorMsg = "Permission denied for tool '\(toolName)'"
            await MainActor.run {
                AssistManager.shared.reportToolFailed(
                    callId: callId,
                    toolName: toolName,
                    error: errorMsg,
                    arguments: args
                )
            }
            return (false, nil, errorMsg)
        }

        let meta = AssistToolRouter.shared.metadata(for: tool)
        let semKey = await MainActor.run {
            AssistEventNormalizer.shared.computeSemanticKey(toolName: toolName, arguments: args)
        }

        // Tools that produce interactive, dynamic, or time-sensitive results must never be cached
        let nonCacheableTools: Set<String> = [
            "plan_ask_user", "plan-askuser", "execution_plan", "plan_task",
            "breakdown_task", "project_diff", "diff", "env_capture_logs",
            "log_capture", "code_review", "safe_validate_changes", "validate_changes",
            "test_runner", "run_tests", "compiler_diagnostics_engine", "compiler_diagnostics",
            "runtime_diagnostics_engine", "runtime_diagnostics", "use_terminal", "run_command"
        ]
        let isCacheEligible = meta.isReadOnly && !nonCacheableTools.contains(toolName.lowercased())

        // Runtime Result Reuse / Idempotency Check for Read-Only tools
        if isCacheEligible {
            let cached: String? = await MainActor.run {
                toolRegistry.getCachedResult(semanticKey: semKey)
            }
            if let cached = cached {
                await MainActor.run {
                    AssistManager.shared.reportToolCompleted(
                        callId: callId,
                        toolName: toolName,
                        output: cached,
                        arguments: args
                    )
                }
                return (true, cached, nil)
            }
        }

        do {
            toolRegistry.markUsed(toolName)
            let effectiveArgs = validation.correctedInput ?? args
            let result = try await tool.execute(input: effectiveArgs, context: context)
            if result.success {
                // Ensure model and UI receive the actual payload contents (e.g. file content, directory trees, structured data)
                let fullPayload: String
                if let data = result.data, !data.isEmpty {
                    if let content = data["content"], !content.isEmpty {
                        fullPayload = content
                    } else if let tree = data["tree"], !tree.isEmpty {
                        fullPayload = tree
                    } else if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]),
                              let jsonStr = String(data: jsonData, encoding: .utf8) {
                        fullPayload = result.output.isEmpty ? jsonStr : "\(result.output)\n\n\(jsonStr)"
                    } else {
                        let formatted = data.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                        fullPayload = result.output.isEmpty ? formatted : "\(result.output)\n\n\(formatted)"
                    }
                } else {
                    fullPayload = result.output
                }

                await MainActor.run {
                    let isTerminalOrMutation = meta.isMutating || toolName.lowercased() == "use_terminal" || toolName.lowercased() == "run_command"
                    if isTerminalOrMutation {
                        toolRegistry.invalidateReadOnlyCache()
                    } else if isCacheEligible {
                        toolRegistry.setCachedResult(fullPayload, for: semKey)
                    }

                    AssistManager.shared.reportToolCompleted(
                        callId: callId,
                        toolName: toolName,
                        output: fullPayload,
                        arguments: args
                    )
                }
                return (true, fullPayload, nil)
            } else {
                let errStr = result.error ?? result.output
                toolRegistry.markError(toolName, error: errStr)
                await MainActor.run {
                    AssistManager.shared.reportToolFailed(
                        callId: callId,
                        toolName: toolName,
                        error: errStr,
                        arguments: args
                    )
                }
                return (false, nil, errStr)
            }
        } catch {
            toolRegistry.markError(toolName, error: error.localizedDescription)
            let errStr = "Tool '\(toolName)' execution error: \(error.localizedDescription)"
            await MainActor.run {
                AssistManager.shared.reportToolFailed(
                    callId: callId,
                    toolName: toolName,
                    error: errStr,
                    arguments: args
                )
            }
            return (false, nil, errStr)
        }
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

    /// Starts the Antigravity runtime bridge.
    public func start() async throws {
        guard !isRunning else { return }

        isStarting = true
        statusDescription = "Starting..."
        lastError = nil

        do {
            try await bridge.start()
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
        self.isRunning = false
        self.isStarting = false
        self.activeSessions.removeAll()
        self.activeSessionsCount = 0
        self.statusDescription = "Stopped"
        appendLog("Google Cloud SDK runtime stopped.")
    }

    /// Restarts the runtime.
    public func restart() async throws {
        await stop()
        try await start()
    }

    /// Creates and returns a new native Antigravity session.
    public func createSession(id: String = UUID().uuidString, config: GoogleCloudSDKConfiguration? = nil) async throws -> GoogleCloudSDKSession {
        try await ensureStarted()

        let resolvedConfig = config ?? GoogleCloudSDKConfiguration.resolveDefault()
        let resp = try await bridge.createSession(sessionId: id, config: resolvedConfig)
        let convId = resp.conversationId

        let session = GoogleCloudSDKSession(id: id, config: resolvedConfig, bridge: bridge, conversationId: convId)
        self.activeSessions[id] = session
        self.activeSessionsCount = activeSessions.count

        appendLog("Created session '\(id)' (Conversation ID: \(convId ?? "N/A"))")
        return session
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
            self.isRunning = false
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

        case .toolCompleted(let res):
            appendLog("[\(res.sessionId)] Tool completed: \(res.name)")

        case .toolFailed(let id, let name, let err):
            appendLog("[Tool \(name) (\(id))] Tool failed: \(err)")

        case .workerStarted(let sid, let workerId, let name, let args):
            appendLog("[\(sid)] Worker \(name) (\(workerId)) started with args: \(args)")
            let wID = resolvedWorkerUUID(for: workerId)
            let worker = Worker(
                id: wID,
                name: name,
                scope: name,
                task: args,
                status: .working,
                parentTaskID: UUID()
            )
            WorkerRuntimeState.shared.register(worker: worker)

            let wEvent = WorkerEvent(
                workerID: wID,
                type: .workerStarted,
                title: name,
                details: args,
                metadata: ["sessionId": sid]
            )
            WorkerEventBus.shared.publish(wEvent)

        case .workerProgress(let sid, let workerId, let progress):
            appendLog("[\(sid)] Worker \(workerId) progress: \(progress)")
            let wID = resolvedWorkerUUID(for: workerId)
            WorkerRuntimeState.shared.updateProgress(id: wID, progress: WorkerProgress(narrative: progress, currentAction: progress))

            let wEvent = WorkerEvent(
                workerID: wID,
                type: .workerProgressUpdated,
                title: "Subagent Progress",
                details: progress,
                metadata: ["sessionId": sid]
            )
            WorkerEventBus.shared.publish(wEvent)

        case .workerCompleted(let sid, let workerId, let result):
            appendLog("[\(sid)] Worker \(workerId) completed: \(result)")
            let wID = resolvedWorkerUUID(for: workerId)
            WorkerRuntimeState.shared.transitionWorker(id: wID, to: .completed, reason: "Completed")

            let wEvent = WorkerEvent(
                workerID: wID,
                type: .workerCompleted,
                title: "Subagent Completed",
                details: result,
                metadata: ["sessionId": sid]
            )
            WorkerEventBus.shared.publish(wEvent)

        case .workerFailed(let sid, let workerId, let err):
            appendLog("[\(sid)] Worker \(workerId) failed: \(err)")
            let wID = resolvedWorkerUUID(for: workerId)
            WorkerRuntimeState.shared.transitionWorker(id: wID, to: .failed, reason: err)

            let wEvent = WorkerEvent(
                workerID: wID,
                type: .workerFailed,
                title: "Subagent Failed",
                details: err,
                metadata: ["sessionId": sid]
            )
            WorkerEventBus.shared.publish(wEvent)

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
