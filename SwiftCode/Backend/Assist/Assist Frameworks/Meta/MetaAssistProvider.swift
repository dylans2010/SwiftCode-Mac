//
//  MetaAssistProvider.swift
//  SwiftCode
//
//  "Assist with Meta" provider implementation powered by Muse Code SDK.
//  Public UI identity is strictly "Assist with Meta".
//

import Foundation

public actor MetaAssistProvider {
    public static let shared = MetaAssistProvider()

    public static let providerID = "meta_assist"
    public static let providerName = "Assist with Meta"
    public static let defaultModelID = "meta-code-3.0"

    private var activeSessionID: String?

    private init() {}

    private func setActiveSessionID(_ id: String) {
        self.activeSessionID = id
    }

    /// Returns available models for "Assist with Meta".
    public func discoverModels() async -> [AssistAvailableModel] {
        let isConfigured = await MuseCodeCLIHelper.shared.isInstalled()
        let isAvailable = isConfigured && (await MuseCodeCLIHelper.shared.checkCredentials())

        let status: AssistModelStatus = isAvailable ? .available : (isConfigured ? .authRequired : .unavailable)
        let statusDesc = isAvailable ? "Available" : (isConfigured ? "Authentication Required" : "CLI Not Installed")

        return [
            AssistAvailableModel(
                id: "meta-code-3.0",
                displayName: "Meta Code 3.0",
                providerID: Self.providerID,
                providerName: Self.providerName,
                modelIdentifier: "meta-code-3.0",
                source: .custom,
                isConfigured: isConfigured,
                isAvailable: isAvailable,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsVision: false,
                supportsStructuredOutput: true,
                supportsAgenticUse: true,
                supportsSubagents: true,
                priority: 90,
                statusDescription: statusDesc,
                status: status,
                contextWindow: 128_000
            )
        ]
    }

    /// Initializes host session and executes prompt turn streaming text output back.
    public func executeTurn(
        prompt: String,
        workspaceRoot: String,
        onTextDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let isInstalled = await MuseCodeCLIHelper.shared.isInstalled()
        if !isInstalled {
            throw MuseCodeCLIError.executableNotFound
        }

        let hasCreds = await MuseCodeCLIHelper.shared.checkCredentials()
        if !hasCreds {
            // Attempt login or inform auth required
            let result = try await MuseCodeCLIHelper.shared.runCommand(args: ["account", "read"])
            if !result.isSuccess {
                throw MuseCodeCLIError.executionFailed(exitCode: result.exitCode, stderr: "Authentication required for Assist with Meta. Please log in via CLI.")
            }
        }

        let bridge = MuseCodeMSPBridge.shared
        try await bridge.startHost(workspaceRoot: workspaceRoot)

        // Set up notification listener
        await bridge.setNotificationHandler { method, params in
            if method == "item/delta" {
                if let delta = params["delta"] as? String {
                    onTextDelta(delta)
                } else if let deltaObj = params["delta"] as? [String: Any], let text = deltaObj["text"] as? String {
                    onTextDelta(text)
                }
            } else if method == "approval/requested" {
                // Auto-approve or resolve permission
                if let sessionId = params["sessionId"] as? String,
                   let approvalId = params["approvalId"] as? String {
                    Task {
                        _ = try? await MuseCodeMSPBridge.shared.sendCommand(method: "approval/decide", params: [
                            "sessionId": sessionId,
                            "approvalId": approvalId,
                            "requirementId": ["approvalId": approvalId, "sourceIndex": 0],
                            "choiceId": "allow_once",
                            "feedback": NSNull()
                        ])
                    }
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                await bridge.setNotificationHandler { method, params in
                    if method == "item/delta" {
                        if let delta = params["delta"] as? String {
                            onTextDelta(delta)
                        } else if let deltaObj = params["delta"] as? [String: Any], let text = deltaObj["text"] as? String {
                            onTextDelta(text)
                        }
                    } else if method == "turn/completed" {
                        continuation.resume(returning: ())
                    } else if method == "approval/requested" {
                        if let sessionId = params["sessionId"] as? String,
                           let approvalId = params["approvalId"] as? String {
                            Task {
                                _ = try? await MuseCodeMSPBridge.shared.sendCommand(method: "approval/decide", params: [
                                    "sessionId": sessionId,
                                    "approvalId": approvalId,
                                    "requirementId": ["approvalId": approvalId, "sourceIndex": 0],
                                    "choiceId": "allow_once",
                                    "feedback": NSNull()
                                ])
                            }
                        }
                    }
                }

                do {
                    // 1. Initialize
                    _ = try await bridge.sendCommand(method: "initialize", params: [
                        "clientInfo": ["name": "SwiftCode", "version": "1.0.0"]
                    ])

                    // 2. Start Session
                    let sessionRes = try await bridge.sendCommand(method: "session/start", params: [
                        "workspaceRoot": workspaceRoot
                    ])

                    let sessionId: String
                    if let sessionObj = sessionRes["session"] as? [String: Any], let id = sessionObj["sessionId"] as? String {
                        sessionId = id
                    } else if let id = sessionRes["sessionId"] as? String {
                        sessionId = id
                    } else {
                        sessionId = UUID().uuidString
                    }
                    await self.setActiveSessionID(sessionId)

                    // 3. Start Turn
                    _ = try await bridge.sendCommand(method: "turn/start", params: [
                        "sessionId": sessionId,
                        "input": [["type": "text", "text": prompt]]
                    ])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Cancels current active turn.
    public func cancelTurn() async {
        guard let sessionId = activeSessionID else { return }
        _ = try? await MuseCodeMSPBridge.shared.sendCommand(method: "turn/cancel", params: [
            "sessionId": sessionId
        ])
    }
}
