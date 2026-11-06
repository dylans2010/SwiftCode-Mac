import Foundation

// MARK: - Hermes session runner (parent integration)
//
// The single seam between AssistAgentSession and HermesProvider,
// mirroring AssistSDKSessionRunner's shape for the parts that are
// genuinely shared (SwiftCode prompt construction, tool-event
// publication to SDKToolEventStore under the Assist session id) and
// differing where Hermes genuinely differs:
//
// * No SDK bridge, no tool schemas sent, no native tool execution:
//   Hermes runs its own tools and SwiftCode observes them (see
//   HermesProvider.swift for the full rationale and the approval
//   semantics). The `executeTool` concept from the SDK runner has
//   no Hermes counterpart and is not faked here.
// * No conversation history replay: each task is a fresh Hermes
//   one-shot (no --resume), so a previous SwiftCode task's Hermes
//   session state is never silently resumed. The SwiftCode
//   transcript remains the conversation record.
// * No fallback: a missing executable, an invalid model, or a
//   failed run is an actionable error naming Assist Settings →
//   Hermes, never a silent substitution of another provider.
//
// Cancellation: `cancel()` terminates the provider's child process
// and marks every non-terminal tool row for the run cancelled, so a
// cancelled run never leaves rows stuck in Running or misreports
// as Failed. AssistAgentSession additionally guards its own state
// transition for Hermes cancellations (see its Hermes branch).

@MainActor
public final class HermesSessionRunner {
    private var activeProvider: HermesProvider?
    private var lastSessionKey: String?

    public init() {}

    public func cancel() async {
        await activeProvider?.cancel()
        activeProvider = nil
        if let sessionKey = lastSessionKey {
            SDKToolEventStore.shared.cancelNonTerminal(sessionId: sessionKey)
        }
    }

    /// Runs one Hermes task and returns the model's final text.
    /// Tool events are published to the store as the run proceeds;
    /// the caller (AssistAgentSession) owns posting the final text
    /// to the transcript.
    public func run(
        objective: String,
        context: AssistContext
    ) async throws -> String {
        let systemPrompt = try await AssistSDKSessionRunner.buildSystemPrompt(objective: objective)
        let selectedModel = AssistModelManager.shared.selectedModelID
        guard HermesModelID.parse(selectedModel) != nil else {
            throw HermesError.invalidModelID(selectedModel)
        }
        let sessionKey = context.sessionId.uuidString
        lastSessionKey = sessionKey
        let provider = HermesProvider()
        activeProvider = provider
        defer { activeProvider = nil }
        let request = HermesRunRequest(
            model: selectedModel,
            systemPrompt: systemPrompt,
            userText: objective,
            directory: context.workspaceRoot.path
        )
        let stream = await provider.run(request, onToolEvent: Self.storeEventHandler(sessionKey: sessionKey))
        var streamedText = ""
        for try await delta in stream {
            streamedText += delta
        }
        // The terminal `result` record's text is authoritative (text
        // deltas can stop early on a replay gap); fall back to the
        // streamed deltas, and only then fail — never post a partial
        // or empty reply as if it were complete.
        if let result = await provider.lastResult, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result.text
        }
        guard !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HermesError.runFailed(
                exitCode: 1,
                detail: "The Hermes run completed without a final response. No text was posted."
            )
        }
        return streamedText
    }

    // MARK: - Tool events

    /// Re-keys provider events to the Assist session id (Hermes
    /// tool events carry no SwiftCode session id) and publishes them
    /// to the store. The closure itself is non-isolated and Sendable:
    /// it captures only the session key and hops to the MainActor
    /// store. Hermes events arrive with an empty sessionId from the
    /// provider; the store key is set here, never inside the event
    /// type, so the provider stays session-agnostic.
    private static func storeEventHandler(sessionKey: String) -> @Sendable (SDKToolEvent) -> Void {
        { event in
            let rekeyed = SDKToolEvent(
                id: event.id,
                provider: event.provider,
                sessionId: sessionKey,
                toolCallId: event.toolCallId,
                toolName: event.toolName,
                toolDescription: event.toolDescription,
                source: event.source,
                state: event.state,
                arguments: event.arguments,
                result: event.result,
                error: event.error,
                startedAt: event.startedAt,
                completedAt: event.completedAt
            )
            Task { @MainActor in
                SDKToolEventStore.shared.apply(rekeyed)
            }
        }
    }
}
