import Foundation
import SwiftCodeExtensions

public protocol SDKAssistBackend: Sendable {
    func complete(session: SDKAssistSession, message: String) async throws -> String
    func stream(session: SDKAssistSession, message: String) async -> AsyncThrowingStream<String, Error>
    func executeTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult
}

public actor SDKAssistService {
    public static let shared = SDKAssistService()

    public static let maxMessageBytes = 65_536
    public static let maxHistoryEntries = 200
    public static let maxHistoryEntryBytes = 16_384
    public static let maxToolNameLength = 128
    public static let maxToolArgumentCount = 32
    public static let maxToolArgumentBytes = 16_384

    public var backend: (any SDKAssistBackend)?

    public func setBackend(_ backend: (any SDKAssistBackend)?) {
        self.backend = backend
    }

    private struct StoredSession {
        var session: SDKAssistSession
        let keyID: UUID
    }

    private var sessions: [UUID: StoredSession] = [:]
    private let permissions: PermissionManager

    public init(permissions: PermissionManager = PermissionManager()) {
        self.permissions = permissions
    }

    public func requireAssistEntitlement(key: SDKAPIKey, extensionID: String) async throws {
        guard key.entitlements.contains(.developerAIAssist) else {
            await SDKAuditLog.shared.record(.assistDenied, extensionID: extensionID, detail: "key \(key.id.uuidString)")
            throw SDKError(code: .assistDenied, message: SDKAssistGate.assistDeniedUserMessage)
        }
    }

    public func liveAllowedToolIDs(for extensionID: String) -> [String] {
        let granted = Set(permissions.grantedCapabilities(for: extensionID))
        var allowed: [String] = []
        for capability in SDKCapabilityID.allCases {
            let mapped = ExtensionCapability.v2Capabilities(for: capability)
            guard !mapped.isEmpty, mapped.allSatisfy({ granted.contains($0) }) else { continue }
            allowed.append(capability.rawValue)
        }
        return allowed.sorted()
    }

    public func createSession(
        key: SDKAPIKey,
        extensionID: String,
        options: SDKAssistSessionOptions
    ) async throws -> SDKAssistSession {
        try await requireAssistEntitlement(key: key, extensionID: extensionID)
        try validate(options: options)
        let session = SDKAssistSession(
            extensionID: extensionID,
            title: options.title,
            systemPrompt: options.systemPrompt,
            model: options.model,
            allowedToolIDs: liveAllowedToolIDs(for: extensionID)
        )
        sessions[session.id] = StoredSession(session: session, keyID: key.id)
        return session
    }

    public func listSessions(forExtensionID extensionID: String) -> [SDKAssistSession] {
        sessions.values
            .filter { $0.session.extensionID == extensionID }
            .map(\.session)
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func liveSession(id: UUID, extensionID: String) throws -> SDKAssistSession {
        guard let stored = sessions[id] else {
            throw SDKError(code: .invalidArgument, message: "The Assist session does not exist.")
        }
        guard stored.session.extensionID == extensionID else {
            throw SDKError(code: .permissionDenied, message: "The Assist session belongs to another extension.")
        }
        guard !stored.session.isClosed else {
            throw SDKError(code: .invalidArgument, message: "The Assist session is closed.")
        }
        return stored.session
    }

    public func send(
        sessionID: UUID,
        key: SDKAPIKey,
        extensionID: String,
        message: String
    ) async throws -> SDKAssistResponse {
        try await requireAssistEntitlement(key: key, extensionID: extensionID)
        var session = try liveSession(id: sessionID, extensionID: extensionID)
        try validateMessage(message, in: session)
        guard let backend else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "The host Assist backend is not attached. Try again later."
            )
        }
        let text = try await backend.complete(session: session, message: message)
        session.messages.append(SDKAssistMessage(role: .user, content: message))
        session.messages.append(SDKAssistMessage(role: .assistant, content: text))
        sessions[sessionID]?.session = session
        return SDKAssistResponse(sessionID: sessionID, text: text)
    }

    public func sendStreaming(
        sessionID: UUID,
        key: SDKAPIKey,
        extensionID: String,
        message: String
    ) -> AsyncThrowingStream<SDKAssistStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await requireAssistEntitlement(key: key, extensionID: extensionID)
                    let session = try await liveSession(id: sessionID, extensionID: extensionID)
                    try await validateMessage(message, in: session)
                    guard let backend = await self.backend else {
                        continuation.yield(.started)
                        continuation.yield(.failed(SDKError(
                            code: .serviceUnavailable,
                            message: "Assist is not available for extensions right now.",
                            suggestion: "The host Assist backend is not attached. Try again later."
                        )))
                        continuation.finish()
                        return
                    }
                    continuation.yield(.started)
                    var fullText = ""
                    for try await delta in await backend.stream(session: session, message: message) {
                        fullText += delta
                        continuation.yield(.delta(delta))
                    }
                    await self.recordExchange(sessionID: sessionID, userMessage: message, assistantText: fullText)
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error as? SDKError ?? SDKError(code: .serviceUnavailable, message: error.localizedDescription)))
                    continuation.finish()
                }
            }
        }
    }

    public func executeTool(
        sessionID: UUID,
        key: SDKAPIKey,
        extensionID: String,
        call: SDKAssistToolCall
    ) async throws -> SDKAssistToolResult {
        try await requireAssistEntitlement(key: key, extensionID: extensionID)
        let session = try liveSession(id: sessionID, extensionID: extensionID)
        guard call.toolName.count <= Self.maxToolNameLength, !call.toolName.isEmpty else {
            throw SDKError(code: .invalidArgument, message: "The tool name is invalid.")
        }
        guard call.arguments.count <= Self.maxToolArgumentCount else {
            throw SDKError(code: .invalidArgument, message: "Too many tool arguments.")
        }
        for (_, value) in call.arguments {
            guard value.utf8.count <= Self.maxToolArgumentBytes else {
                throw SDKError(code: .invalidArgument, message: "A tool argument is too large.")
            }
        }
        guard session.allowedToolIDs.contains(call.toolName) else {
            throw SDKError(code: .permissionDenied, message: "The tool is not approved for this session.")
        }
        guard let backend else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "The host Assist backend is not attached. Try again later."
            )
        }
        return try await backend.executeTool(session: session, call: call)
    }

    public func closeSession(id: UUID, extensionID: String) throws {
        guard var stored = sessions[id] else {
            throw SDKError(code: .invalidArgument, message: "The Assist session does not exist.")
        }
        guard stored.session.extensionID == extensionID else {
            throw SDKError(code: .permissionDenied, message: "The Assist session belongs to another extension.")
        }
        stored.session.isClosed = true
        sessions[id] = stored
    }

    public func closeSessions(forKeyID keyID: UUID) -> Int {
        var closed = 0
        for (id, stored) in sessions where stored.keyID == keyID && !stored.session.isClosed {
            var updated = stored
            updated.session.isClosed = true
            sessions[id] = updated
            closed += 1
        }
        return closed
    }

    public func closeSessions(forExtensionID extensionID: String) -> Int {
        var closed = 0
        for (id, stored) in sessions where stored.session.extensionID == extensionID && !stored.session.isClosed {
            var updated = stored
            updated.session.isClosed = true
            sessions[id] = updated
            closed += 1
        }
        return closed
    }

    private func recordExchange(sessionID: UUID, userMessage: String, assistantText: String) {
        guard var stored = sessions[sessionID] else { return }
        stored.session.messages.append(SDKAssistMessage(role: .user, content: userMessage))
        stored.session.messages.append(SDKAssistMessage(role: .assistant, content: assistantText))
        sessions[sessionID] = stored
    }

    private func validate(options: SDKAssistSessionOptions) throws {
        if let title = options.title, title.count > 256 {
            throw SDKError(code: .invalidArgument, message: "The session title is too long.")
        }
        if let systemPrompt = options.systemPrompt, systemPrompt.utf8.count > 16_384 {
            throw SDKError(code: .invalidArgument, message: "The system prompt is too long.")
        }
        if let model = options.model, model.count > 256 {
            throw SDKError(code: .invalidArgument, message: "The model identifier is too long.")
        }
    }

    private func validateMessage(_ message: String, in session: SDKAssistSession) throws {
        guard message.utf8.count <= Self.maxMessageBytes, !message.isEmpty else {
            throw SDKError(code: .invalidArgument, message: "The message is empty or too large.")
        }
        guard session.messages.count < Self.maxHistoryEntries else {
            throw SDKError(code: .invalidArgument, message: "The session history is full.")
        }
        for entry in session.messages {
            guard entry.content.utf8.count <= Self.maxHistoryEntryBytes else {
                throw SDKError(code: .invalidArgument, message: "A history entry is too large.")
            }
        }
    }
}
