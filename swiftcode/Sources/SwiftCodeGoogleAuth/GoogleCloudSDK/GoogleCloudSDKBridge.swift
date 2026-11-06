//
//  GoogleCloudSDKBridge.swift
//  SwiftCode
//
//  Bridge actor coordinating the Python subprocess and structured IPC transport.
//
//  Ported from Legacy (Dylan's own code; direct port authorised
//  under MIT):
//    SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKBridge.swift
//
//  Adaptations for the destination:
//  - Legacy took `GoogleCloudSDKConfiguration` (skipped: its
//    replacement already exists in SwiftCodeAssistant as
//    `SDKSessionConfiguration` — see AssistSDKModelSelection.swift).
//    `createSession` / `resumeSession` now take
//    `SDKSessionConfiguration` and build the `session.create` /
//    `session.resume` params from its real fields (model,
//    provider raw value, thinkingLevel, enableSubagents,
//    executionMode, baseURL). Fields Legacy's config carried that
//    `SDKSessionConfiguration` deliberately dropped (Vertex
//    project/location, skillsPaths, workspaces, appDataDir/saveDir,
//    tool table, systemInstructions, serviceTier, subagent depth,
//    LiteRT paths) are NOT sent — see GOOGLE-SWIFT-FRAGMENT.md.
//    The bridge still authenticates from the process environment
//    (GOOGLE_OAUTH_ACCESS_TOKEN injected by GoogleCloudSDKProcess);
//    in `antigravity` execution mode the session params also carry
//    the current OAuth token, as Legacy's `toDictionary()` did,
//    fetched here from `GoogleAccountAuthService` so no secret is
//    ever stored on the configuration value.
//  - Wire protocol unchanged: JSON-RPC 2.0 methods
//    `runtime.start` / `runtime.stop` / `runtime.status`,
//    `session.create` / `session.resume` / `session.close`,
//    `message.send` / `message.cancel` (verified against the
//    staged bridge `main.py` dispatch table).

import Foundation
import os

import SwiftCodeAssistant

private let logger = Logger(subsystem: "com.swiftcode.GoogleCloudSDK", category: "GoogleCloudSDKBridge")

public actor GoogleCloudSDKBridge {
    private let process = GoogleCloudSDKProcess()
    private let transport = GoogleCloudSDKTransport()
    private var isStarted = false
    private var sdkVersion: String = "0.1.20"

    public init() {}

    public var isRunning: Bool {
        get async {
            await process.isRunning
        }
    }

    public var liveLogs: [String] {
        get async {
            await process.liveLogs
        }
    }

    /// Sets the handler closure for incoming tool execution requests (`tool.execute`).
    public func setToolExecutionHandler(_ handler: @escaping @Sendable (GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?)) async {
        await transport.setToolExecutionHandler(handler)
    }

    /// Starts the bridge subprocess and completes the readiness handshake.
    public func start() async throws {
        if isStarted, await isRunning {
            return
        }

        logger.info("Starting Google Cloud SDK / Antigravity bridge...")

        let socketPath = try await process.start()

        do {
            try await transport.connect(to: socketPath, timeout: 15.0)
        } catch {
            await process.stop()
            throw error
        }

        // Perform initial handshake via runtime.start
        let handshakeResult = try await transport.sendRequest(method: "runtime.start", params: [:], timeout: 10.0)
        if let version = handshakeResult.sdkVersion {
            self.sdkVersion = version
        }

        self.isStarted = true
        _ = await process.onTermination { [weak self] exitCode in
            guard let self = self else { return }
            Task {
                await self.handleProcessTerminated(exitCode: exitCode)
            }
        }
        logger.info("Google Cloud SDK bridge started successfully (version: \(self.sdkVersion))")
    }

    private func handleProcessTerminated(exitCode: Int32) async {
        self.isStarted = false
        await transport.emitEvent(.runtimeStopped)
    }

    /// Stops the bridge cleanly.
    public func stop() async {
        if isStarted {
            _ = try? await transport.sendRequest(method: "runtime.stop", params: [:], timeout: 3.0)
        }

        await transport.disconnect()
        await process.stop()
        self.isStarted = false
        logger.info("Google Cloud SDK bridge stopped")
    }

    /// Subscribes to the broadcast event stream from the bridge.
    public func subscribeEvents() async -> AsyncStream<GoogleCloudSDKEvent> {
        await transport.subscribeEvents()
    }

    /// Builds the `session.create` / `session.resume` params for a
    /// session configuration. Only fields `SDKSessionConfiguration`
    /// actually carries are sent; the OAuth token is resolved live
    /// (never stored on the configuration) when the session runs
    /// under Google OAuth.
    private func sessionParams(sessionId: String, config: SDKSessionConfiguration) async -> [String: Any] {
        var params: [String: Any] = [
            "sessionId": sessionId,
            "model": config.model,
            "provider": config.provider.rawValue,
            "enableSubagents": config.enableSubagents,
        ]
        if let thinkingLevel = config.thinkingLevel, !thinkingLevel.isEmpty {
            params["thinkingLevel"] = thinkingLevel
        }
        if let executionMode = config.executionMode, !executionMode.isEmpty {
            params["executionMode"] = executionMode
        }
        if let baseURL = config.baseURL, !baseURL.isEmpty {
            params["baseURL"] = baseURL
        }
        if config.executionMode == "antigravity",
           let oauthToken = await GoogleAccountAuthService.shared.getValidAccessToken(),
           !oauthToken.isEmpty {
            params["oauthToken"] = oauthToken
        }
        return params
    }

    /// Creates an active agent session with Antigravity.
    public func createSession(sessionId: String, config: SDKSessionConfiguration) async throws -> GoogleCloudSDKResponse {
        try await start()
        let params = await sessionParams(sessionId: sessionId, config: config)
        return try await transport.sendRequest(method: "session.create", params: params, timeout: 60.0)
    }

    /// Resumes an existing agent session.
    public func resumeSession(sessionId: String, config: SDKSessionConfiguration) async throws -> GoogleCloudSDKResponse {
        try await start()
        let params = await sessionParams(sessionId: sessionId, config: config)
        return try await transport.sendRequest(method: "session.resume", params: params, timeout: 60.0)
    }

    /// Closes an active agent session.
    public func closeSession(sessionId: String) async throws -> GoogleCloudSDKResponse {
        guard isStarted else { return GoogleCloudSDKResponse() }
        return try await transport.sendRequest(method: "session.close", params: ["sessionId": sessionId], timeout: 10.0)
    }

    /// Dispatches a message to the agent session for turn execution.
    public func sendMessage(sessionId: String, content: String, attachments: [GoogleCloudSDKAttachment] = []) async throws -> GoogleCloudSDKResponse {
        try await start()
        let attachmentsDict = attachments.map { $0.toDictionary() }
        let params: [String: Any] = [
            "sessionId": sessionId,
            "content": content,
            "attachments": attachmentsDict,
        ]
        // message.send only acknowledges that the bridge queued a turn; model
        // inference and tool execution continue on the event stream. A long
        // RPC timeout here hides a dead bridge and can leave Assist appearing
        // stuck long before the turn-level inactivity watchdog runs.
        return try await transport.sendRequest(method: "message.send", params: params, timeout: 30.0)
    }

    /// Cancels active turn execution in an agent session.
    public func cancelMessage(sessionId: String) async throws -> GoogleCloudSDKResponse {
        guard isStarted else { return GoogleCloudSDKResponse() }
        return try await transport.sendRequest(method: "message.cancel", params: ["sessionId": sessionId], timeout: 5.0)
    }

    /// Queries the runtime health and active session count.
    public func getStatus() async throws -> GoogleCloudSDKResponse {
        try await start()
        return try await transport.sendRequest(method: "runtime.status", params: [:], timeout: 5.0)
    }
}
