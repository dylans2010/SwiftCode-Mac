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

    private init() {
        Task { @MainActor in
            await self.auditEnvironment()
            await self.setupToolExecutionBridge()
        }
    }

    /// Configures the Swift tool execution bridge callback on the bridge.
    private func setupToolExecutionBridge() async {
        await bridge.setToolExecutionHandler { @Sendable request in
            await GoogleCloudSDKRuntime.shared.executeSwiftTool(request: request)
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
        let sessionUUID = UUID(uuidString: request.sessionId) ?? UUID()
        let workspaceRoot = ProjectSessionStore.shared.activeProject?.directoryURL ?? URL(fileURLWithPath: "/")
        let context = AssistPromptOptimizer.shared.executionContext(for: sessionUUID, workspaceRoot: workspaceRoot)

        // Evaluate permissions via context
        if !context.permissions.authorizeOperation(toolName) {
            let errorMsg = "Permission denied for tool '\(toolName)'"
            AssistManager.shared.reportToolFailed(
                callId: callId,
                toolName: toolName,
                error: errorMsg,
                arguments: args
            )
            return (false, nil, errorMsg)
        }

        let meta = AssistToolRouter.shared.metadata(for: tool)
        let semKey = AssistEventNormalizer.shared.computeSemanticKey(toolName: toolName, arguments: args)

        // Runtime Result Reuse / Idempotency Check for Read-Only tools
        if meta.isReadOnly {
            if let cached = toolRegistry.getCachedResult(semanticKey: semKey) {
                AssistManager.shared.reportToolCompleted(
                    callId: callId,
                    toolName: toolName,
                    output: cached,
                    arguments: args
                )
                return (true, cached, nil)
            }
        }

        do {
            toolRegistry.markUsed(toolName)
            let effectiveArgs = validation.correctedInput ?? args
            let result = try await tool.execute(input: effectiveArgs, context: context)

            if result.success {
                if meta.isMutating {
                    toolRegistry.invalidateReadOnlyCache()
                } else if meta.isReadOnly {
                    toolRegistry.setCachedResult(result.output, for: semKey)
                }

                AssistManager.shared.reportToolCompleted(
                    callId: callId,
                    toolName: toolName,
                    output: result.output,
                    arguments: args
                )
                return (true, result.output, nil)
            } else {
                let errStr = result.error ?? result.output
                toolRegistry.markError(toolName, error: errStr)
                AssistManager.shared.reportToolFailed(
                    callId: callId,
                    toolName: toolName,
                    error: errStr,
                    arguments: args
                )
                return (false, nil, errStr)
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

        case .toolProgress(let sid, let id, let msg, let chunk, let callId):
            let effectiveId = (callId?.isEmpty == false ? callId : nil) ?? id
            let detail = chunk.map { "\(msg) (chunk: \($0))" } ?? msg
            appendLog("[\(sid)] Tool progress (\(effectiveId)): \(detail)")

        case .toolCompleted(let res):
            appendLog("[\(res.sessionId)] Tool completed: \(res.name)")

        case .toolFailed(let sid, let id, let name, let err):
            appendLog("[\(sid)] Tool failed: \(name) (\(id)): \(err)")

        case .workerStarted(let sid, let workerId, let name, let args):
            appendLog("[\(sid)] Worker \(name) (\(workerId)) started with args: \(args)")
            let wID = UUID(uuidString: workerId) ?? UUID()
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
            let wID = UUID(uuidString: workerId) ?? UUID()
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
            let wID = UUID(uuidString: workerId) ?? UUID()
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
            let wID = UUID(uuidString: workerId) ?? UUID()
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
