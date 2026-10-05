//
//  GoogleCloudSDKBridge.swift
//  SwiftCode
//
//  Bridge actor coordinating the Python subprocess and structured IPC transport.
//

import Foundation
import os

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
        if let version = handshakeResult["sdkVersion"] as? String {
            self.sdkVersion = version
        }

        self.isStarted = true
        logger.info("Google Cloud SDK bridge started successfully (version: \(self.sdkVersion))")
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

    /// Creates an active agent session with Antigravity.
    public func createSession(sessionId: String, config: GoogleCloudSDKConfiguration) async throws -> [String: Any] {
        try await start()
        var params = config.toDictionary()
        params["sessionId"] = sessionId
        return try await transport.sendRequest(method: "session.create", params: params, timeout: 30.0)
    }

    /// Resumes an existing agent session.
    public func resumeSession(sessionId: String, config: GoogleCloudSDKConfiguration) async throws -> [String: Any] {
        try await start()
        var params = config.toDictionary()
        params["sessionId"] = sessionId
        return try await transport.sendRequest(method: "session.resume", params: params, timeout: 30.0)
    }

    /// Closes an active agent session.
    public func closeSession(sessionId: String) async throws -> [String: Any] {
        guard isStarted else { return [:] }
        return try await transport.sendRequest(method: "session.close", params: ["sessionId": sessionId], timeout: 10.0)
    }

    /// Dispatches a message to the agent session for turn execution.
    public func sendMessage(sessionId: String, content: String, attachments: [GoogleCloudSDKAttachment] = []) async throws -> [String: Any] {
        try await start()
        let attachmentsDict = attachments.map { $0.toDictionary() }
        let params: [String: Any] = [
            "sessionId": sessionId,
            "content": content,
            "attachments": attachmentsDict,
        ]
        return try await transport.sendRequest(method: "message.send", params: params, timeout: 120.0)
    }

    /// Cancels active turn execution in an agent session.
    public func cancelMessage(sessionId: String) async throws -> [String: Any] {
        guard isStarted else { return [:] }
        return try await transport.sendRequest(method: "message.cancel", params: ["sessionId": sessionId], timeout: 5.0)
    }

    /// Queries the runtime health and active session count.
    public func getStatus() async throws -> [String: Any] {
        try await start()
        return try await transport.sendRequest(method: "runtime.status", params: [:], timeout: 5.0)
    }
}
