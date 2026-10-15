//
//  MetaAssistProvider.swift
//  SwiftCode
//
//  "Assist with Meta" provider implementation powered by Muse Code SDK.
//  Public UI identity is strictly "Assist with Meta".
//

import Foundation

@MainActor
public final class MetaAssistProvider: Sendable {
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
        let isConfigured = MuseCodeCLIHelper.shared.isInstalled()
        let hasCreds = await MuseCodeCLIHelper.shared.checkCredentials()
        let isAvailable = isConfigured && hasCreds

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
        let isInstalled = MuseCodeCLIHelper.shared.isInstalled()
        if !isInstalled {
            throw MuseCodeCLIError.executableNotFound
        }

        let hasCreds = await MuseCodeCLIHelper.shared.checkCredentials()
        if !hasCreds {
            do {
                _ = try await MuseCodeCLIHelper.shared.runLoginFlow()
            } catch {
                throw MuseCodeCLIError.executionFailed(exitCode: 2, stderr: "Authentication required for Assist with Meta. Please log in via CLI.")
            }
        }

        let bridge = MuseCodeMSPBridge.shared
        try await bridge.startHost(workspaceRoot: workspaceRoot)

        let permissionsManager = AssistPermissionsManager()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bridge.setNotificationHandler { method, params in
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
                        let action = params["action"] as? String ?? "operation"
                        let isAllowed = permissionsManager.authorizeOperation(action)
                        let choice = isAllowed ? "allow_once" : "deny"

                        Task { @MainActor in
                            _ = try? await MuseCodeMSPBridge.shared.sendCommand(method: "approval/decide", params: [
                                "sessionId": sessionId,
                                "approvalId": approvalId,
                                "requirementId": ["approvalId": approvalId, "sourceIndex": 0],
                                "choiceId": choice,
                                "feedback": NSNull()
                            ])
                        }
                    }
                } else if method == "tool/requested" {
                    if let sessionId = params["sessionId"] as? String,
                       let toolCallId = params["toolCallId"] as? String,
                       let toolId = params["toolId"] as? String,
                       let args = params["arguments"] as? [String: Any] {
                        Task { @MainActor in
                            var output = ""
                            var isSuccess = false
                            if permissionsManager.authorizeOperation(toolId) {
                                if let tool = AssistManager.shared.registry.getTool(toolId) {
                                    let rootURL = URL(fileURLWithPath: workspaceRoot)
                                    let logger = AssistLogger()
                                    let context = AssistContext(
                                        sessionId: UUID(),
                                        project: nil,
                                        workspaceRoot: rootURL,
                                        memory: AssistMemoryGraph(),
                                        logger: logger,
                                        fileSystem: AssistFileSystem(workspaceRoot: rootURL),
                                        git: AssistGitManager(project: nil),
                                        permissions: permissionsManager,
                                        safetyLevel: .balanced,
                                        isAutonomous: true
                                    )
                                    do {
                                        let res = try await tool.execute(input: args, context: context)
                                        output = res.output.isEmpty ? (res.error ?? "No output") : res.output
                                        isSuccess = res.success
                                    } catch {
                                        output = error.localizedDescription
                                        isSuccess = false
                                    }
                                } else {
                                    output = "Tool '\(toolId)' not found in SwiftCode registry."
                                }
                            } else {
                                output = "Execution of tool '\(toolId)' denied by permission policy."
                            }

                            _ = try? await MuseCodeMSPBridge.shared.sendCommand(method: "tool/result", params: [
                                "sessionId": sessionId,
                                "toolCallId": toolCallId,
                                "success": isSuccess,
                                "output": output
                            ])
                        }
                    }
                }
            }

            Task { @MainActor in
                do {
                    // 1. Initialize & handshake
                    _ = try await bridge.sendCommand(method: "initialize", params: [
                        "clientInfo": [
                            "name": "swiftcode",
                            "title": "SwiftCode",
                            "version": "1.0.0"
                        ]
                    ])
                    try bridge.sendNotification(method: "initialized", params: [:])

                    // 2. Start Session with canonical UUIDv7 commandId
                    let sessionCmdId = MuseUUIDv7.generate()
                    let sessionRes = try await bridge.sendCommand(method: "session/start", params: [
                        "commandId": sessionCmdId,
                        "workspaceRoot": workspaceRoot
                    ])

                    let sessionId: String
                    if let resultObj = sessionRes["result"] as? [String: Any],
                       let sessionObj = resultObj["session"] as? [String: Any],
                       let id = sessionObj["sessionId"] as? String {
                        sessionId = id
                    } else if let sessionObj = sessionRes["session"] as? [String: Any],
                              let id = sessionObj["sessionId"] as? String {
                        sessionId = id
                    } else if let id = sessionRes["sessionId"] as? String {
                        sessionId = id
                    } else {
                        sessionId = sessionCmdId
                    }
                    self.setActiveSessionID(sessionId)

                    // 3. Start Turn with UUIDv7 commandId
                    let turnCmdId = MuseUUIDv7.generate()
                    _ = try await bridge.sendCommand(method: "turn/start", params: [
                        "commandId": turnCmdId,
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
