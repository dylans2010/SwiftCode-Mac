// Moved from SwiftCodeGoogleAuth by R-GOOGLE-MOVE (W-V2 decision 1, 2026-11-06):
// SwiftCodeAssistant cannot depend on SwiftCodeGoogleAuth, so the types AssistManager
// needs live here. Still in SwiftCodeGoogleAuth (follow-up move): GoogleCloudSDKBridge, GoogleCloudSDKProcess,
// GoogleCloudSDKEvent, GoogleCloudSDKToolExecutionRequest (and transitively GoogleCloudSDKTransport,
// GoogleCloudSDKMessage, GoogleCloudSDKError).

//
//  GoogleCloudSDKRuntime.swift
//  SwiftCode
//
//  Primary native entry point and high-level manager for the Google Cloud SDK / Antigravity runtime.
//
//  Ported from Legacy (Dylan's own code; direct port authorised
//  under MIT):
//    SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKRuntime.swift
//
//  Adaptations for the destination — read before wiring this up:
//  - Configuration is `SDKSessionConfiguration` from
//    SwiftCodeAssistant (the destination replacement for Legacy's
//    `GoogleCloudSDKConfiguration`). `createSession` takes the
//    config as a required parameter: Legacy's
//    `GoogleCloudSDKConfiguration.resolveDefault()` has no
//    destination equivalent (it depended on `AppSettings`,
//    `AssistModelRouter.currentRuntimeModel`,
//    `AgentModelAdapter`, `AssistSystemPromptSections`, and the
//    Assist tool registry, none of which exist in the
//    destination). Callers build the config with
//    `SDKSessionConfigurationBuilder.build(for:...)` from a
//    selected candidate model. Fields Legacy's config carried
//    that `SDKSessionConfiguration` dropped (systemInstructions,
//    skillsPaths, workspaces, appDataDir/saveDir, tool table,
//    serviceTier, Vertex project/location, LiteRT paths) are not
//    sent to the bridge — see GOOGLE-SWIFT-FRAGMENT.md.
//  - Tool execution: Legacy executed bridge `tool.execute`
//    requests directly against the Assist tool registry
//    (`AssistManager`, `AssistContextBuilder`,
//    `AssistPermissionsManager`, `AssistFileSystem`,
//    `AssistGitManager`, `AssistToolRouter`,
//    `AssistEventNormalizer`, `AssistToolResultFormatter`, the
//    read-only result cache) — none of which exists in the
//    destination. That whole execution path is NOT re-implemented
//    here and NOT faked: the runtime exposes a pluggable
//    `toolExecutionHandler` (same signature the bridge already
//    uses). The host installs a real handler via
//    `setToolExecutionHandler(_:)`; until it does, a bridge tool
//    request fails honestly with "No tool execution handler
//    registered in Swift" instead of pretending to execute.
//    The 64 KiB transport payload cap still applies in
//    GoogleCloudSDKTransport.
//  - Worker (subagent) events: Legacy registered/published them
//    through `Worker`, `WorkerRuntimeState`, and `WorkerEventBus`
//    — none exists in the destination. Worker events are logged
//    (same log lines as Legacy) and forwarded on the event
//    stream, but no worker state is tracked or published. The
//    `workerIdToUUID` map is therefore gone.
//  - Auth recovery is preserved: agent-failure and bridge-error
//    events naming 401/403/unauthenticated/permission_denied/
//    expired/scope still trigger
//    `GoogleAccountAuthService.shared.verifyRuntimeSession()`,
//    which exists in this target.
//  - `ProjectSessionStore` (workspace root for tool execution)
//    does not exist in the destination and is not referenced.

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

    /// Host-installed handler for bridge `tool.execute` requests.
    /// Nil until the host installs a real tool executor via
    /// `setToolExecutionHandler(_:)` — see the file header. Never a
    /// fake executor: with no handler, tool requests fail honestly.
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

    /// Prewarms the runtime environment in the background.
    public func prewarm() {
        Task { @MainActor in
            _ = try? await self.ensureStarted()
        }
    }

    /// Installs the host's tool executor for bridge `tool.execute`
    /// requests and forwards it to the bridge transport.
    public func setToolExecutionHandler(_ handler: @escaping @Sendable (GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?)) async {
        self.toolExecutionHandler = handler
        await bridge.setToolExecutionHandler(handler)
    }

    /// Configures the Swift tool execution bridge callback on the bridge.
    /// The callback delegates to the host-installed handler; with no
    /// handler installed it fails honestly rather than executing
    /// anything.
    private func setupToolExecutionBridge() async {
        await bridge.setToolExecutionHandler { @Sendable request in
            await GoogleCloudSDKRuntime.shared.executeSwiftTool(request: request)
        }
    }

    /// Dispatches a bridge tool request to the host-installed
    /// handler, or fails honestly when none is installed.
    private func executeSwiftTool(request: GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?) {
        guard let handler = toolExecutionHandler else {
            return (false, nil, "No tool execution handler registered in Swift")
        }
        return await handler(request)
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
    /// The config is required: there is no destination equivalent
    /// of Legacy's `GoogleCloudSDKConfiguration.resolveDefault()`
    /// (see the file header).
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
