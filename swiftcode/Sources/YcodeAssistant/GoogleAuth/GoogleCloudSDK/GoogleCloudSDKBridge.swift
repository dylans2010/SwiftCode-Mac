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

    public func setToolExecutionHandler(_ handler: @escaping @Sendable (GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?)) async {
        await transport.setToolExecutionHandler(handler)
    }

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

    public func stop() async {
        if isStarted {
            _ = try? await transport.sendRequest(method: "runtime.stop", params: [:], timeout: 3.0)
        }

        await transport.disconnect()
        await process.stop()
        self.isStarted = false
        logger.info("Google Cloud SDK bridge stopped")
    }

    public func subscribeEvents() async -> AsyncStream<GoogleCloudSDKEvent> {
        await transport.subscribeEvents()
    }

    private func sessionParamsData(sessionId: String, config: SDKSessionConfiguration) async -> Data {
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
        return (try? JSONSerialization.data(withJSONObject: params)) ?? Data("{}".utf8)
    }

    public func createSession(sessionId: String, config: SDKSessionConfiguration) async throws -> GoogleCloudSDKResponse {
        try await start()
        let data = await sessionParamsData(sessionId: sessionId, config: config)
        return try await transport.sendRequest(method: "session.create", paramsData: data, timeout: 60.0)
    }

    public func createSession(sessionId: String, config: GoogleCloudSDKConfiguration) async throws -> GoogleCloudSDKResponse {
        let providerKind: ProviderKind = (config.provider == "anthropic" || config.provider == "claude") ? .anthropic : .gemini
        let sessionConfig = SDKSessionConfiguration(
            model: config.model,
            provider: providerKind,
            thinkingLevel: config.thinkingLevel,
            enableSubagents: config.enableSubagents,
            executionMode: config.executionMode,
            hasAPIKey: config.apiKey != nil && !(config.apiKey?.isEmpty ?? true),
            isOAuthAuthenticated: config.oauthToken != nil && !(config.oauthToken?.isEmpty ?? true),
            baseURL: config.baseURL
        )
        return try await createSession(sessionId: sessionId, config: sessionConfig)
    }

    public func resumeSession(sessionId: String, config: SDKSessionConfiguration) async throws -> GoogleCloudSDKResponse {
        try await start()
        let data = await sessionParamsData(sessionId: sessionId, config: config)
        return try await transport.sendRequest(method: "session.resume", paramsData: data, timeout: 60.0)
    }

    public func closeSession(sessionId: String) async throws -> GoogleCloudSDKResponse {
        guard isStarted else { return GoogleCloudSDKResponse() }
        let paramsData = (try? JSONSerialization.data(withJSONObject: ["sessionId": sessionId])) ?? Data("{}".utf8)
        return try await transport.sendRequest(method: "session.close", paramsData: paramsData, timeout: 10.0)
    }

    public func sendMessage(sessionId: String, content: String, attachments: [GoogleCloudSDKAttachment] = []) async throws -> GoogleCloudSDKResponse {
        try await start()
        let attachmentsDict = attachments.map { $0.toDictionary() }
        let params: [String: Any] = [
            "sessionId": sessionId,
            "content": content,
            "attachments": attachmentsDict,
        ]
        let paramsData = (try? JSONSerialization.data(withJSONObject: params)) ?? Data("{}".utf8)
        return try await transport.sendRequest(method: "message.send", paramsData: paramsData, timeout: 30.0)
    }

    public func cancelMessage(sessionId: String) async throws -> GoogleCloudSDKResponse {
        guard isStarted else { return GoogleCloudSDKResponse() }
        let paramsData = (try? JSONSerialization.data(withJSONObject: ["sessionId": sessionId])) ?? Data("{}".utf8)
        return try await transport.sendRequest(method: "message.cancel", paramsData: paramsData, timeout: 5.0)
    }

    public func getStatus() async throws -> GoogleCloudSDKResponse {
        try await start()
        return try await transport.sendRequest(method: "runtime.status", paramsData: Data("{}".utf8), timeout: 5.0)
    }
}
