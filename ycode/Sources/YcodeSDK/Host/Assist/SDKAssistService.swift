import Foundation
import YcodeExtensions

// MARK: - SDKAssistService
//
// Ported from Legacy `SwiftCode/SDK/Host/Assist/SDKAssistService.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Host-owned Assist sessions for entitled extensions. An extension may
// only touch sessions created under its own verified key, and only with
// tools the host approved at session creation (snapshotted from the
// ACTIVE grants — never extended afterwards).
//
// BACKEND BOUNDARY: `send`, `sendStreaming`, and `executeTool` require a
// real Assist backend. With no backend attached they throw
// `.serviceUnavailable` — the host NEVER fabricates responses, deltas,
// or tool results. Attaching the host's real Assist stack is future
// work; the candidate entry points audited in Legacy (`AssistManager`,
// agent sessions, `LLMService`) were rejected as attachment points
// because they would leak the user's conversation and keys across the
// extension boundary. `SDKAssistBackend` is the seam a future
// attachment must implement — it receives only the extension's own
// session content, never the user's host conversation.

/// The backend a future host attachment must implement to serve
/// entitled Assist sessions. Until one is attached, the service throws
/// `.serviceUnavailable` on every completion attempt.
public protocol SDKAssistBackend: Sendable {
    /// Completes one user message in `session`, returning the assistant
    /// reply text. Receives only the extension's own session content.
    func complete(session: SDKAssistSession, message: String) async throws -> String
    /// Streams a completion. Each element is a text delta; the final
    /// element is the empty string signalling completion.
    func stream(session: SDKAssistSession, message: String) -> AsyncThrowingStream<String, Error>
    /// Executes one approved tool call and returns its output.
    func executeTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult
}

public actor SDKAssistService {
    public static let shared = SDKAssistService()

    /// Bounds (Legacy §13). Violations throw `.invalidArgument`.
    public static let maxMessageBytes = 65_536
    public static let maxHistoryEntries = 200
    public static let maxHistoryEntryBytes = 16_384
    public static let maxToolNameLength = 128
    public static let maxToolArgumentCount = 32
    public static let maxToolArgumentBytes = 16_384

    /// The attached backend, if any. `nil` (the default) means every
    /// completion attempt throws `.serviceUnavailable`.
    public var backend: (any SDKAssistBackend)?

    private struct StoredSession {
        var session: SDKAssistSession
        let keyID: UUID
    }

    private var sessions: [UUID: StoredSession] = [:]
    private let permissions: PermissionManager

    public init(permissions: PermissionManager = PermissionManager()) {
        self.permissions = permissions
    }

    // MARK: - Entitlement

    /// Requires the `developerAIAssist` entitlement on a VERIFIED key
    /// record — the record `SDKAPIKeyStore.verify` returned, never a
    /// caller-supplied claim. Denial uses the verbatim §13 message and
    /// is audited as `assistDenied`.
    public func requireAssistEntitlement(key: SDKAPIKey, extensionID: String) async throws {
        guard key.entitlements.contains(.developerAIAssist) else {
            await SDKAuditLog.shared.record(.assistDenied, extensionID: extensionID, detail: "key \(key.id.uuidString)")
            throw SDKError(code: .assistDenied, message: SDKAssistGate.assistDeniedUserMessage)
        }
    }

    // MARK: - Sessions

    /// Creates a session. Snapshots the extension's ACTIVE grants as
    /// `allowedToolIDs`: an SDK capability is allowed only when ALL of
    /// its mapped v2 capabilities are currently granted (conservative,
    /// deny-by-default). The snapshot is never extended afterwards.
    public func createSession(
        key: SDKAPIKey,
        extensionID: String,
        options: SDKAssistSessionOptions
    ) async throws -> SDKAssistSession {
        try await requireAssistEntitlement(key: key, extensionID: extensionID)
        try validate(options: options)
        let granted = Set(permissions.grantedCapabilities(for: extensionID))
        var allowed: [String] = []
        for capability in SDKCapabilityID.allCases {
            let mapped = ExtensionCapability.v2Capabilities(for: capability)
            guard !mapped.isEmpty, mapped.allSatisfy({ granted.contains($0) }) else { continue }
            allowed.append(capability.rawValue)
        }
        let session = SDKAssistSession(
            extensionID: extensionID,
            title: options.title,
            systemPrompt: options.systemPrompt,
            model: options.model,
            allowedToolIDs: allowed.sorted()
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

    /// Returns a live session the caller owns. Unknown ID →
    /// `.invalidArgument`; another extension's session →
    /// `.permissionDenied`; closed session → `.invalidArgument`.
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

    // MARK: - Completion (backend boundary)

    /// Sends a message. With no backend attached, throws
    /// `.serviceUnavailable` after all validation — never a fabricated
    /// reply. The user message is appended to the session history only
    /// when a backend actually serves it.
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

    /// Streams a completion. With no backend attached, yields `.started`
    /// then `.failed(.serviceUnavailable)` — never fabricated deltas.
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
                    for try await delta in backend.stream(session: session, message: message) {
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

    /// Executes one approved tool call. The tool must be in the session's
    /// snapshot `allowedToolIDs`; otherwise `.permissionDenied`. With no
    /// backend attached, throws `.serviceUnavailable` — never a
    /// fabricated tool result.
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

    // MARK: - Close (host-owned cleanup, no entitlement check by design)

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

    /// Closes every session owned by `keyID` (revocation hook).
    public func closeSessions(forKeyID keyID: UUID) {
        for (id, stored) in sessions where stored.keyID == keyID {
            var updated = stored
            updated.session.isClosed = true
            sessions[id] = updated
        }
    }

    /// Closes every session owned by `extensionID` (uninstall hook).
    public func closeSessions(forExtensionID extensionID: String) {
        for (id, stored) in sessions where stored.session.extensionID == extensionID {
            var updated = stored
            updated.session.isClosed = true
            sessions[id] = updated
        }
    }

    // MARK: - Validation

    /// Appends a completed exchange to a session's history. Actor-isolated
    /// helper for the streaming path, which runs outside actor isolation.
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
