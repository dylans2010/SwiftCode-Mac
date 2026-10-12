import Foundation

// MARK: - SDKAssistService
//
// THE host-side owner of headless Assist operations for entitled
// third-party callers (Docs/Intro-to-SDK.md §11 — the `assistSDK`
// variant without UI).
//
// What this service really does:
//   - Owns session lifecycle: create / send / sendStreaming / close, with
//     host-generated session IDs, per-session history, and ownership
//     checks (a session only answers its owning extension ID).
//   - Enforces the key-bound entitlement FIRST on every public method via
//     `requireAssistEntitlement(caller:route:)`, which reads ONLY the
//     verified API key record bound to the caller's session
//     (`caller.apiKey?.entitlements`, i.e. the sibling B3
//     `SDKEntitlement.developerAIAssist`). A manifest claim, package name,
//     or client-code claim of the entitlement is ignored — the code never
//     reads entitlement-ish fields from anywhere but the key record.
//     Absent entitlement → typed `.assistDenied` carrying the VERBATIM
//     §13 user message, plus an audit event. No conversation content or
//     credentials are ever logged.
//   - Validates and bounds every extension-supplied string before the host
//     touches it (mirrors `SDKCloudModelAdapter`'s bounds).
//   - Enforces tool access per approved scope for real: `allowedToolIDs`
//     is snapshotted from the extension's ACTIVE grants at session
//     creation, and `executeTool` denies anything outside that set with
//     `.permissionDenied` before any backend is consulted.
//
// ---------------------------------------------------------------------------
// BACKEND BOUNDARY — read before changing this file.
//
// `send`, `sendStreaming`, and `executeTool` stop at a real, typed
// boundary: there is currently NO per-extension Assist backend they can
// call. The candidates were all audited and rejected:
//
//   - `AssistManager.shared.sendMessage(_:attachments:envelope:)`
//     (SwiftCode/Backend/Assist/AssistManager.swift:328) drives the USER's
//     shared visible conversation (it appends to the same `messages` the
//     user sees in `AssistMainView`), returns `Void`, surfaces errors only
//     through published `lastError`, and takes no caller identity.
//     Routing a third-party call through it would inject the extension's
//     conversation into the user's chat — a cross-principal data leak —
//     and could never return a per-call response.
//   - `AssistManager.shared.agentSession.start(objective:attachments:context:)`
//     (SwiftCode/Backend/Assist/AssistAgentSession.swift:293) is
//     singleton-owned, driven by the user's settings (model, execution
//     mode), and executes tools against the user's machine with no
//     extension caller identity.
//   - `LLMService.sendChatRequest(model:messages:key:providerOverride:)`
//     (SwiftCode/Features/AI/LLMService.swift:576) returns a per-call
//     `LLMResponse`, but spends the USER's configured model and keys and
//     has no caller identity, no per-extension quota, and no Assist tool
//     pipeline.
//
// The missing plumbing is extension caller identity through the real
// Assist choke points (`AssistManager`, `AssistAPIRouter.route`,
// `LLMService`, and the Antigravity bridge) — the same future work
// `SDKAssistGate.swift` names explicitly. Until that lands, these methods
// throw a typed `.serviceUnavailable` naming the missing plumbing. They
// NEVER fabricate a response, a stream delta, or a tool result: a denial
// never invents model output.
//
// Everything up to that boundary — entitlement, validation, session
// bookkeeping, tool-scope policy — is implemented for real.

public actor SDKAssistService {

    public static let shared = SDKAssistService()

    private init() {}

    // MARK: - Input bounds (mirrors SDKCloudModelAdapter)

    /// Max UTF-8 bytes of one user message.
    private static let maxMessageBytes = 64 * 1024
    /// Max history turns retained per session (DoS bound on memory).
    private static let maxHistoryEntries = 200
    /// Max UTF-8 bytes of one history entry's content.
    private static let maxHistoryEntryBytes = 16 * 1024
    /// Max length of a tool name (capability ID).
    private static let maxToolNameLength = 128
    /// Max tool arguments (entries).
    private static let maxToolArgumentCount = 32
    /// Max UTF-8 bytes of one tool argument key or value.
    private static let maxToolArgumentBytes = 16 * 1024

    // MARK: - Session state

    private struct SessionState {
        var session: SDKAssistSession
        var closedAt: Date?
        /// The developer API key bound to the caller's session when this
        /// session was created (`caller.apiKey?.id`). Recorded so an
        /// entitlement revocation (Docs/Intro-to-SDK.md §14) can close
        /// exactly the sessions the revoked key owned. Nil for sessions
        /// created by keyless callers.
        var owningKeyID: UUID?
    }

    private var sessions: [UUID: SessionState] = [:]

    // MARK: - Entitlement boundary

    /// Requires the key-bound `com.SwiftCode.developer-AI-Assist`
    /// entitlement before any Assist operation. The denial message is the
    /// verbatim §13 user error, single-sourced on
    /// `SDKAssistGate.assistDeniedUserMessage` (do not reword).
    /// entitlement before any Assist operation. Reads ONLY the verified
    /// API key record bound to the caller's host-constructed session
    /// identity (`caller.apiKey`, re-verified per request by
    /// `SDKIPCDispatcher`, so entitlement revocation takes effect on the
    /// next call). Manifest claims, package names, and client-code claims
    /// are ignored — they are never consulted.
    ///
    /// - Throws: typed `.assistDenied` carrying the verbatim §13 message
    ///   when the session presents no key or the key lacks the
    ///   entitlement. Audited (no conversation content, no credentials).
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

    // MARK: - Session lifecycle

    /// Creates a headless Assist session for an entitled caller.
    ///
    /// Pipeline: entitlement → validate options → snapshot the
    /// extension's ACTIVE grants as `allowedToolIDs` → store the session
    /// record → return the snapshot.
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

    /// Lists the caller's open headless Assist sessions, oldest first.
    ///
    /// Pipeline: entitlement → filter to live sessions owned by the
    /// caller's extension ID. Cross-extension sessions are never listed.
    public func listSessions(caller: SDKCallerIdentity) async throws -> [SDKAssistSession] {
        try await requireAssistEntitlement(caller: caller, route: "service:listSessions")
        return sessions.values
            .filter { $0.closedAt == nil && $0.session.extensionID == caller.extensionID }
            .map(\.session)
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Looks up a live session and verifies the caller owns it.
    ///
    /// - Throws: `.invalidArgument` for an unknown session ID,
    ///   `.permissionDenied` when the session belongs to another
    ///   extension (cross-extension session handles are never honored),
    ///   `.invalidArgument` when the session is closed.
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

    /// Validates one extension-supplied message. Malformed input is
    /// `.invalidArgument`: the caller is told exactly what to fix, and the
    /// host never forwards unbounded payloads.
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

    // MARK: - Backend boundary

    /// The typed error for the unwired backend (see the file header).
    /// Thrown INSTEAD of fabricating a response — a denial never invents
    /// model output.
    private func backendUnavailableError(route: String) -> SDKError {
        SDKError(
            code: .serviceUnavailable,
            message: "Headless Assist calls are not yet connected to a per-extension backend.",
            suggestion: "The host's Assist choke points (AssistManager, AssistAPIRouter, LLMService) do not yet accept an extension caller identity; until that plumbing lands, headless Assist calls cannot be dispatched. No response was fabricated.",
            diagnostics: ["route": route, "missing": "extension-caller-identity"]
        )
    }

    // MARK: - Send (non-streaming)

    /// Sends one user message on a headless Assist session.
    ///
    /// Pipeline: entitlement → session lookup + ownership → validate
    /// message → BACKEND BOUNDARY (throws `.serviceUnavailable`; see the
    /// file header for why no real backend can be called yet). History is
    /// only mutated for work that was actually dispatched, so nothing is
    /// recorded for the undelivered message.
    public func send(
        sessionID: UUID,
        message: String,
        caller: SDKCallerIdentity
    ) async throws -> SDKAssistResponse {
        try await requireAssistEntitlement(caller: caller, route: "service:send")
        _ = try liveSession(id: sessionID, caller: caller, route: "service:send")
        _ = try validateMessage(message, route: "service:send")
        // BACKEND BOUNDARY: no per-extension Assist backend exists yet.
        // Never fabricate a response.
        throw backendUnavailableError(route: "service:send")
    }

    // MARK: - Send (streaming)

    /// Streams one user message's response on a headless Assist session.
    ///
    /// The entitlement check throws BEFORE the stream is created; the
    /// stream itself opens with `.started` and terminates with `.failed`
    /// at the backend boundary (see the file header). No `.delta` text is
    /// ever fabricated.
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
            // BACKEND BOUNDARY: no per-extension Assist backend exists yet.
            // Never fabricate deltas.
            continuation.yield(.failed(failure))
            continuation.finish()
        }
    }

    // MARK: - Tool access (per approved scope)

    /// Invokes one tool through a headless Assist session.
    ///
    /// Pipeline: entitlement → session lookup + ownership → tool-scope
    /// policy (`toolName` must be in the session's `allowedToolIDs`,
    /// snapshotted from the extension's ACTIVE grants at creation; anything
    /// else is `.permissionDenied`) → validate arguments →
    /// BACKEND BOUNDARY (throws `.serviceUnavailable`; see the file
    /// header). The policy check is real and runs before the boundary.
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

        // BACKEND BOUNDARY: no per-extension Assist tool runtime exists yet.
        // Never fabricate a tool result.
        throw backendUnavailableError(route: "service:executeTool")
    }

    // MARK: - Close

    /// Closes a headless Assist session. Entitlement is still required —
    /// closing is an Assist operation, and a revoked entitlement must not
    /// retain any handle on Assist state. Idempotent for unknown IDs?
    /// No: unknown IDs are `.invalidArgument` (fail loud, never silent).
    public func closeSession(id: UUID, caller: SDKCallerIdentity) async throws {
        try await requireAssistEntitlement(caller: caller, route: "service:closeSession")
        let state = try liveSession(id: id, caller: caller, route: "service:closeSession")
        closeSessionState(id: id, state: state)
    }

    /// Closes every open session created with the developer API key
    /// `keyID`, returning how many were closed.
    ///
    /// THE revocation hook (Docs/Intro-to-SDK.md §14): called from
    /// `SDKAPIKeyStore.revokeEntitlement` (and `revoke(id:)`) AFTER the
    /// entitlement is removed from the persisted key record. Revocation is
    /// already immediate at the authorization boundary (the key metadata is
    /// re-read on every call), so subsequent calls are denied; this closes
    /// the in-flight sessions too, "where safe": no network or backend
    /// work is in flight (the backend boundary is unwired — see the file
    /// header), so closing is pure host-side bookkeeping and always safe.
    /// No entitlement check here BY DESIGN: this is host-owned cleanup,
    /// never an extension-facing operation.
    public func closeSessions(forKeyID keyID: UUID) -> Int {
        // Collect IDs first: mutating `sessions` while iterating it is a
        // runtime trap.
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

    /// Closes every open session owned by `extensionID`, returning how
    /// many were closed. Called from `SDKExtensionManager.uninstall`:
    /// uninstalling the app closes its Assist sessions along with removing
    /// its entitlement bindings.
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

    /// Marks one session closed, preserving its record. Shared by
    /// `closeSession`, `closeSessions(forKeyID:)`, and
    /// `closeSessions(forExtensionID:)`.
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
