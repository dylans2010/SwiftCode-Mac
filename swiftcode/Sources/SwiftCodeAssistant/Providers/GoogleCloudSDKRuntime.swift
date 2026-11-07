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

    public var toolExecutionHandler: (@Sendable (GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?))?

    private let bridge = GoogleCloudSDKBridge()
    private var activeSessions: [String: GoogleCloudSDKSession] = [:]
    private var eventSubscriptionTask: Task<Void, Never>?

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

    public func prewarm() {
        Task { @MainActor in
            _ = try? await self.ensureStarted()
        }
    }

    public func setToolExecutionHandler(_ handler: @escaping @Sendable (GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?)) async {
        self.toolExecutionHandler = handler
        await bridge.setToolExecutionHandler(handler)
    }

    private func setupToolExecutionBridge() async {
        await bridge.setToolExecutionHandler { @Sendable request in
            await GoogleCloudSDKRuntime.shared.executeSwiftTool(request: request)
        }
    }

    private func executeSwiftTool(request: GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?) {
        guard let handler = toolExecutionHandler else {
            return (false, nil, "No tool execution handler registered in Swift")
        }
        return await handler(request)
    }

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

    public func ensureStarted() async throws {
        if !isRunning {
            try await start()
        }
    }

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

    public func restart() async throws {
        await stop()
        try await start()
    }

    public func createSession(id: String = UUID().uuidString, config: SDKSessionConfiguration) async throws -> GoogleCloudSDKSession {
        try await ensureStarted()

        let resp = try await bridge.createSession(sessionId: id, config: config)
        let convId = resp.conversationId

        let session = GoogleCloudSDKSession(id: id, config: config, bridge: bridge, conversationId: convId)
        self.activeSessions[id] = session
        self.activeSessionsCount = activeSessions.count

        appendLog("Created session '\(id)' (Conversation ID: \(convId ?? "N/A"))")
        return session
    }

    public func getSession(id: String) -> GoogleCloudSDKSession? {
        activeSessions[id]
    }

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
            let lower = err.lowercased()
            if lower.contains("401") || lower.contains("403") || lower.contains("unauthenticated") || lower.contains("permission_denied") || lower.contains("expired") || lower.contains("scope") {
                Task { @MainActor in
                    _ = await GoogleAccountAuthService.shared.verifyRuntimeSession()
                }
            }

        case .toolStarted(let tool):
            appendLog("[\(tool.sessionId)] Tool started: \(tool.name)")

        case .toolCompleted(let res):
            appendLog("[\(res.sessionId)] Tool completed: \(res.name)")

        case .toolFailed(let id, let name, let err):
            appendLog("[Tool \(name) (\(id))] Tool failed: \(err)")

        case .workerStarted(let sid, let workerId, let name, let args):
            appendLog("[\(sid)] Worker \(name) (\(workerId)) started with args: \(args)")

        case .workerProgress(let sid, let workerId, let progress):
            appendLog("[\(sid)] Worker \(workerId) progress: \(progress)")

        case .workerCompleted(let sid, let workerId, let result):
            appendLog("[\(sid)] Worker \(workerId) completed: \(result)")

        case .workerFailed(let sid, let workerId, let err):
            appendLog("[\(sid)] Worker \(workerId) failed: \(err)")

        case .error(let msg):
            self.lastError = msg
            appendLog("[Error] \(msg)")
            let lower = msg.lowercased()
            if lower.contains("401") || lower.contains("403") || lower.contains("unauthenticated") || lower.contains("permission_denied") || lower.contains("expired") || lower.contains("scope") {
                Task { @MainActor in
                    _ = await GoogleAccountAuthService.shared.verifyRuntimeSession()
                }
            }

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
