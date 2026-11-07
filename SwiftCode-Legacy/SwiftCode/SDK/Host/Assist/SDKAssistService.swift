import Foundation

public actor SDKAssistService {

    public static let shared = SDKAssistService()

    private init() {}

    private static let maxMessageBytes = 64 * 1024
    private static let maxHistoryEntries = 200
    private static let maxHistoryEntryBytes = 16 * 1024
    private static let maxToolNameLength = 128
    private static let maxToolArgumentCount = 32
    private static let maxToolArgumentBytes = 16 * 1024

    private struct SessionState {
        var session: SDKAssistSession
        var closedAt: Date?
        var owningKeyID: UUID?
    }

    private var sessions: [UUID: SessionState] = [:]

    private func requireAssistEntitlement(caller: SDKCallerIdentity, route: String) async throws {
        let key = caller.apiKey
        let entitled = key?.entitlements.contains(.developerAIAssist) ?? false
        guard entitled else {
            let error = SDKError(
                code: .assistDenied,
                message: SDKAssistGate.assistDeniedUserMessage,
                suggestion: "The app developer can apply for Assist access in SwiftCode Studio; only a verified entitlement on the developer's API key unlocks Assist.",
                diagnostics: [
                    "route": route,
                    "keyId": key?.id.uuidString ?? "none",
                ]
            )
            await SDKAuditLog.shared.record(
                type: .assistDenied,
                extensionID: caller.extensionID,
                detail: "assist-sdk:\(route): entitlement com.SwiftCode.developer-AI-Assist absent",
                correlationId: error.correlationId
            )
            throw error
        }
    }

    public func createSession(
        caller: SDKCallerIdentity,
        options: SDKAssistSessionOptions = SDKAssistSessionOptions()
    ) async throws -> SDKAssistSession {
        try await requireAssistEntitlement(caller: caller, route: "service:createSession")

        let grants = await SDKGrantStore.shared.grants(for: caller.extensionID)
        let allowedToolIDs = grants
            .filter { $0.isActive() }
            .map { $0.capability.rawValue }
            .sorted()

        let session = SDKAssistSession(
            extensionID: caller.extensionID,
            title: options.title,
            systemPrompt: options.systemPrompt,
            model: options.model,
            allowedToolIDs: allowedToolIDs
        )
        sessions[session.id] = SessionState(session: session, owningKeyID: caller.apiKey?.id)
        return session
    }

    public func listSessions(caller: SDKCallerIdentity) async throws -> [SDKAssistSession] {
        try await requireAssistEntitlement(caller: caller, route: "service:listSessions")
        return sessions.values
            .filter { $0.closedAt == nil && $0.session.extensionID == caller.extensionID }
            .map(\.session)
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func liveSession(id: UUID, caller: SDKCallerIdentity, route: String) throws -> SessionState {
        guard let state = sessions[id] else {
            throw SDKError(
                code: .invalidArgument,
                message: "No Assist session exists for the given session ID.",
                suggestion: "Create a session with createSession first.",
                diagnostics: ["route": route]
            )
        }
        guard state.session.extensionID == caller.extensionID else {
            throw SDKError(
                code: .permissionDenied,
                message: "This Assist session belongs to a different app.",
                suggestion: "Use a session created by your own app.",
                diagnostics: ["route": route]
            )
        }
        guard state.closedAt == nil else {
            throw SDKError(
                code: .invalidArgument,
                message: "This Assist session is closed.",
                suggestion: "Create a new session with createSession.",
                diagnostics: ["route": route]
            )
        }
        return state
    }

    private func validateMessage(_ message: String, route: String) throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The message must be a non-empty string.",
                suggestion: "Send a message like {\"message\": \"...\"}.",
                diagnostics: ["route": route]
            )
        }
        guard trimmed.utf8.count <= Self.maxMessageBytes else {
            throw SDKError(
                code: .invalidArgument,
                message: "The message is too large (limit \(Self.maxMessageBytes) bytes).",
                suggestion: "Shorten the message and try again.",
                diagnostics: ["route": route]
            )
        }
        return trimmed
    }

    private func backendUnavailableError(route: String) -> SDKError {
        SDKError(
            code: .serviceUnavailable,
            message: "Headless Assist calls are not yet connected to a per-extension backend.",
            suggestion: "The host's Assist choke points (AssistManager, AssistAPIRouter, LLMService) do not yet accept an extension caller identity; until that plumbing lands, headless Assist calls cannot be dispatched. No response was fabricated.",
            diagnostics: ["route": route, "missing": "extension-caller-identity"]
        )
    }

    public func send(
        sessionID: UUID,
        message: String,
        caller: SDKCallerIdentity
    ) async throws -> SDKAssistResponse {
        try await requireAssistEntitlement(caller: caller, route: "service:send")
        _ = try liveSession(id: sessionID, caller: caller, route: "service:send")
        _ = try validateMessage(message, route: "service:send")
        throw backendUnavailableError(route: "service:send")
    }

    public func sendStreaming(
        sessionID: UUID,
        message: String,
        caller: SDKCallerIdentity
    ) async throws -> AsyncStream<SDKAssistStreamEvent> {
        try await requireAssistEntitlement(caller: caller, route: "service:sendStreaming")
        _ = try liveSession(id: sessionID, caller: caller, route: "service:sendStreaming")
        _ = try validateMessage(message, route: "service:sendStreaming")
        let failure = backendUnavailableError(route: "service:sendStreaming")
        return AsyncStream { continuation in
            continuation.yield(.started(sessionID: sessionID))
            continuation.yield(.failed(failure))
            continuation.finish()
        }
    }

    public func executeTool(
        sessionID: UUID,
        toolCall: SDKAssistToolCall,
        caller: SDKCallerIdentity
    ) async throws -> SDKAssistToolResult {
        try await requireAssistEntitlement(caller: caller, route: "service:executeTool")
        let state = try liveSession(id: sessionID, caller: caller, route: "service:executeTool")

        guard toolCall.toolName.count <= Self.maxToolNameLength, !toolCall.toolName.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "The tool name must be a non-empty string of at most \(Self.maxToolNameLength) characters.",
                diagnostics: ["route": "service:executeTool"]
            )
        }
        guard state.session.allowedToolIDs.contains(toolCall.toolName) else {
            throw SDKError(
                code: .permissionDenied,
                message: "This tool is outside the app's approved scope.",
                suggestion: "Only tools covered by the app's active capability grants can be invoked.",
                diagnostics: ["route": "service:executeTool", "tool": toolCall.toolName]
            )
        }
        guard toolCall.arguments.count <= Self.maxToolArgumentCount else {
            throw SDKError(
                code: .invalidArgument,
                message: "Too many tool arguments (limit \(Self.maxToolArgumentCount)).",
                diagnostics: ["route": "service:executeTool"]
            )
        }
        for (key, value) in toolCall.arguments {
            guard key.utf8.count <= Self.maxToolArgumentBytes,
                  value.utf8.count <= Self.maxToolArgumentBytes else {
                throw SDKError(
                    code: .invalidArgument,
                    message: "A tool argument is too large (limit \(Self.maxToolArgumentBytes) bytes per key/value).",
                    diagnostics: ["route": "service:executeTool"]
                )
            }
        }

        throw backendUnavailableError(route: "service:executeTool")
    }

    public func closeSession(id: UUID, caller: SDKCallerIdentity) async throws {
        try await requireAssistEntitlement(caller: caller, route: "service:closeSession")
        let state = try liveSession(id: id, caller: caller, route: "service:closeSession")
        closeSessionState(id: id, state: state)
    }

    public func closeSessions(forKeyID keyID: UUID) -> Int {
        let targets = sessions
            .filter { $0.value.closedAt == nil && $0.value.owningKeyID == keyID }
            .map(\.key)
        var closed = 0
        for id in targets {
            if let state = sessions[id] {
                closeSessionState(id: id, state: state)
                closed += 1
            }
        }
        return closed
    }

    public func closeSessions(forExtensionID extensionID: String) -> Int {
        let targets = sessions
            .filter { $0.value.closedAt == nil && $0.value.session.extensionID == extensionID }
            .map(\.key)
        var closed = 0
        for id in targets {
            if let state = sessions[id] {
                closeSessionState(id: id, state: state)
                closed += 1
            }
        }
        return closed
    }

    private func closeSessionState(id: UUID, state: SessionState) {
        let open = state.session
        sessions[id] = SessionState(
            session: SDKAssistSession(
                id: open.id,
                extensionID: open.extensionID,
                title: open.title,
                systemPrompt: open.systemPrompt,
                model: open.model,
                createdAt: open.createdAt,
                isClosed: true,
                messages: open.messages,
                allowedToolIDs: open.allowedToolIDs
            ),
            closedAt: Date(),
            owningKeyID: state.owningKeyID
        )
    }
}
