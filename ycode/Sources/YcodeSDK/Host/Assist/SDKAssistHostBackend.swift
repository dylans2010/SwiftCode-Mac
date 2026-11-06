import Foundation
import YcodeAssistant

// MARK: - SDKAssistHostBackend
//
// The safe attachment point for the host Assist backend (Wave 16,
// Slice C). `SDKAssistService` throws `.serviceUnavailable` until a
// backend is attached; this type is the attachment, and it is
// deliberately narrow:
//
//   - It serves `complete` / `stream` ONLY, through Ycode's own
//     `AssistantProvider.send(ChatRequest)` — one fresh `ChatRequest`
//     built from the extension's OWN session (its system prompt, its
//     own messages, the new message). It never touches the host's
//     conversation store, the user's visible chat, or any host session.
//   - It never receives, reads, or returns an API key. The provider
//     comes from the installed `SDKAssistProviderResolving` resolver,
//     which builds it from the host's settings + secret store; the key
//     stays inside the provider. `ChatRequest` has no key field.
//   - It serves text-completion providers ONLY (Ollama, llama.cpp,
//     OpenAI, OpenRouter, Foundation Models, SwiftCode Cloud). Agent
//     providers (Claude Code, Codex, Antigravity, ACP agents, Hermes,
//     OpenCode, Meta Assist) run tools on the user's machine outside
//     the extension's granted set, so they are refused with
//     `.serviceUnavailable` — never silently downgraded.
//   - `workingDirectory` is always `nil`: no provider may run tools
//     in a directory on the extension's behalf. `.activity` events
//     (host agent activity) are dropped, never forwarded.
//   - It holds NO conversation state and stores NO results: a turn's
//     text flows back through `SDKAssistService` to the owning
//     session only. Caller A cannot see caller B's results because
//     the service enforces session ownership BEFORE calling this
//     backend, and this backend never retains anything to leak.
//   - `executeTool` runs through the installed grant-enforcing
//     tool runner (`SDKAssistToolRunning`, Wave 17, Slice B — see
//     `SDKAssistToolRunner.swift`): the backend checks the closed
//     session, the session snapshot, and the live grants, then the
//     runner maps the capability to its MCP tools and runs one
//     through the host's existing approval flow with the
//     extension's caller identity attached. No runner installed
//     means `.serviceUnavailable`, exactly as before — never a
//     fabricated tool result.
//
// Entitlement and ownership are NOT re-checked here on purpose: the
// service checks the verified-key entitlement and the session
// ownership before every backend call, and key revocation closes
// the sessions (`SDKAPIKeyStore` revocation hook). This backend
// trusts only what the service passes it — an already-checked
// session — and never re-derives identity from caller data. The one
// check it does itself is `session.isClosed`, so a stale session
// passed directly (bypassing the service) still fails.
//
// Provider failures are mapped to a generic `.serviceUnavailable`
// (the provider's message never crosses the extension boundary);
// the underlying failure is logged host-side to the developer log
// with identifiers only (provider kind, session ID, error type —
// never message content).

/// The resolved host provider for one extension turn.
public struct SDKAssistProviderResolution: Sendable {
    /// The host provider to run the turn through. Built by the
    /// resolver from host settings + secret store; the caller never
    /// sees the credentials inside it.
    public let provider: any AssistantProvider
    /// The model to request, or `nil` for the provider's default.
    /// Already folded with the session's requested model by the
    /// resolver (session model wins when set).
    public let modelID: String?

    public init(provider: any AssistantProvider, modelID: String?) {
        self.provider = provider
        self.modelID = modelID
    }
}

/// Resolves the host provider for an extension session. Installed by
/// the host UI at startup (YcodeUI's `YcodeSDKAssistResolver`, built
/// on `CodingAssistantServices`). The backend never builds a provider
/// itself — it has no access to host settings or the secret store.
public protocol SDKAssistProviderResolving: Sendable {
    func resolveProvider(for session: SDKAssistSession) async throws -> SDKAssistProviderResolution
}

public actor SDKAssistHostBackend: SDKAssistBackend {
    public static let shared = SDKAssistHostBackend()

    /// Providers whose `send` is a plain text completion. Only these
    /// may serve extension turns.
    public static let textCompletionProviderKinds: Set<ProviderKind> = [
        .ollama, .llamaCpp, .openAI, .openRouter, .foundationModels, .scCloud,
    ]

    /// Providers refused for extension turns: they run an agent (CLI
    /// or server) that executes tools on the user's machine outside
    /// the extension's granted capabilities. Refusal is
    /// `.serviceUnavailable`, never a silent downgrade.
    public static let agentProviderKinds: Set<ProviderKind> = [
        .claudeCode, .codex, .antigravity, .acpAgent, .hermes, .openCode, .metaAssist,
    ]

    /// Host instructions when the session carries no system prompt.
    /// Host-supplied, never extension-controlled; states the limits
    /// of the turn (no tools, no files, no host conversation).
    public static let defaultInstructions =
        "Answer the user's message directly. You are replying on behalf of an IDE extension; you have no tools and no access to the user's files or conversation."

    private var resolver: (any SDKAssistProviderResolving)?
    /// The grant-enforcing tool runner (Wave 17, Slice B), installed
    /// by the host UI at startup alongside the provider resolver.
    /// Nil means `executeTool` throws `.serviceUnavailable` — the
    /// backend never runs a tool without a runner that enforces the
    /// caller's grants through the host's approval flow.
    private var toolRunner: (any SDKAssistToolRunning)?

    public init(resolver: (any SDKAssistProviderResolving)? = nil) {
        self.resolver = resolver
    }

    /// Installs the host provider resolver (called once at startup).
    public func install(resolver: any SDKAssistProviderResolving) {
        self.resolver = resolver
    }

    /// Installs the grant-enforcing tool runner (called once at
    /// startup, by the host UI). Replaces any previous runner.
    public func install(toolRunner: any SDKAssistToolRunning) {
        self.toolRunner = toolRunner
    }

    // MARK: - Completion

    public func complete(session: SDKAssistSession, message: String) async throws -> String {
        guard !session.isClosed else {
            throw SDKError(code: .invalidArgument, message: "The Assist session is closed.")
        }
        let (provider, modelID) = try await resolveTextProvider(for: session)
        let request = Self.request(for: session, message: message, modelID: modelID)
        var text = ""
        do {
            for try await event in provider.send(request) {
                if case .text(let delta) = event { text += delta }
                if case .finished = event { break }
                // `.activity` (host agent activity) and `.truncated`
                // are dropped: the extension receives only reply text.
            }
        } catch {
            throw await Self.mapProviderError(error, providerKind: provider.kind, session: session)
        }
        return text
    }

    public func stream(session: SDKAssistSession, message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !session.isClosed else {
                        throw SDKError(code: .invalidArgument, message: "The Assist session is closed.")
                    }
                    let (provider, modelID) = try await self.resolveTextProvider(for: session)
                    let request = Self.request(for: session, message: message, modelID: modelID)
                    do {
                        for try await event in provider.send(request) {
                            if case .text(let delta) = event { continuation.yield(delta) }
                            if case .finished = event { break }
                        }
                    } catch {
                        throw await Self.mapProviderError(error, providerKind: provider.kind, session: session)
                    }
                    // The final element is the empty string signalling
                    // completion (see `SDKAssistBackend.stream`).
                    continuation.yield("")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Tool execution (grant-enforcing runner)

    /// Executes one tool call through the installed grant-enforcing
    /// runner (Wave 17, Slice B). The checks run in this order, and
    /// every refusal happens BEFORE any approval UI appears and
    /// BEFORE any tool runs:
    ///   1. Closed session → `.invalidArgument`.
    ///   2. No runner installed → `.serviceUnavailable` (the exact
    ///      pre-Wave-17 behaviour: never a fabricated result).
    ///   3. Tool not in the session's snapshot `allowedToolIDs` →
    ///      `.permissionDenied` (the snapshot is the ceiling, fixed
    ///      at session creation from the ACTIVE grants).
    ///   4. Tool no longer in the extension's LIVE grants →
    ///      `.permissionDenied` (a revoked grant closes the path
    ///      even for a session created before the revocation).
    ///   5. The runner maps the capability to its MCP tools,
    ///      re-checks the named tool against the snapshot, and runs
    ///      it through the host's existing approval flow with the
    ///      extension's caller identity attached — a granted write
    ///      still asks the user exactly as a host write would.
    /// Caller isolation holds because the session — and its
    /// snapshot — belongs to exactly one extension: caller A
    /// cannot run with caller B's grants (the service enforces
    /// session ownership before this backend is reached, and this
    /// backend never runs a tool outside the passed session's
    /// snapshot). Runner failures are mapped to a generic
    /// `.serviceUnavailable` (the runner's message never crosses
    /// the extension boundary); `SDKError`s pass through.
    public func executeTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult {
        guard !session.isClosed else {
            throw SDKError(code: .invalidArgument, message: "The Assist session is closed.")
        }
        guard let runner = toolRunner else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "Tool execution for extensions is not attached: no tool runner reachable from the SDK host enforces the extension's granted capabilities."
            )
        }
        guard session.allowedToolIDs.contains(call.toolName) else {
            throw SDKError(code: .permissionDenied, message: "The tool is not approved for this session.")
        }
        if let live = await runner.liveAllowedToolIDs(for: session.extensionID),
           !live.contains(call.toolName) {
            throw SDKError(code: .permissionDenied, message: "The tool is not approved for this session.")
        }
        do {
            return try await runner.runTool(session: session, call: call)
        } catch let error as SDKError {
            throw error
        } catch {
            let failure = SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "The host tool runner could not run the tool."
            )
            await SDKDeveloperLogger.shared.log(
                error: failure,
                diagnostics: [
                    "tool": call.toolName,
                    "session": session.id.uuidString,
                    "underlying": String(describing: type(of: error)),
                ],
                context: ["extension": session.extensionID]
            )
            throw failure
        }
    }

    // MARK: - Private

    /// Resolves a text-completion provider for `session`, or throws
    /// `.serviceUnavailable` (no resolver, agent provider, provider
    /// not ready). `SDKError`s pass through unchanged.
    private func resolveTextProvider(for session: SDKAssistSession) async throws -> (provider: any AssistantProvider, modelID: String?) {
        guard let resolver else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "No Assist provider resolver is installed. The host has not attached its Assist backend yet."
            )
        }
        let resolution = try await resolver.resolveProvider(for: session)
        guard Self.textCompletionProviderKinds.contains(resolution.provider.kind) else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "The configured provider (\(resolution.provider.kind.displayName)) runs an agent on the user's machine and cannot serve extension turns. Choose a text-completion provider in Settings."
            )
        }
        let availability = await resolution.provider.availability()
        guard availability.isReady else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: availability.hint ?? "The configured provider is not ready."
            )
        }
        return (resolution.provider, resolution.modelID)
    }

    /// Builds the turn's request from ONLY the extension's own
    /// session: its system prompt as instructions, its own messages
    /// plus the new message, no working directory (no tool runs),
    /// the host's default output limit.
    private static func request(for session: SDKAssistSession, message: String, modelID: String?) -> ChatRequest {
        var messages = session.messages.map { ChatMessage($0.role == .assistant ? .assistant : .user, $0.content) }
        messages.append(ChatMessage(.user, message))
        return ChatRequest(
            model: modelID,
            instructions: session.systemPrompt ?? defaultInstructions,
            messages: messages,
            workingDirectory: nil,
            generation: .assistantDefault
        )
    }

    /// Maps a provider failure to a generic `.serviceUnavailable`
    /// (the provider's message never crosses the extension
    /// boundary). `SDKError`s pass through unchanged. The underlying
    /// failure is logged host-side with identifiers only — never
    /// message content.
    private static func mapProviderError(_ error: Error, providerKind: ProviderKind, session: SDKAssistSession) async -> SDKError {
        if let sdkError = error as? SDKError { return sdkError }
        let failure = SDKError(
            code: .serviceUnavailable,
            message: "Assist is not available for extensions right now.",
            suggestion: "The host provider (\(providerKind.displayName)) could not complete the request."
        )
        await SDKDeveloperLogger.shared.log(
            error: failure,
            diagnostics: [
                "provider": providerKind.rawValue,
                "session": session.id.uuidString,
                "underlying": String(describing: type(of: error)),
            ],
            context: ["extension": session.extensionID]
        )
        return failure
    }
}
