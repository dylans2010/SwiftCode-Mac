import Foundation

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
